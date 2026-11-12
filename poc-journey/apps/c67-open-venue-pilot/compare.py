"""Paired comparison of three frozen extraction campaigns."""

import json
import statistics

from pilot import FIELDS, LOCAL, OUT, digest, save


def compare():
    evidence = (LOCAL / "evidence.json").read_bytes()
    reference_raw = (OUT / "manual-reference.json").read_bytes()
    reference = json.loads(reference_raw)
    output = {
        "evidence_sha256": digest(evidence), "reference_sha256": digest(reference_raw),
        "notes": [
            "Same frozen excerpts and reference. No new crawl or evaluator labels are sent to models.",
            "Nine reference venues have excerpts; score only those 63 fields for model comparisons.",
            "This is a single purposive pilot, with one reviewer and no field validation.",
            "Qwen output cap was 700 tokens; remote caps are 1600. The configured endpoint adds a JSON-schema instruction.",
            "Per-venue elapsed includes pacing and retry. Tokenization, infrastructure and request time differ.",
            "Costs concern successful responses. Missing cost is unknown.",
            "Token totals concern accepted responses only. Controls are separate from venue timings and attempts.",
            "This compares provider/model extraction configurations, not browsing, location pins, or application recommendations.",
        ],
        "runs": [],
    }
    expected_venues = {t["id"] for t in json.loads(evidence)["targets"]}
    for name, path in (
        ("qwen", OUT / "extraction.json"),
        ("nemotron", OUT / "nemotron/extraction.json"),
        ("giovanc", OUT / "giovanc/extraction.json"),
    ):
        data = json.loads(path.read_bytes())
        assert data["evidence_sha256"] == digest(evidence)
        assert data["reference_sha256"] == digest(reference_raw)
        rows = {r["id"]: r for r in data["rows"]}
        assert len(rows) == len(data["rows"]) and rows.keys() == expected_venues
        inferred = [r for r in rows.values() if r["state"] == "extracted"]
        field_count = correct = supported = recovered = extra = 0
        differences = []
        for ident, gold in reference["rows"].items():
            row = rows[ident]
            if row["state"] != "extracted":
                continue
            for field in FIELDS:
                wanted = "supported" if field in gold else "unknown"
                got = row["claims"][field]["status"]
                field_count += 1
                correct += got == wanted
                supported += wanted == "supported"
                recovered += wanted == got == "supported"
                extra += wanted == "unknown" and got != "unknown"
                if wanted != got:
                    differences.append({"id": ident, "field": field, "expected": wanted, "actual": got})
        accepted = [r for r in data.get("attempts", []) if r["state"] == "accepted"]
        control_data = json.loads((path.parent / "controls.json").read_bytes())
        controls = control_data if isinstance(control_data, list) else control_data["rows"]
        control_checks = [row["claims"][field]["status"] == expected
                          for row in controls for field, expected in row["expected"].items()]
        costs = [r["costUSD"] for r in accepted if r.get("costUSD") is not None]
        model_times = [r["successful_attempt_seconds"] for r in inferred if "successful_attempt_seconds" in r]
        output["runs"].append({
            "name": name, "requested_model": data["model"],
            "reported_models": sorted({r.get("model", data["model"]) for r in inferred}),
            "inferred": len(inferred), "no_source": sum(r["state"] == "no_source" for r in rows.values()),
            "generation_attempts": len(data.get("attempts", [])) or len(inferred),
            "retries": sum(r["state"] == "retry" for r in data.get("attempts", [])),
            "median_venue_seconds": statistics.median(r["seconds"] for r in inferred),
            "sum_venue_seconds": sum(r["seconds"] for r in inferred),
            "median_successful_request_seconds": statistics.median(model_times) if model_times else None,
            "prompt_tokens": sum(r.get("prompt_tokens") or 0 for r in inferred),
            "output_tokens": sum(r.get("output_tokens") or 0 for r in inferred),
            "successful_request_cost_usd": sum(costs) if accepted and len(costs) == len(accepted) else None,
            "reference_fields": field_count, "matching_statuses": correct,
            "supported_reference": supported, "supported_recovered": recovered,
            "unsupported_non_unknown": extra, "differences": differences,
            "synthetic_control_cases": len(controls),
            "synthetic_control_checks": len(control_checks),
            "synthetic_control_checks_passed": sum(control_checks),
        })
    save(OUT / "comparison.json", output)
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    compare()
