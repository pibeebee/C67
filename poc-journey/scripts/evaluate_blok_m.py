#!/usr/bin/env python3
"""Score native-pipeline exports using separately collected, blinded human judgments."""

import argparse
import json
import math
from pathlib import Path


def load(path):
    return json.loads(Path(path).read_text())


def review_labels(document, expected, sources):
    if not document.get("reviewerID", "").strip():
        raise ValueError("A real reviewerID is required.")
    labels = {}
    for row in document["judgments"]:
        key = (row["personaID"], row["candidateID"])
        if key in labels or key not in expected:
            raise ValueError(f"Duplicate or unknown judgment {key}")
        grade = row["grade"]
        if type(grade) is not int or grade not in (0, 1, 2):
            raise ValueError(f"Human grade 0/1/2 required for {key}")
        if not row.get("reason", "").strip() or not row.get("sourceIDs"):
            raise ValueError(f"Reason and sources required for {key}")
        if not set(row["sourceIDs"]).issubset(sources[key[1]]):
            raise ValueError(f"Source does not belong to this candidate {key}")
        labels[key] = grade
    if set(labels) != expected:
        raise ValueError("Every persona/candidate pair must be reviewed, including grade zero.")
    return labels


def metrics(ids, grades, eligible):
    ideal = sorted((grades[candidate] for candidate in eligible), reverse=True)[:3]
    idcg = sum((2**grade - 1) / math.log2(index + 2) for index, grade in enumerate(ideal))
    dcg = sum((2**grades[candidate] - 1) / math.log2(index + 2) for index, candidate in enumerate(ids[:3]))
    return {
        "precisionAt3": sum(grades[candidate] > 0 for candidate in ids[:3]) / 3,
        "ndcgAt3": dcg / idcg if idcg else None,
        "strongMatches": sum(grades[candidate] == 2 for candidate in ids[:3]),
    }


def overlap(left, right):
    union = set(left) | set(right)
    return len(set(left) & set(right)) / len(union) if union else None


def evaluate(series, reviewers=None, consensus=None):
    runs = series["runs"]
    if not runs:
        raise ValueError("Empty series")
    catalog = runs[0]["review"]["quality"]["catalog"]
    candidates = {row["id"]: row for row in catalog["candidates"]}
    personas = {row["persona"]["id"]: row["persona"] for row in runs}
    expected = {(persona, candidate) for persona in personas if persona != "P0" for candidate in candidates}
    sources = {key: set(row["sourceIDs"]) for key, row in candidates.items()}
    labels = None
    human_status = "pending_two_independent_reviewers"
    disagreements = []
    if reviewers:
        if reviewers[0]["reviewerID"] == reviewers[1]["reviewerID"]:
            raise ValueError("Two different reviewer identities are required.")
        first = review_labels(reviewers[0], expected, sources)
        second = review_labels(reviewers[1], expected, sources)
        disagreements = [key for key in sorted(expected) if first[key] != second[key]]
        if disagreements and consensus is None:
            human_status = "pending_adjudication"
        else:
            labels = review_labels(consensus, expected, sources) if consensus else first
            # Consensus may only change scores on disputed pairs.
            if any(labels[key] != first[key] for key in expected if key not in disagreements):
                raise ValueError("Consensus changed an undisputed judgment.")
            human_status = "complete"

    results = []
    seen = set()
    for run in runs:
        key = (run["persona"]["id"], run["window"], run["method"])
        if key in seen or run["review"]["quality"]["catalog"] != catalog:
            raise ValueError("Duplicate run or mixed catalog snapshots")
        seen.add(key)
        ids = run["displayedIDs"]
        eligible = run["eligibleIDs"]
        valid = (
            len(ids) <= 3
            and len(ids) == len(set(ids))
            and set(ids).issubset(eligible)
            and set(eligible).issubset(candidates)
            and len({candidates[candidate]["venueID"] for candidate in ids}) == len(ids)
        )
        if not valid:
            raise ValueError(f"Invalid displayed set or hard gate violation {key}")
        row = {
            "persona": key[0], "window": key[1], "method": key[2], "displayedIDs": ids,
            "pipelineStatus": run["review"]["quality"]["status"],
            "eligibleCount": len(eligible), "factSupportedCount": len(run["factSupportedIDs"]),
            "seconds": run["review"]["quality"]["elapsedSeconds"],
            "relevanceStatus": "general_control" if key[0] == "P0" else human_status,
        }
        if labels and key[0] != "P0":
            grades = {candidate: labels[(key[0], candidate)] for candidate in candidates}
            positive_venues = {candidates[candidate]["venueID"] for candidate in eligible if grades[candidate] > 0}
            row["metrics"] = metrics(ids, grades, eligible)
            row["relevantEligibleVenues"] = len(positive_venues)
            row["relevanceStatus"] = "scored" if len(positive_venues) >= 3 else "insufficient_catalog_coverage"
        results.append(row)

    lookup = {(row["persona"], row["window"], row["method"]): row for row in results}
    deltas = []
    for row in results:
        baseline = lookup.get((row["persona"], row["window"], "general"))
        if not baseline or row["method"] == "general":
            continue
        row["generalTop3Overlap"] = overlap(row["displayedIDs"], baseline["displayedIDs"])
        if row["relevanceStatus"] == "scored":
            delta = row["metrics"]["ndcgAt3"] - baseline["metrics"]["ndcgAt3"]
            row["ndcgDeltaFromGeneral"] = delta
            if row["method"] == "category":
                deltas.append(delta)
        category = lookup.get((row["persona"], row["window"], "category"))
        if row["method"] == "combined" and row["relevanceStatus"] == "scored" and category:
            row["ndcgDeltaFromCategory"] = row["metrics"]["ndcgAt3"] - category["metrics"]["ndcgAt3"]
            row["e5InferenceObserved"] = run_has_embedding(runs, row["persona"], row["window"])

    sensitivity = []
    # Evaluate each new profile using its own labels against the other profile's ranking.
    for left, right in [("P1", "P3"), ("P3", "P1"), ("P1", "P4"), ("P4", "P1")]:
        target = lookup.get((right, "day", "category"))
        previous = lookup.get((left, "day", "category"))
        item = {"from": left, "to": right, "status": "insufficient_evidence"}
        if labels and target and previous and target["relevanceStatus"] == "scored":
            eligible = next(run["eligibleIDs"] for run in runs if run["persona"]["id"] == right and run["window"] == "day" and run["method"] == "category")
            if set(previous["displayedIDs"]).issubset(eligible):
                grades = {candidate: labels[(right, candidate)] for candidate in candidates}
                before = metrics(previous["displayedIDs"], grades, eligible)["ndcgAt3"]
                after = target["metrics"]["ndcgAt3"]
                item.update(status="pass" if after > before else "fail", delta=after - before)
        sensitivity.append(item)

    positive = [row for row in results if row["method"] == "category" and row["persona"] != "P0"]
    scored = [row for row in positive if row["relevanceStatus"] == "scored"]
    mean_ndcg = sum(row["metrics"]["ndcgAt3"] for row in scored) / len(scored) if scored else None
    mean_delta = sum(deltas) / len(deltas) if deltas else None
    required = {(f"P{index}", window, method) for index in range(6)
                for window in ["day", "afternoon"] for method in ["general", "category"]}
    complete = labels is not None and required.issubset(seen) and len(scored) == len(positive)
    outcome = "insufficient_evidence"
    if complete:
        passed = (all(row["metrics"]["precisionAt3"] >= 2 / 3 for row in scored)
                  and mean_ndcg >= 0.80 and mean_delta >= 0.10
                  and sum(item["status"] == "pass" for item in sensitivity) >= 3)
        outcome = "pass" if passed else "fail"
    return {
        "catalogID": series["catalogID"], "clockMode": series["clockMode"],
        "humanJudgments": human_status, "disagreements": disagreements,
        "personalizationOutcome": outcome, "meanCategoryNDCGAt3": mean_ndcg,
        "meanCategoryDeltaFromGeneral": mean_delta, "sensitivity": sensitivity,
        "limitations": ["Technical replay and local inference do not establish user satisfaction.",
                        "Hard-gate audits here check exported set consistency. Native regression tests independently exercise factual gates.",
                        "Repeated windows share venue facts and are correlated."],
        "runs": results,
    }


def run_has_embedding(runs, persona, window):
    return any(row["persona"]["id"] == persona and row["window"] == window and row["method"] == "combined"
               and row["review"]["quality"].get("embedding") is not None for row in runs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("series", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--reviewer-a", type=Path)
    parser.add_argument("--reviewer-b", type=Path)
    parser.add_argument("--consensus", type=Path)
    parser.add_argument("--prepare-review", action="store_true")
    args = parser.parse_args()
    if bool(args.reviewer_a) != bool(args.reviewer_b):
        parser.error("Provide both independent reviews.")
    if args.out.exists():
        parser.error("Use a fresh output directory.")
    series = load(args.series)
    reviewers = [load(args.reviewer_a), load(args.reviewer_b)] if args.reviewer_a else None
    report = evaluate(series, reviewers, load(args.consensus) if args.consensus else None)
    args.out.mkdir(parents=True)
    (args.out / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    lines = ["# Blok M recommendation evaluation", "", f"Personalization outcome — {report['personalizationOutcome']}",
             f"Human judgments — {report['humanJudgments']}", "", "| Persona | Window | Method | Top 3 | Pipeline status | Relevance |",
             "| --- | --- | --- | --- | --- | --- |"]
    for row in report["runs"]:
        lines.append(f"| {row['persona']} | {row['window']} | {row['method']} | {', '.join(row['displayedIDs'])} | {row['pipelineStatus']} | {row['relevanceStatus']} |")
    lines += ["", *report["limitations"]]
    (args.out / "REPORT.md").write_text("\n".join(lines) + "\n")
    if args.prepare_review:
        catalog = series["runs"][0]["review"]["quality"]["catalog"]
        personas = {run["persona"]["id"]: run["persona"] for run in series["runs"] if run["persona"]["id"] != "P0"}
        # Reviewer materials contain facts and profiles, never rankings, scores or method names.
        (args.out / "review-materials.json").write_text(json.dumps({"catalog": catalog, "personas": list(personas.values())}, indent=2) + "\n")
        template = {"reviewerID": "", "judgments": [
            {"personaID": persona, "candidateID": candidate["id"], "grade": None, "reason": "", "sourceIDs": []}
            for persona in sorted(personas) for candidate in sorted(catalog["candidates"], key=lambda item: item["id"])
        ]}
        (args.out / "review-template.json").write_text(json.dumps(template, indent=2) + "\n")
    print(f"{report['personalizationOutcome']}; {report['humanJudgments']}; {args.out}")


if __name__ == "__main__":
    main()
