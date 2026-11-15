"""Recompute diagnostics and prepare a human review packet; no provider calls."""
import copy
import importlib.util
import itertools
import json
from pathlib import Path
import statistics
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ordering_experiment", HERE / "run_experiment.py")
experiment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(experiment)


def main():
    inputs = json.loads((HERE / "inputs.json").read_text())
    aliases = inputs["aliases"]
    cases = {row["experimentCaseID"]: row["input"] for row in inputs["cases"]}
    records = json.loads((HERE / "results.json").read_text())
    summary = []
    for record in records:
        key = record["experimentCaseID"]
        case = cases[key]
        assert experiment.validate(key, case, record, aliases) == record["validation"]
        answer = record.get("answer")
        row = dict(case=key, httpStatus=record.get("httpStatus"),
                   seconds=record.get("elapsedSeconds"),
                   structurePassed=record["validation"]["structurePassed"],
                   reportedTokens=(record.get("usage") or {}).get("total_tokens"))
        if answer:
            names = {p["id"]: p["name"] for p in case["places"]}
            row["orderedIDs"] = answer["orderedIDs"]
            row["namesVisibleToModelInOrder"] = [names[x] for x in answer["orderedIDs"]]
            orders = list(itertools.permutations(names))
            if key in {"baseline", "shuffled", "origin-change", "untrusted-name", "baseline-repeat"}:
                compatible = [o for o in orders if o[-1] == aliases["market"]]
                constraint = "market last, matching the explicit supplied wish"
            elif key == "preference-change":
                compatible = [o for o in orders if o[0] == aliases["library"]]
                constraint = "main spot first, matching the explicit supplied wish"
            elif key == "experience-geography-conflict":
                compatible = [o for o in orders if o[0] == aliases["library"] and
                    o.index(aliases["coffee"]) < o.index(aliases["sushi"])]
                constraint = "main spot first; library before coffee before sushi"
            else:
                compatible = orders
                constraint = "none: redacted names cannot ground the market-last preference"
            best = min(experiment.geography(case, order) for order in compatible)
            actual = experiment.geography(case, answer["orderedIDs"])
            row["coordinateDiagnostic"] = dict(selectedOrderKM=round(actual, 3),
                minimumPreferenceCompatibleKM=round(best, 3), ratio=round(actual / best, 3),
                compatibilityFilter=constraint,
                limitation="Straight-line proxy only, not a road distance, ETA or reasonable-order verdict. Not supplied to Luna.")
        summary.append(row)
    by_key = {row["experimentCaseID"]: row for row in records}
    comparison = {}
    if all(key in by_key and by_key[key].get("answer") for key in ["baseline", "shuffled", "baseline-repeat"]):
        comparison = dict(
            baselineEqualsShuffled=by_key["baseline"]["answer"]["orderedIDs"] == by_key["shuffled"]["answer"]["orderedIDs"],
            baselineEqualsRepeat=by_key["baseline"]["answer"]["orderedIDs"] == by_key["baseline-repeat"]["answer"]["orderedIDs"],
            shuffledEqualsRepeat=by_key["shuffled"]["answer"]["orderedIDs"] == by_key["baseline-repeat"]["answer"]["orderedIDs"])
    document = dict(attempted=len(records), completed=sum("answer" in r for r in records),
        structurePassed=sum(r["validation"]["structurePassed"] for r in records),
        minimumSeconds=min(r["elapsedSeconds"] for r in records),
        medianSeconds=statistics.median(r["elapsedSeconds"] for r in records),
        maximumSeconds=max(r["elapsedSeconds"] for r in records),
        providerReportedTotalTokens=sum((r.get("usage") or {}).get("total_tokens", 0) for r in records),
        orderComparisons=comparison, cases=summary)
    (HERE / "summary.json").write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")

    # Fixed presentation order hides experiment labels and author scores. It is
    # a packet for future human review, not an executed blinded study.
    keys = ["ambiguous-metadata", "origin-change", "baseline", "untrusted-name",
            "preference-change", "baseline-repeat", "experience-geography-conflict", "shuffled"]
    packet = ["# Human review packet", "", "No human ratings have been collected. Case labels and the implementing agent's scores are omitted here.",
              "Review each supplied input/output. Score preference fit, activity flow, geographic explanation and epistemic care from 0 (contradiction/unsupported) to 1 (plausible/generic) to 2 (specific/supported or qualified). Explain disagreements. Do not equate shortest coordinate distance with best experience.", ""]
    mapping = {}
    for index, key in enumerate(keys, 1):
        if key not in by_key:
            continue
        mapping["R" + str(index)] = key
        case = copy.deepcopy(cases[key])
        case.pop("caseID", None)
        record = by_key[key]
        packet.extend(["## R" + str(index), "", "Input:", "", "```json",
                       json.dumps(case, indent=2, ensure_ascii=False), "```", "", "Output:", "", "```json",
                       json.dumps(record.get("answer", {"providerFailure": record.get("httpStatus")}), indent=2, ensure_ascii=False),
                       "```", "", "Reviewer scores: preference __/2; flow __/2; geography __/2; epistemic care __/2.", "Reviewer notes: __", ""])
    (HERE / "review-packet.md").write_text("\n".join(packet))
    (HERE / "review-key.json").write_text(json.dumps(mapping, indent=2) + "\n")
    print(json.dumps({k: v for k, v in document.items() if k != "cases"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
