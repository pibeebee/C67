"""Compare frozen reviewer labels against the pilot and report source coverage."""

import argparse
import collections
import json
import statistics
from pathlib import Path

from pilot import FIELDS, LOCAL, OUT, digest, save


def read(path):
    return json.loads(path.read_bytes())


def evaluate(extraction_path=None):
    evidence_path = LOCAL / "evidence.json"
    reference_path = OUT / "manual-reference.json"
    evidence = read(evidence_path)
    reference = read(reference_path)
    extraction_path = extraction_path or OUT / "giovanc/extraction.json"
    extraction = read(extraction_path)
    evidence_hash = digest(evidence_path.read_bytes())
    assert evidence_hash == reference["evidence_sha256"] == extraction["evidence_sha256"]
    assert digest(reference_path.read_bytes()) == extraction["reference_sha256"]
    targets = {row["id"]: row for row in evidence["targets"]}
    rows = {row["id"]: row for row in extraction["rows"]}
    assert len(rows) == len(extraction["rows"]) == len(targets) and rows.keys() == targets.keys()
    disagreements = []
    stages = {"all_reference": collections.Counter(), "actual_model_only": collections.Counter()}
    for key, expected in reference["rows"].items():
        row = rows[key]
        for field in FIELDS:
            claim = row["claims"][field]
            actual = claim["status"]
            status = "supported" if field in expected else "unknown"
            scopes = [stages["all_reference"]]
            if row["state"] == "extracted":
                scopes.append(stages["actual_model_only"])
            for counts in scopes:
                counts["fields"] += 1
                counts["match"] += actual == status
                counts["reference_supported"] += status == "supported"
                counts["reference_unknown"] += status == "unknown"
                counts["supported_recovered"] += status == actual == "supported"
                counts["unsupported_non_unknown"] += status == "unknown" and actual != "unknown"
            if status != actual:
                disagreements.append({"id": key, "field": field, "reference": status, "model": actual})
    time_samples = [row["seconds"] for row in rows.values() if row["state"] == "extracted"]
    matched = [key for key, row in reference["rows"].items()
               if {"identity", "public_visit", "visitor_activity"} <= row.keys()]
    accepted = [row for row in extraction.get("attempts", []) if row["state"] == "accepted"]
    known_costs = [row["costUSD"] for row in accepted if row.get("costUSD") is not None]
    summary = {
        "targets": len(targets),
        "with_excerpts": sum(bool(t["evidence"]) for t in targets.values()),
        "crawl_attempts_including_robots": evidence["network_attempts"],
        "crawl_seconds": evidence["seconds"],
        "inference_states": dict(collections.Counter(row["state"] for row in rows.values())),
        "inference_seconds_sum": sum(time_samples),
        "inference_seconds_median": statistics.median(time_samples) if time_samples else None,
        "model": extraction["model"],
        "attempts": len(extraction.get("attempts", [])),
        "retries": sum(row["state"] == "retry" for row in extraction.get("attempts", [])),
        "successful_requests_cost_usd": sum(known_costs) if accepted and len(known_costs) == len(accepted) else None,
        "successful_requests_with_cost": len(known_costs),
        "schema_downgrades": sum(len(row.get("downgraded_fields", [])) for row in rows.values()),
        "manual_sample_venues": len(reference["rows"]),
        "comparison": {key: dict(counter) for key, counter in stages.items()},
        "disagreements": disagreements,
        "documentary_review_shortlist": matched,
    }
    save(extraction_path.parent / "summary.json", summary)
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--extraction", type=Path)
    evaluate(parser.parse_args().extraction)
