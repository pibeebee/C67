#!/usr/bin/env python3
"""Measure paired TJ routing changes and preserve the complete package regression run."""

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

from evaluate_transjakarta_capabilities import collect, load_manifest, percentile, ROOT, PACKAGE


def summarize(rows):
    groups = defaultdict(list)
    for row in rows:
        groups[row["group"]].append(row)
    return {name: {
        "cases": len(values), "beforeFeasible": sum(row["beforeFeasible"] for row in values),
        "afterFeasible": sum(row["afterFeasible"] for row in values),
        "recovered": sum(not row["beforeFeasible"] and row["afterFeasible"] for row in values),
        "regressed": sum(row["beforeFeasible"] and not row["afterFeasible"] for row in values),
        "beforeP50Milliseconds": percentile([row["beforeMilliseconds"] for row in values], .5),
        "afterP50Milliseconds": percentile([row["afterMilliseconds"] for row in values], .5),
        "beforeWalkingCalls": sum(row["beforeRequests"] for row in values),
        "afterWalkingCalls": sum(row["afterRequests"] for row in values),
        "boundedSearchCases": sum(row["searchLimited"] for row in values),
    } for name, values in groups.items()}


def markdown(report):
    lines = ["# TJ itinerary improvements and paired evaluation", "",
             f'Captured {report["runAtUTC"]}. Overall result **{"PASS" if not report["errors"] else "FAIL"}**.', "",
             "## Implemented behavior", "",
             "Platform discovery first checks ordered route connectivity within 800 metres. Up to 64 candidates are evaluated per direct/transfer stage, with a total budget of 128 walking lookups per calculation. The direct search expands beyond the previous nearest-two-platform filter. Walking durations are cached within a calculation and provider errors eligible for retry receive at most one additional attempt under the existing throttle.", "",
             "The default pipeline loads the expanded attributed TJ network. Direct services are preferred, with up to one transfer as a fallback. Transfer candidates originate from identical boarding stops, shared parent stations or explicit recommended GTFS links. Every transfer requires a walking result and an additional authored 120-second buffer before the next full-headway wait. Endpoint and transfer walking components retain the 20-minute policy.", "",
             "For local itinerary legs, provider-verified walking of at most 15 minutes is prioritized. This policy was introduced to keep six-venue calculations inside the request budget. The first expanded-network regression exhausted 128 walking requests on the six-venue case. That failure motivated this policy and is retained in the execution history.", "",
             "The Showcase offers the existing sourced Jakarta catalog alongside Blok M and accepts a configurable origin for live location verification. A visit-time budget appears during setup, selection and review. Impossible total dwell is rejected before location requests. Explicit actions can extend the trip by one hour within the same day or shorten visit durations by 15 minutes, preserving chosen venues for recalculation.", "",
             "## Paired measurements", "",
             "Each pair uses the same departure and synthetic walking model on a frozen pre-change planner and the improved planner. The network group also changes from the original corridor-1 snapshot to the expanded runtime snapshot. Each OD is a diagnostic platform/end-location query.", "",
             "| Group | Cases | Before feasible | After feasible | Recovered | Regressed |",
             "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for name, group in report["groups"].items():
        lines.append(f'| {name} | {group["cases"]} | {group["beforeFeasible"]} | {group["afterFeasible"]} | {group["recovered"]} | {group["regressed"]} |')
    lines += ["", "| Group | Before / after p50, ms | Before / after synthetic walking calls | Cases reaching candidate limit |",
              "| --- | ---: | ---: | ---: |"]
    for name, group in report["groups"].items():
        lines.append(f'| {name} | {group["beforeP50Milliseconds"]:.3f} / {group["afterP50Milliseconds"]:.3f} | '
                     f'{group["beforeWalkingCalls"]} / {group["afterWalkingCalls"]} | {group["boundedSearchCases"]} |')
    lines += ["", "The platform group deliberately places 0–19 closer unusable stops around a valid platform at ten departure hours. These are correlated synthetic adversarial cases. The alternative-destination group uses ten original corridor-1 OD pairs with normal synthetic walking to nearby alternatives. The network group selects one published pattern and usable endpoint pair per imported route at 09:00 WIB. Actual chosen services may differ from the requested source route when an alternative reaches the same destination. The official transfer group restricts the attributed source to the two named corridors so that the connection itself is exercised.", "",
              "These rates measure the fixed test sets. Walking accessibility, real bus waiting, traffic, field transfer entrances and travel accuracy require their own observations. Additional candidates trade calculation work and walking requests for coverage. Per-leg timings exclude planner initialization, source decoding/validation and network I/O. End-to-end pipeline latency includes additional work.", "",
              "## Runtime source coverage", "",
              f'The runtime imports {report["network"]["routes"]} routes, {report["network"]["patterns"]} patterns and {report["network"]["stops"]} stops from the original captured ZIP.', "",
              "| Imported pattern category | Count |", "| --- | ---: |"]
    lines += [f'| {name} | {count} |' for name, count in sorted(report["network"]["categoryPatterns"].items())]
    lines += ["", "The importer retains complete patterns inside the existing Jakarta geographic boundary. Of the original 694 patterns, 149 cross that boundary and one uses exact-times service. These exclusions are recorded instead of clipping patterns or changing service semantics. Broadening the physical coverage and handling scheduled exact-times service remain follow-up work. Published pickup/drop-off restrictions are enforced. The original source date and ZIP hash are retained.", "",
              "## Unresolved paired inputs", "",
              "| Case | Synthetic walking calls | Candidate limit reached | Requested source route calendar |", "| --- | ---: | --- | --- |"]
    for row in report["unresolved"]:
        lines.append(f'| {row["id"]} | {row["afterRequests"]} | {row["searchLimited"]} | {row.get("calendarDiagnosis", "Requires inspection")} |')
    lines += ["", "A nil result can reflect the tested time, access policy, service restrictions or bounded search. The remaining cases require case-specific route/connection inspection before assigning a root cause.", "",
              "## Regression and compatibility", "",
              f'Package verification exit code {report["packageExitCode"]}. The active 64-case compatibility suite and 1,000-input sweep were captured alongside the paired tests.', "",
              f'Core outcome counts `{report["coreOutcomeCounts"]}`. Sweep outcomes `{report["sweepOutcomeCounts"]}`.', "",
              "The legacy single-route feed gate remains covered by the 64-case suite. Its unsupported-gate counts describe that compatibility contract. Active network support is measured by the paired network group above. T39 now verifies recovery of the third valid platform. The explicit over-limit walking cases continue to reject.", "",
              "Old stored journeys decode through the original single-ride fields. A new optional connection retains the second ride, transfer walking, source link and buffer. Storage audit checks source membership and transfer provenance. The UI and Markdown export include both rides; geometry outside the original sidecar appears as stop pins with an availability explanation.", "",
              "Separate regression cases check a missed onward window, missing transfer edge, pickup prohibition, forged onward timing, numeric/coordinate provider failures, transient retry and cancellation, and early dwell infeasibility. Package logs, paired observations and source hashes are retained in this run directory.", "",
              "## Explicit defaults and remaining acceptance", "",
              "One-transfer fallback, the authored two-minute interchange buffer, the 15-minute local-walking priority and bounded candidate/request counts are implementation defaults selected for this POC. A direct feasible service is returned before exploring transfer alternatives. This preserves a bounded search and can miss a faster connecting service.", "",
              "The full-headway buffer remains the acceptance policy. Calibrating waiting uncertainty requires field or verified realtime observations. Accessibility and holiday exceptions remain unresolved. Demo coordinates and weather are synthetic. Live signing, device provider behavior and physical trips require separate acceptance.", ""]
    if report["errors"]:
        lines += ["## Failures", ""] + [f'- {error}' for error in report["errors"]] + [""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=False)
    environment = dict(os.environ, POC_OUTPUT_DIR=str(directory / "packages"),
                       TJ_IMPROVEMENT_OUTPUT=str(directory), TJ_CAPABILITY_OUTPUT=str(directory / "capabilities"))
    with (directory / "verify.log").open("w") as log:
        completed = subprocess.run(["rtk", "proxy", "bash", str(ROOT / "scripts/verify.sh"), "packages"],
                                   env=environment, stdout=log, stderr=subprocess.STDOUT, check=False)
    paired_path = directory / "paired-results.json"
    rows = json.loads(paired_path.read_text()) if paired_path.exists() else []
    groups = summarize(rows)
    errors = []
    expected = {"route_aware_platforms_200": 200, "alternative_destination_platforms_100": 100,
                "network_source_route_endpoints": 199, "official_two_corridor_transfer": 2}
    if {key: value["cases"] for key, value in groups.items()} != expected:
        errors.append("Paired comparison groups incomplete")
    if len({row["id"] for row in rows}) != len(rows):
        errors.append("Duplicate paired inputs")
    if any(group["regressed"] for group in groups.values()):
        errors.append("A paired feasible input regressed")
    core, sweep, capability_errors = collect(load_manifest(), directory / "capabilities", completed.returncode)
    errors += capability_errors
    network = json.loads((PACKAGE / "Sources/TripIntegration/Resources/transjakarta-network.json").read_text())
    services = {service["id"]: service for service in network["services"]}
    test_day = datetime.fromisoformat(network["source"]["checkedAt"].replace("Z", "+00:00")).date() + timedelta(days=1)
    day_string = test_day.strftime("%Y%m%d")
    unresolved = [row for row in rows if not row["afterFeasible"]]
    for row in unresolved:
        if row["group"] != "network_source_route_endpoints":
            continue
        route = row["id"].removeprefix("network-")
        route_services = [services[pattern["serviceID"]] for pattern in network["patterns"] if pattern["routeID"] == route]
        if route_services and all(not (service["startDate"] <= day_string <= service["endDate"] and test_day.isoweekday() in service["weekdays"]) for service in route_services):
            row["calendarDiagnosis"] = f"All patterns for requested route inactive on {test_day.isoformat()} under the published weekly calendar. Alternative search remains bounded."
    report = {
        "schemaVersion": 1, "runAtUTC": datetime.now(timezone.utc).isoformat(), "errors": errors,
        "packageExitCode": completed.returncode, "groups": groups,
        "network": {"source": network["source"], "routes": len({p["routeID"] for p in network["patterns"]}),
                    "patterns": len(network["patterns"]), "stops": len(network["stops"]),
                    "categoryPatterns": dict(Counter(p["category"] for p in network["patterns"]))},
        "unresolved": unresolved,
        "coreOutcomeCounts": dict(Counter(row["observation"]["outcome"] for row in core)),
        "sweepOutcomeCounts": dict(Counter(row["outcome"] for row in sweep)),
        "sourceHashes": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(
            list((PACKAGE / "Sources").rglob("*.swift")) + list((PACKAGE / "Tests").rglob("*.swift"))
            + list((PACKAGE / "Tests").rglob("*.json")) + list((PACKAGE / "Sources").rglob("*.json"))
            + list((ROOT / "apps/c67-journey-showcase/App").glob("*.swift"))
            + list((ROOT / "apps/c67-journey-showcase/Tests").glob("*.swift"))
            + list((ROOT / "apps/c67-journey-showcase/UITests").glob("*.swift"))
            + [Path(__file__), ROOT / "scripts/import_transjakarta_network.py", ROOT / "scripts/test_import_transjakarta_network.py"])},
    }
    (directory / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    (directory / "REPORT.md").write_text(markdown(report))
    print(json.dumps({"groups": groups, "errors": errors, "report": str(directory / "REPORT.md")}, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
