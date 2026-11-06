#!/usr/bin/env python3
"""Development regression cases; records every result, not a user-benefit study."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

binary = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=False)
root = Path(__file__).resolve().parents[1]
def profile(text="", interests=None, avoids=None, feedback=None):
    return dict(schemaVersion=1, interests=interests or [], avoids=avoids or [], text=text, feedback=feedback or {})
cases = [
    ("cold", profile(), [], []),
    ("coffee-id", profile("Saya ingin ngopi sambil membaca di tempat yang tenang"), ["coffee", "reading", "quiet"], []),
    ("coffee-en", profile("I want to have coffee and read a book in a quiet place"), ["coffee", "reading", "quiet"], []),
    ("art-id", profile("Saya ingin menikmati lukisan dan pameran seni"), ["art"], []),
    ("art-en", profile("I enjoy paintings and visual art exhibitions"), ["art"], []),
    ("liked-coffee", profile(feedback={"A": "liked"}), ["coffee", "reading", "quiet"], []),
    ("liked-art", profile(feedback={"C": "liked"}), ["art"], []),
    ("explicit-avoid", profile(interests=["nature", "outdoor"], avoids=["indoor", "lively"]), ["nature", "outdoor"], []),
    ("text-negation-only", profile("Saya ingin ngopi tetapi tidak ingin tempat ramai"), [], []),
    ("text-plus-avoid", profile("Saya ingin ngopi", avoids=["lively"]), ["coffee"], []),
    ("snapshot-thin-data", profile("Saya ingin ngopi sambil membaca di tempat yang tenang"), [], ["--snapshot"]),
    ("category-only", profile(interests=["coffee", "reading"]), ["coffee", "reading"], ["--baseline"]),
]
source_files = list((root/"Packages/PreferenceLearning").rglob("*.swift")) + list((root/"App").glob("*.swift"))
manifest = dict(binarySHA256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                sourceSHA256={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files},
                model=json.loads((root/"Packages/PreferenceLearning/Sources/PreferenceLearning/Resources/Model/manifest.json").read_text()),
                scope="Twelve authored development cases, one trial each. Tag coverage is fixture-only and not human preference accuracy.")
(out/"manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
rows = []
for name, value, required, extra in cases:
    input_path = out/(name+".input.json")
    input_path.write_text(json.dumps(value, indent=2))
    completed = subprocess.run([str(binary), "--profile", str(input_path), "--out", str(out/name), *extra], capture_output=True, text=True, timeout=60)
    (out/(name+".stderr")).write_text(completed.stderr)
    row = dict(case=name, exitCode=completed.returncode, requiredFixtureTags=required)
    if completed.returncode == 0:
        run = json.loads((out/name/"run.json").read_text())
        row.update(status=run["status"], error=run["error"], elapsedSeconds=run["elapsedSeconds"])
        for kind in ["categoryRanking", "semanticRanking"]:
            top=run[kind][:3]
            row[kind]=[dict(id=r["place"]["id"], score=r["score"]) for r in top]
            row[kind+"AllRequiredTags"]=None if not required or not top else sum(set(required)<=set(r["place"]["tags"]) for r in top)
        row["filtersRespected"] = all(not set(r["place"]["tags"]) & set(value["avoids"]) and r["place"]["id"] not in value["feedback"] for key in ["categoryRanking","semanticRanking"] for r in run[key])
    rows.append(row)
    (out/"summary.json").write_text(json.dumps(rows, indent=2)+"\n")
    print(name, row.get("status", row["exitCode"]), row.get("elapsedSeconds"), flush=True)
