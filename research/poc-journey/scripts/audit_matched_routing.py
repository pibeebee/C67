"""Audit derived matched-routing observations; never infer field accuracy."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re


def percentile(values, fraction):
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * fraction) - 1)] if values else None


def audit(data):
    errors = []
    groups = defaultdict(list)
    pair_rows = defaultdict(list)
    row_fields = set("pairID querySHA256 provider mode order outcome wallSeconds pacingSeconds serviceSeconds geometryPoints maximumEndpointGapMeters".split())
    comparison_fields = set("pairID mode bothAvailable valhallaToAppleServiceRatio valhallaToAppleETARatio valhallaToAppleDistanceRatio geometryMedianGapMeters".split())
    outcomes = set("available unavailable invalidInput missingConfiguration missingVisitContext disabledByScope missingAccess privateAccess invalidResponse budgetExhausted authentication throttled transport staleResult deadlineExceeded provider_failure".split())
    def number(value):
        return type(value) in (int, float) and math.isfinite(value) and value >= 0
    if set(data) - set("startedAt appleAPI plannedPairs stoppedReason rows comparisons".split()):
        errors.append("Unexpected output fields")
    for row in data.get("rows", []):
        if set(row) - row_fields or row.get("provider") not in ("apple", "valhalla") or row.get("mode") not in ("walking", "automobile"):
            errors.append("Invalid row schema")
        if not re.fullmatch(r"[0-9a-f]{64}", row.get("querySHA256", "")) or row.get("order") not in (0, 1) or row.get("outcome") not in outcomes:
            errors.append("Invalid identity/order/outcome")
        if any(not number(row.get(k)) for k in ("wallSeconds", "pacingSeconds", "serviceSeconds", "geometryPoints")):
            errors.append("Invalid numeric values")
        elif abs(row["wallSeconds"] - row["pacingSeconds"] - row["serviceSeconds"]) > .001:
            errors.append("Pacing decomposition mismatch")
        if "maximumEndpointGapMeters" in row and not number(row["maximumEndpointGapMeters"]):
            errors.append("Invalid endpoint gap")
        pair_rows[row.get("pairID")].append(row)
        groups[(row.get("provider"), row.get("mode"))].append(row)
    comparisons = data.get("comparisons", [])
    if len(comparisons) != len(pair_rows) or len({c.get("pairID") for c in comparisons}) != len(comparisons):
        errors.append("Comparison coverage mismatch")
    for c in comparisons:
        rows = pair_rows.get(c.get("pairID"), [])
        if set(c) - comparison_fields or type(c.get("bothAvailable")) is not bool:
            errors.append("Invalid comparison schema")
        if len(rows) != 2 or {r.get("provider") for r in rows} != {"apple", "valhalla"} or {r.get("order") for r in rows} != {0, 1} or len({r.get("querySHA256") for r in rows}) != 1 or {r.get("mode") for r in rows} != {c.get("mode")}:
            errors.append("Unmatched pair identity")
            continue
        both = all(r.get("outcome") == "available" for r in rows)
        if c.get("bothAvailable") != both:
            errors.append("Forged availability")
        for key in comparison_fields - {"pairID", "mode", "bothAvailable"}:
            if key in c and (not both or not number(c[key])):
                errors.append("Invalid derived ratio or geometry diagnostic")
        if both:
            a = next(r for r in rows if r["provider"] == "apple")
            v = next(r for r in rows if r["provider"] == "valhalla")
            if a["serviceSeconds"] > 0 and abs(c.get("valhallaToAppleServiceRatio", -1) - v["serviceSeconds"] / a["serviceSeconds"]) > .000001:
                errors.append("Service ratio mismatch")
    planned = data.get("plannedPairs")
    if type(planned) is not int or planned < len(comparisons) or (not data.get("stoppedReason") and planned != len(comparisons)):
        errors.append("Incomplete campaign without stop reason")
    summary = dict(plannedPairs=planned, completedPairs=len(comparisons), bothAvailable=sum(c.get("bothAvailable") is True for c in comparisons), errors=errors, groups=[], comparisons=[])
    if errors:
        return errors, summary
    for (provider, mode), rows in sorted(groups.items()):
        success = [r for r in rows if r["outcome"] == "available"]
        group = dict(provider=provider, mode=mode, attempted=len(rows), available=len(success), outcomes=dict(Counter(r["outcome"] for r in rows)))
        for field in ("serviceSeconds", "wallSeconds", "maximumEndpointGapMeters"):
            values = [r[field] for r in success if field in r]
            group[field] = dict(p50=percentile(values, .5), p95=percentile(values, .95))
        summary["groups"].append(group)
    for mode in ("automobile", "walking"):
        rows = [c for c in comparisons if c["mode"] == mode and c["bothAvailable"]]
        group = dict(mode=mode, matchedSuccessPairs=len(rows))
        for field in comparison_fields - {"pairID", "mode", "bothAvailable"}:
            values = [r[field] for r in rows if field in r]
            group[field] = dict(p50=percentile(values, .5), p95=percentile(values, .95), maximum=max(values) if values else None)
        summary["comparisons"].append(group)
    return errors, summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    errors, summary = audit(json.loads(args.input.read_text()))
    args.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2, sort_keys=True))
    raise SystemExit(bool(errors))


if __name__ == "__main__":
    main()
