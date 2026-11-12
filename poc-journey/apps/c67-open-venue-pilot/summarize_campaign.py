"""Report new collection coverage and export traceable proposals for human review."""

import argparse
import collections
import copy
import json
import statistics

import pilot


def summarize(name):
    campaign = pilot.configure_campaign(name)
    evidence_raw = (pilot.LOCAL / "evidence.json").read_bytes()
    evidence = json.loads(evidence_raw)
    extraction = json.loads((pilot.OUT / "giovanc/extraction.json").read_bytes())
    discovery = json.loads((campaign / "discovery.json").read_bytes())
    assert extraction["evidence_sha256"] == pilot.digest(evidence_raw)
    targets = {t["id"]: t for t in evidence["targets"]}
    notes = {t["id"]: t for t in discovery["rows"]}
    rows = {r["id"]: r for r in extraction["rows"]}
    review_path = pilot.OUT / "review-notes.json"
    review_notes = json.loads(review_path.read_bytes()) if review_path.exists() else {"issues": []}
    assert len(rows) == len(extraction["rows"]) == len(targets)
    assert targets.keys() == rows.keys() == notes.keys()
    queue = []
    field_states = {field: collections.Counter() for field in pilot.FIELDS}
    for ident, target in targets.items():
        row = rows[ident]
        claims = copy.deepcopy(row["claims"])
        assert not pilot.validate(claims, {e["id"] for e in target["evidence"]})
        resolved = {}
        for field, claim in claims.items():
            field_states[field][claim["status"]] += 1
            resolved[field] = []
            for ref in claim["evidence"]:
                excerpt = next(e for e in target["evidence"] if e["id"] == ref)
                source = target["sources"][excerpt["source"] - 1]
                resolved[field].append({
                    "id": ref, "text": excerpt["text"],
                    "url": source.get("final_url", source["url"]),
                    "checked_at": source["checked_at"], "page_sha256": source["sha256"],
                })
        queue.append({
            "id": ident, "name": target["name"], "branch": target["branch"],
            "category": notes[ident]["category"], "places": target["places"],
            "collection_state": row["state"],
            "decision": "pending_review" if row["state"] == "extracted" else "needs_source",
            "app_eligible": False, "pin_status": "unverified",
            "review_flags": notes[ident]["risks"],
            "review_findings": [item for item in review_notes["issues"] if item["id"] == ident],
            "model_claims": claims, "claim_evidence": resolved,
        })
    inferred = [row for row in rows.values() if row["state"] == "extracted"]
    attempts = extraction.get("attempts", [])
    accepted_calls = [a for a in attempts if a["state"] == "accepted"]
    costs = [a["costUSD"] for a in accepted_calls if a.get("costUSD") is not None]
    summary = {
        "campaign": name, "created_at": pilot.now(),
        "evidence_sha256": pilot.digest(evidence_raw),
        "extraction_sha256": pilot.digest((pilot.OUT / "giovanc/extraction.json").read_bytes()),
        "new_candidates": len(rows), "categories": dict(collections.Counter(r["category"] for r in notes.values())),
        "with_seed_urls": sum(bool(r["urls"]) for r in notes.values()),
        "with_excerpts": sum(bool(t["evidence"]) for t in targets.values()),
        "page_states": dict(collections.Counter(s["state"] for t in targets.values() for s in t["sources"])),
        "source_page_references": sum(len(t["sources"]) for t in targets.values()),
        "unique_fetched_pages": len({s.get("final_url", s["url"]) for t in targets.values()
                                     for s in t["sources"] if s["state"] == "fetched"}),
        "crawl_network_attempts_including_robots": evidence["network_attempts"],
        "crawl_seconds": evidence["seconds"],
        "inference_states": dict(collections.Counter(r["state"] for r in rows.values())),
        "requested_model": extraction["model"],
        "reported_models": sorted({r["model"] for r in inferred}),
        "generation_attempts": len(attempts),
        "retries": sum(a["state"] == "retry" for a in attempts),
        "retry_errors": dict(collections.Counter(a["error"] for a in attempts if a["state"] == "retry")),
        "inference_seconds_sum": sum(r["seconds"] for r in inferred),
        "inference_seconds_median": statistics.median(r["seconds"] for r in inferred) if inferred else None,
        "accepted_response_cost_usd": sum(costs) if accepted_calls and len(costs) == len(accepted_calls) else None,
        "field_states_including_no_source": {field: dict(counts) for field, counts in field_states.items()},
        "model_proposed_core_facts": sum(all(r["claims"][f]["status"] == "supported"
                                             for f in ("identity", "public_visit", "visitor_activity"))
                                         for r in inferred),
        "review_decisions": dict(collections.Counter(r["decision"] for r in queue)),
        "new_app_eligible": 0,
        "documentary_spot_check_findings": len(review_notes["issues"]),
        "notes": [
            "Assistant web search selected operator/government seed pages. The extraction LLM did not browse.",
            "No new Google Places API requests. Existing OSM/Overture records retain provenance and attribution.",
            "New candidates are separate from the earlier Google/Jev set of 982 and from frozen benchmark artifacts.",
            "Field counts are model proposals, not reviewed fact counts. No held-out reference or accuracy claim for this batch.",
            "Review branch scope, source ownership, dates, conditions, current access and mapped coordinates before application use.",
            "Fetched-at timestamps establish collection time only, not current validity of older documents.",
        ],
    }
    pilot.save(pilot.OUT / "review-queue.json", {"campaign": name, "rows": queue})
    pilot.save(pilot.OUT / "summary.json", summary)
    median = summary["inference_seconds_median"]
    report = [
        "# Pengumpulan data Jakarta Selatan — batch 30", "",
        f"Kampanye `{name}` menambahkan {len(rows)} kandidat dari snapshot OSM/Overture yang sudah tersedia. "
        "Pencarian asisten memilih URL pengelola dan pemerintah. Kolektor mengambil potongan halaman, "
        "kemudian model melalui luna-provider.example mengusulkan tujuh field beserta ID bukti. "
        "LLM tidak melakukan browsing dalam alur ini.", "",
        "| Ukuran | Hasil |", "| --- | ---: |",
        f"| Kandidat baru | {len(rows)} |",
        f"| Memiliki URL awal | {summary['with_seed_urls']} |",
        f"| Memiliki potongan sumber | {summary['with_excerpts']} |",
        f"| Ekstraksi selesai | {len(inferred)} |",
        f"| Masih memerlukan sumber | {summary['inference_states'].get('no_source', 0)} |",
        f"| Halaman unik berhasil diambil | {summary['unique_fetched_pages']} |",
        f"| Percobaan model / retry | {len(attempts)} / {summary['retries']} |",
        f"| Median waktu per tempat, termasuk retry | {median:.2f} detik |" if median is not None else
        "| Median waktu per tempat | Belum tersedia |",
        f"| Jumlah waktu inferensi | {summary['inference_seconds_sum']:.2f} detik |",
        "| Tambahan panggilan Google Places | 0 |", "",
        f"Model diminta `{extraction['model']}`. Model yang dilaporkan "
        + ", ".join(f"`{m}`" for m in summary["reported_models"]) + ". "
        + ("Biaya tidak dilaporkan endpoint." if summary["accepted_response_cost_usd"] is None else
           f"Biaya respons berhasil yang dilaporkan USD {summary['accepted_response_cost_usd']:.6f}."), "",
        "## Cakupan usulan model", "",
        "Angka berikut menghitung status keluaran model pada seluruh kandidat, termasuk kandidat tanpa sumber. "
        "Angka ini belum menjadi jumlah fakta yang lolos telaah isi.", "",
        "| Field | Supported | Contradicted | Unknown |", "| --- | ---: | ---: | ---: |",
    ]
    for field, counts in field_states.items():
        report.append(f"| {field} | {counts['supported']} | {counts['contradicted']} | {counts['unknown']} |")
    report.extend([
        "", "## Status penggunaan", "",
        "Usulan berada pada antrean telaah. Pin masih berasal dari sumber peta dan belum diverifikasi. "
        "Tidak ada data baru yang otomatis diterima atau dimasukkan ke aplikasi. "
        "Periksa identitas cabang, bukti akses, kegiatan, tanggal dokumen, syarat program, dan pasangan hari/jam. "
        "Tanggal pengambilan halaman tidak membuktikan bahwa berita lama masih berlaku.", "",
        "Batch ini tidak mempunyai acuan evaluasi independen yang dibekukan sebelum inferensi. "
        "Tidak ada skor akurasi baru atau klaim peningkatan kualitas model. "
        "Sampel dipilih secara purposif; sebagian venue tidak memiliki halaman operator yang memadai. "
        "Dataset Google/Jev 982 tempat dan tiga arsip benchmark sebelumnya tetap terpisah.", "",
        "## Berkas", "",
        "- [Ringkasan JSON](results/summary.json)",
        "- [Antrean telaah dengan klaim, potongan, URL dan hash sumber](results/review-queue.json)",
        "- [Keluaran model asli dan log retry](results/giovanc/extraction.json)",
        "- [Audit pengambilan halaman](results/source-audit.json)",
        "- [Input kandidat](targets.json)", "- [Penemuan URL dan risiko sumber](discovery.json)", "",
    ])
    if review_path.exists():
        report.append("- [Catatan pemeriksaan isi sebagian keluaran](results/review-notes.json)")
    (campaign / "REPORT.md").write_text("\n".join(report))
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign", required=True)
    summarize(parser.parse_args().campaign)
