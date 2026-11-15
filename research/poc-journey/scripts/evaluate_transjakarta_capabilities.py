#!/usr/bin/env python3
"""Run offline engine probes and report capability gaps without inventing routes."""

import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import io
from itertools import product
import json
from pathlib import Path
import platform
import subprocess
import zipfile

from transjakarta_network_audit import audit_network


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "apps/c67-trip-integration/Packages/TripIntegration"
MANIFEST = PACKAGE / "Tests/TripIntegrationTests/Fixtures/transjakarta-capability-v3.json"
OUTCOMES = {
    "supported_feasible", "supported_conflict", "unsupported_capability",
    "missing_data", "provider_failure", "defect",
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_manifest(path=MANIFEST):
    manifest = json.loads(path.read_text())
    cases = manifest["cases"]
    if manifest["schemaVersion"] != 3 or manifest.get("scope") != "transjakarta_only" or manifest.get("caseCount") != 64 or len(cases) != 64:
        raise ValueError("Expected TJ-only version 3 with exactly 64 core cases")
    if {case["id"] for case in cases} != {f"T{i:02}" for i in range(1, 65)}:
        raise ValueError("Missing or duplicate scenario IDs")
    for case in cases:
        if case.get("operators") != ["Tije"] or case["requiredCapability"] in {"mrt", "krl"}:
            raise ValueError("Active cases must contain TJ services only")
        if case["expectedOutcome"] not in OUTCOMES - {"defect"}:
            raise ValueError("Invalid expected outcome")
        for key in ("origin", "destination", "requiredCapability", "blockingLayer", "assertion"):
            if not case.get(key):
                raise ValueError(f"Missing scenario field {key}")
    return manifest


def inspect_gtfs(path, expected_hash):
    if sha256(path) != expected_hash:
        raise ValueError("Full GTFS ZIP must match the manifest routing snapshot SHA256")
    with zipfile.ZipFile(path) as archive:
        def rows(name):
            if archive.getinfo(name).file_size > 30_000_000:
                raise ValueError(f"Table exceeds inspection bound: {name}")
            with archive.open(name) as source:
                return list(csv.DictReader(io.TextIOWrapper(source, encoding="utf-8-sig", newline="")))

        routes = rows("routes.txt")
        agencies = rows("agency.txt")
        transfers = rows("transfers.txt") if "transfers.txt" in archive.namelist() else []
        trips = rows("trips.txt")
        frequencies = rows("frequencies.txt")
        calls = rows("stop_times.txt")
        stops = rows("stops.txt")
        services = rows("calendar.txt")
        stop_ids = {row["stop_id"] for row in stops}
        service_ids = {row["service_id"] for row in services}
        trip_ids = {row["trip_id"] for row in trips}
        route_ids = {row["route_id"] for row in routes}
        invalid_references = (
            sum(row["route_id"] not in route_ids or row["service_id"] not in service_ids for row in trips)
            + sum(row["stop_id"] not in stop_ids or row["trip_id"] not in trip_ids for row in calls)
            + sum(row["trip_id"] not in trip_ids for row in frequencies)
            + sum(row["from_stop_id"] not in stop_ids or row["to_stop_id"] not in stop_ids for row in transfers)
        )
        candidate_ids = {"1", "1A", "1B", "1E", "6M", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "B14", "B51", "11C", "BW1"}
        candidates = [row for row in routes if row["route_id"] in candidate_ids]
        candidates += [row for row in routes if row["route_desc"] == "Mikrotrans"][:3]
        frequency_modes = Counter(row.get("exact_times", "0") or "0" for row in frequencies)
        return {
            "status": "inspected_pinned_snapshot", "sha256": expected_hash,
            "routeCount": len(routes), "routeCategories": dict(Counter(row["route_desc"] for row in routes)),
            "agencies": [{"id": row["agency_id"], "name": row["agency_name"]} for row in agencies],
            "transferCount": len(transfers),
            "transferTypes": dict(Counter(row["transfer_type"] for row in transfers)),
            "transfersWithMinimumSeconds": sum(bool(row.get("min_transfer_time")) for row in transfers),
            "calendarDatesPresent": "calendar_dates.txt" in archive.namelist(),
            "stopCount": len(stops), "tripCount": len(trips), "stopCallCount": len(calls),
            "invalidReferenceCount": invalid_references,
            "restrictedPickupCount": sum(row.get("pickup_type", "") not in ("", "0") for row in calls),
            "restrictedDropOffCount": sum(row.get("drop_off_type", "") not in ("", "0") for row in calls),
            "exactTimesCounts": dict(frequency_modes),
            "candidateRoutes": [{"id": row["route_id"], "name": row["route_long_name"], "category": row["route_desc"]} for row in candidates],
            "limitations": ["Shared stop names and parent stations are not proof of a traversable transfer.",
                            "No transfer-time, paid-area access or service availability is inferred from proximity.",
                            "This inspects data coverage; it does not run a multi-route router."],
        }


def collect(manifest, directory, swift_exit):
    results, errors = [], []
    for case in manifest["cases"]:
        path = directory / f'{case["id"]}.json'
        if not path.exists():
            errors.append(f'Missing runtime evidence: {case["id"]}')
            continue
        observation = json.loads(path.read_text())
        if observation.get("id") != case["id"] or observation.get("outcome") not in OUTCOMES:
            errors.append(f'Invalid result identity/outcome: {case["id"]}')
        if observation.get("outcome") != case["expectedOutcome"]:
            errors.append(f'Outcome mismatch: {case["id"]}')
        if observation.get("outcome") == "supported_feasible" and not observation.get("generatedJourney"):
            errors.append(f'Feasible result has no generated journey: {case["id"]}')
        if observation.get("outcome") in {"unsupported_capability", "missing_data"} and observation.get("generatedJourney"):
            errors.append(f'Capability gate incorrectly claims a generated journey: {case["id"]}')
        results.append({"scenario": case, "observation": observation})
    sweep_path = directory / "sweep.json"
    sweep = json.loads(sweep_path.read_text()) if sweep_path.exists() else []
    if len(sweep) != 1000 or {row["id"] for row in sweep} != {f"S{i:04}" for i in range(1, 1001)}:
        errors.append("Incomplete or duplicate 1,000-variation runtime evidence")
    for row in sweep:
        outcome = row.get("outcome")
        if outcome not in {"supported_feasible", "supported_conflict"}:
            errors.append(f'Sweep defect: {row.get("id")} {row.get("detail")}')
        if outcome == "supported_feasible" and not all(row.get(key) is not None for key in ("totalSeconds", "patternID", "boardID", "alightID")):
            errors.append(f'Sweep ride proof missing: {row["id"]}')
    # Validate the actual Cartesian product, not only its total row count.
    combinations = {(r["from"], r["to"], r["departure"], r["accessDelayMinutes"], r["walkingComponentSeconds"]) for r in sweep}
    pairs = {(r["from"], r["to"]) for r in sweep}
    departures = {r["departure"] for r in sweep}
    expected = {(a, b, time, delay, duration) for (a, b), time, delay, duration in product(
        pairs, departures, [0, 1, 5, 15, 30], [120, 1201])}
    if len(pairs) != 10 or len(departures) != 10 or combinations != expected or len(combinations) != 1000:
        errors.append("Sweep Cartesian product is not unique")
    if swift_exit != 0:
        errors.append(f"Swift tests failed with exit {swift_exit}")
    return results, sweep, errors


def percentile(values, quantile):
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * quantile)] if ordered else 0


def markdown(report):
    core = report["coreResults"]
    lines = ["# TransJakarta-only capability evaluation — v3", "",
             f'Run: {report["runAtUTC"]}. Manifest: `{report["manifestID"]}`.', "",
             "## Result and interpretation", "",
             f'Runtime assertions: **{"PASS" if not report["errors"] else "FAIL"}**. '
             f'{len(core)}/64 core observations; {report["sweep"]["count"]}/1,000 variation observations.', "",
             "Legacy schema-v1 gate results describe the retained compatibility contract. Active network support and before/after metrics are measured by BuswayImprovementTests. "
             "Only supported_feasible observations with a bus ride establish routing support. "
             "Walking, provider timing and modified services are explicitly synthetic; no live-provider or field-trip claim.", "",
             "| Core outcome | Count |", "| --- | ---: |"]
    lines += [f"| {name} | {count} |" for name, count in sorted(report["coreOutcomeCounts"].items())]
    lines += ["", "## Capability boundary", "",
              "| Capability | Observed boundary |", "| --- | --- |",
              "| Direct corridor-1 BRT outside Blok M | Runtime leg probes; catalog/UI expansion is separate. |",
              "| Same-stop travel | Walking-only control; excluded from successful TJ ride counts. |",
              "| BRT interchanges | Legacy single-route gate tested here; active network one-transfer routing is measured by the paired improvement suite. |",
              "| Non-BRT / Mikrotrans | Legacy single-route gate retained; active network routes are measured in the paired suite. |",
              "| Other TJ categories | Legacy gates retained; active network admits bounded Jakarta patterns. See the paired suite. |",
              "| Citywide itinerary | Existing city catalog and configurable origin enabled; arbitrary uncatalogued venue IDs remain rejected. |",
              "| Wheelchair / custom walking cap | No structured request or verified accessible transfer data. |",
              "| Platform discovery | T39 now reaches the valid third platform through route-aware discovery. |", "",
              "## Full-feed inspection", ""]
    feed = report["fullFeed"]
    if feed["status"] == "inspected_pinned_snapshot":
        lines += [f'Snapshot SHA256: `{feed["sha256"]}`.', "",
                  f'{feed["routeCount"]} routes, {feed["stopCount"]} stop records, {feed["tripCount"]} trip patterns and '
                  f'{feed["stopCallCount"]} stop calls; {feed["invalidReferenceCount"]} invalid references.', "",
                  "| Source service category | Routes |", "| --- | ---: |"]
        lines += [f"| {category} | {count} |" for category, count in sorted(feed["routeCategories"].items())]
        lines += ["", f'{feed["transferCount"]} explicit transfer records; '
                  f'{feed["transfersWithMinimumSeconds"]} provide a minimum transfer duration. '
                  f'calendar_dates present: {feed["calendarDatesPresent"]}. '
                  'The only agency is Tije; every motorized-service scenario in this version targets TJ.', "",
                  f'Pickup-restricted calls: {feed["restrictedPickupCount"]}; drop-off-restricted calls: '
                  f'{feed["restrictedDropOffCount"]}. Frequency exact_times distribution: `{feed["exactTimesCounts"]}`. '
                  'These are concrete importer/runtime requirements for broader coverage; the corridor-1 importer cannot simply be applied unchanged.', "",
                  "| Candidate route from source | Published name | Category |", "| --- | --- | --- |"]
        lines += [f'| {r["id"]} | {r["name"]} | {r["category"]} |' for r in feed["candidateRoutes"]]
        lines += ["", "Candidate presence is data evidence only; transfer paths, entrances and travel times have not been established.", ""]
    else:
        lines += [feed["detail"], ""]
    network = report["networkAudit"]
    lines += ["## TJ network source stress audits", ""]
    if network["status"] == "audited_pinned_tj_network":
        lines += [f'{network["observationCount"]} source observations cover all {network["patternCount"]} trip patterns across {network["routeCount"]} TJ routes.', "",
                  "Eight probes per pattern: call integrity; pickup/drop-off restrictions; weekly calendar/holiday gap; before-opening query; 09:00; 17:00 plus 30-minute access; 00:01 on the next day; and the final frequency-window boundary.", "",
                  "| Source audit outcome | Count |", "| --- | ---: |"]
        lines += [f"| {name} | {count} |" for name, count in sorted(network["outcomeCounts"].items())]
        lines += ["", "| TJ source category | Routes | Patterns |", "| --- | ---: | ---: |"]
        lines += [f'| {category} | {count} | {network["categoryPatternCounts"].get(category, 0)} |' for category, count in sorted(network["categoryRouteCounts"].items())]
        lines += ["", f'{network["sharedBoardingStopCount"]} shared boarding-coordinate candidates were found. '
                  f'{len(network["explicitTransfers"])} explicit transfer records were inspected. '
                  'Neither shared coordinates nor these records establish a safe transfer or a feasible connection.', "",
                  "These are source-only audits with a conservative full-headway assumption. They do not generate application journeys, model door-to-door walks or run a transfer router. Exact-times service and absent holiday exceptions stay explicit gaps. Source observations are stored separately in network-audit.json.", ""]
    else:
        lines += [network["detail"], ""]
    lines += ["## Core scenarios", "",
              "| ID | Intent | Outcome / first blocking layer | Runtime evidence |", "| --- | --- | --- | --- |"]
    for row in core:
        case, observation = row["scenario"], row["observation"]
        clean = lambda text: str(text).replace("|", "/").replace("\n", " ")
        lines.append(f'| {case["id"]} | {clean(case["title"])}: {clean(case["origin"])} → {clean(case["destination"])} | '
                     f'{observation["outcome"]} / {observation["layer"]} | {clean(observation["detail"])} |')
    lines += ["", "## Deterministic stress sweep", "",
              "10 directed coordinate pairs × 10 departure hours × 5 access delays (0/1/5/15/30 minutes) "
              "× 2 base walking durations (120/1,201 seconds). A new planner and provider are created for every row. "
              "Access delay is added to the access walking component, so it can cross the existing 20-minute component cap. "
              "This does not simulate transfer delays, traffic, or actual bus reliability.", "",
              "| Sweep measure | Result |", "| --- | ---: |",
              f'| Feasible bus legs | {report["sweep"]["outcomeCounts"].get("supported_feasible", 0)} |',
              f'| Access/service conflicts | {report["sweep"]["outcomeCounts"].get("supported_conflict", 0)} |',
              f'| Defects | {report["sweep"]["outcomeCounts"].get("defect", 0)} |',
              f'| Calculation p50 / p95, milliseconds | {report["sweep"]["elapsedMillisecondsP50"]:.3f} / {report["sweep"]["elapsedMillisecondsP95"]:.3f} |',
              f'| Maximum synthetic walking calls per variation | {report["sweep"]["maxSyntheticWalkingCalls"]} |',
              f'| Total synthetic walking calls | {report["sweep"]["totalSyntheticWalkingCalls"]} |',
              f'| Longest feasible fixture trip, seconds | {report["sweep"]["maxFeasibleTripSeconds"]:.0f} |', "",
              "Calculation timings measure this local deterministic harness, not live Maps latency or travel-time accuracy. "
              "Request counts refer to synthetic walking calls, including rejected candidate attempts; they are not live network requests.", "",
              "## Next work, ordered by blocking dependency", "",
              "1. Expand the sourced venue catalog and origin contract for citywide end-to-end inputs.",
              "2. Introduce a multi-route feed and ordered multi-ride journey contract with transfer walk/wait evidence; retain service categories.",
              "3. Validate BRT/non-BRT/Mikrotrans interchange access and timing. Full-feed coverage alone does not prove connections.",
              "4. Add explicit service calendars, boarding restrictions, scheduled-service interpretation and supported geographic bounds for the remaining TJ categories.",
              "5. Expose supported constraints and detailed interchange steps in UI; run bounded live checks and field observations.", "",
              "## Reproducibility and limits", "",
              "Raw results, Swift log, source hashes and pinned-feed inspection are kept in this fresh ignored run directory. "
              "The historical snapshot clock is fixed; no source dates are advanced to bypass freshness. "
              "Previous app/device runs are not inherited as evidence for this suite. "
              "No live providers, credentials, paid APIs, production changes, commits, or deployments are used.", ""]
    if report["errors"]:
        lines += ["## Failures", ""] + [f"- {error}" for error in report["errors"]] + [""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="New, non-existing ignored evidence directory")
    parser.add_argument("--gtfs-zip", type=Path, help="Optional captured official ZIP matching the pinned snapshot hash")
    args = parser.parse_args()
    manifest = load_manifest()
    full_feed = inspect_gtfs(args.gtfs_zip, manifest["snapshotSHA256"]) if args.gtfs_zip else {
        "status": "missing_data", "detail": "No full-feed ZIP supplied; runtime tests still use the bundled attributed corridor-1 snapshot."}
    args.output.mkdir(parents=True, exist_ok=False)
    import os
    environment = dict(os.environ, TJ_CAPABILITY_OUTPUT=str(args.output.resolve()))
    command = ["swift", "test", "--package-path", str(PACKAGE), "--filter", "BuswayCapabilityTests"]
    with (args.output / "swift-tests.log").open("w") as log:
        completed = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT, check=False)
    core, sweep, errors = collect(manifest, args.output, completed.returncode)
    if full_feed.get("invalidReferenceCount", 0):
        errors.append("Full-feed inspection found invalid GTFS references")
    network = audit_network(args.gtfs_zip, manifest["snapshotSHA256"], manifest["cases"]) if args.gtfs_zip else {
        "status": "missing_data", "detail": "Full TJ network audit requires the matching captured official ZIP; no broader source coverage is claimed without it."}
    if network.get("invariantFailures"):
        errors.append("TJ source audit found malformed ordered calls or windows")
    if network.get("observationCount") is not None and network["observationCount"] != network["patternCount"] * 8:
        errors.append("Incomplete TJ source-audit matrix")
    (args.output / "network-audit.json").write_text(json.dumps(network, indent=2) + "\n")
    elapsed = [row["elapsedMilliseconds"] for row in sweep]
    report = {
        "schemaVersion": 3, "scope": "transjakarta_only", "manifestID": manifest["id"], "manifestSHA256": sha256(MANIFEST),
        "runAtUTC": datetime.now(timezone.utc).isoformat(), "host": platform.platform(),
        "command": command, "swiftExitCode": completed.returncode, "errors": errors,
        "coreOutcomeCounts": dict(Counter(row["observation"]["outcome"] for row in core)),
        "coreResults": core, "fullFeed": full_feed, "networkAudit": {key: value for key, value in network.items() if key != "observations"},
        "sweep": {"count": len(sweep), "outcomeCounts": dict(Counter(row["outcome"] for row in sweep)),
                  "elapsedMillisecondsP50": percentile(elapsed, .5), "elapsedMillisecondsP95": percentile(elapsed, .95),
                  "maxSyntheticWalkingCalls": max((row["walkingRequests"] for row in sweep), default=0),
                  "totalSyntheticWalkingCalls": sum(row["walkingRequests"] for row in sweep),
                  "maxFeasibleTripSeconds": max((row.get("totalSeconds", 0) for row in sweep if row.get("totalSeconds") is not None), default=0)},
        "sourceHashes": {str(path.relative_to(ROOT)): sha256(path) for path in sorted(
            list((PACKAGE / "Sources/TripIntegration").rglob("*.swift"))
            + list((PACKAGE / "Sources/TripIntegration/Resources").glob("*.json"))
            + [PACKAGE / "Tests/TripIntegrationTests/BuswayCapabilityTests.swift", PACKAGE / "Package.swift", MANIFEST,
               Path(__file__), ROOT / "scripts/test_evaluate_transjakarta_capabilities.py", ROOT / "scripts/transjakarta_network_audit.py",
               ROOT / "scripts/test_transjakarta_network_audit.py", ROOT / "scripts/verify.sh"])},
    }
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.output / "REPORT.md").write_text(markdown(report))
    print(json.dumps({"core": report["coreOutcomeCounts"], "sweep": report["sweep"], "networkAudit": {k: network.get(k) for k in ["routeCount", "patternCount", "observationCount", "outcomeCounts", "invariantFailures"]}, "errors": errors, "report": str(args.output / "REPORT.md")}, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
