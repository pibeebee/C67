#!/usr/bin/env python3
"""Inspect the official publications; never silently refresh curated facts or their dates."""
import argparse
import concurrent.futures
import datetime
import hashlib
import html
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
catalog = json.loads((ROOT / "Packages/VisitTiming/Sources/VisitTiming/Resources/jakarta-2026-11-05.json").read_text())
checks = {
    "jaklitera": [
        r"Cikini.{0,220}09\.00\s*-\s*22\.00",
        r"Jatinegara.{0,400}Sabtu dan Minggu:\s*09\.00\s*-\s*14\.30",
        r"Jumat,\s*check-in ditutup sementara 11\.30\s*-\s*13\.00",
    ],
    "macan": [r"Museum MACAN tutup sementara", r"17\.30", r"10\.00[–-]18\.00"],
    "ragunan": [r"Tuesday\s*-\s*Sunday", r"07:00\s*-\s*16:00", r"Monday\s*-\s*Closed"],
    "gbk": [r"Senin\s*Tutup", r"06\.00[–-]10\.00,\s*15\.00[–-]18\.00"],
}


def inspect(source):
    result = {"id": source["id"], "url": source["url"],
              "checkedAt": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    try:
        data = subprocess.check_output(
            ["/usr/bin/curl", "--fail", "--location", "--silent", "--show-error",
             "--max-time", "25", source["url"]], stderr=subprocess.PIPE)
        text = html.unescape(re.sub(r"<[^>]+>", " ", data.decode("utf-8", errors="replace")))
        text = re.sub(r"\s+", " ", text)
        outcomes = [bool(re.search(pattern, text, re.I)) for pattern in checks[source["id"]]]
        result.update(sha256=hashlib.sha256(data).hexdigest(), assertionResults=outcomes,
                      status="claims_present" if all(outcomes) else "needs_review")
        if source["id"] == "macan":
            result["visibilityLimit"] = "HTML alone cannot establish display visibility; browser check is separately recorded."
    except Exception as error:
        result.update(status="fetch_failed", error=str(error))
    return result


with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(inspect, catalog["sources"]))
args.out.parent.mkdir(parents=True, exist_ok=True)
args.out.write_text(json.dumps({"results": results, "factsAutomaticallyUpdated": False},
                               indent=2, ensure_ascii=False) + "\n")
for result in results:
    print(result["id"], result["status"])
raise SystemExit(0 if all(result["status"] == "claims_present" for result in results) else 1)
