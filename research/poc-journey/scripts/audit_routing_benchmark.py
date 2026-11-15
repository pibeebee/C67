#!/usr/bin/env python3
"""Audit typed routing observations and produce a safe aggregate summary."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path

FIELDS = {"caseID", "backend", "policy", "evidenceMode", "outcome", "wallSeconds", "calls", "visited", "requiredRetained", "orderRetained", "deadlineMet", "arithmeticValid", "accessStatus", "searchLimited"}
SYNTHETIC_FIELDS = {"syntheticElapsedSeconds", "syntheticTravelSeconds", "syntheticWaitingSeconds", "syntheticWalkingSeconds", "syntheticPenalty"}


def percentile(values, fraction):
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * fraction) - 1)] if values else None


def audit(rows):
    issues, groups = [], defaultdict(list)
    for i, row in enumerate(rows):
        if not FIELDS.issubset(row) or set(row) - FIELDS - SYNTHETIC_FIELDS:
            issues.append(f"row {i}: unknown/missing export field (possible provider payload)")
            continue
        if set(row) & SYNTHETIC_FIELDS and not row["evidenceMode"].startswith("SYNTHETIC"):
            issues.append(f"row {i}: detailed quality export restricted to synthetic inputs")
        if any(type(row[key]) is not bool for key in ["requiredRetained", "orderRetained", "deadlineMet", "arithmeticValid", "searchLimited"]):
            issues.append(f"row {i}: invalid invariant flag type")
            continue
        if any(not isinstance(row[key], str) or not row[key] for key in ["caseID", "backend", "policy", "evidenceMode", "outcome", "accessStatus"]):
            issues.append(f"row {i}: invalid classification")
            continue
        if type(row["visited"]) is not int or not 0 <= row["visited"] <= 6:
            issues.append(f"row {i}: invalid visit count")
            continue
        if type(row["wallSeconds"]) not in (int, float) or not math.isfinite(row["wallSeconds"]) or row["wallSeconds"] < 0:
            issues.append(f"row {i}: invalid duration")
        if type(row["calls"]) is not int or row["calls"] < 0:
            issues.append(f"row {i}: invalid calls")
        if row["outcome"].startswith("candidate"):
            if row["visited"] == 0:
                issues.append(f"row {i}: candidate has no visits")
            if not all(row[k] for k in ["requiredRetained", "orderRetained", "deadlineMet", "arithmeticValid"]):
                issues.append(f"row {i}: candidate violates a hard invariant")
        if row["outcome"] == "defect":
            issues.append(f"row {i}: expected scenario mismatch")
        if row["evidenceMode"].startswith("SYNTHETIC") and row["accessStatus"] not in {"unverified", "synthetic_only", "platform_access_unverified"}:
            issues.append(f"row {i}: synthetic evidence mislabelled")
        groups[(row["backend"], row["policy"], row["evidenceMode"])].append(row)
    summary = []
    for (backend, policy, evidence), items in sorted(groups.items()):
        completed = [r for r in items if r["outcome"] in {"available", "expected_match"} or r["outcome"].startswith("candidate")]
        timing = [r["wallSeconds"] for r in completed]
        summary.append({"backend": backend, "policy": policy, "evidenceMode": evidence,
                        "n": len(items), "completedN": len(completed), "outcomes": dict(Counter(r["outcome"] for r in items)),
                        "p50Seconds": percentile(timing, .5), "p95Seconds": percentile(timing, .95),
                        "calls": sum(r["calls"] for r in items), "accessStatuses": dict(Counter(r["accessStatus"] for r in items))})
    pairs = defaultdict(dict)
    for row in rows:
        if row.get("policy") in {"baseline", "finalists"}:
            pairs[(row["caseID"], row["backend"], row["evidenceMode"])][row["policy"]] = row
    paired = []
    for (case, backend, mode), variants in pairs.items():
        if len(variants) != 2:
            continue
        a, b = variants["baseline"], variants["finalists"]
        paired.append({"caseID": case, "backend": backend, "evidenceMode": mode,
                       "bothCandidates": all(r["outcome"].startswith("candidate") for r in [a, b]),
                       "baselineOutcome": a["outcome"], "finalistsOutcome": b["outcome"],
                       "callReduction": a["calls"] - b["calls"],
                       "runtimeReductionFraction": 1 - b["wallSeconds"] / a["wallSeconds"] if a["wallSeconds"] > 0 else None,
                       "syntheticElapsedRegretSeconds": b["syntheticElapsedSeconds"] - a["syntheticElapsedSeconds"] if a.get("syntheticElapsedSeconds") is not None and b.get("syntheticElapsedSeconds") is not None else None,
                       "syntheticPreferenceEqual": a.get("syntheticPenalty") == b.get("syntheticPenalty") if "syntheticPenalty" in a and "syntheticPenalty" in b else None})
    return issues, {"groups": summary, "paired": paired, "issues": issues,
                    "boundary": "No field entrance correctness, observed ETA accuracy, cross-provider speed winner or user satisfaction claim. Percentiles show their actual sample size."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("observations", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    rows = json.loads(args.observations.read_text())
    issues, summary = audit(rows)
    args.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"observations": len(rows), "issues": len(issues), "paired": len(summary["paired"])}))
    if issues:
        raise SystemExit("\n".join(issues))


if __name__ == "__main__":
    main()
