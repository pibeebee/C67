#!/usr/bin/env python3
"""Small live-provider integration series. Retains every run, not a quality benchmark."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

binary=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve()
out.mkdir(parents=True,exist_ok=False)
root=Path(__file__).resolve().parents[1]
def profile(text="", interests=None, avoids=None):
    return dict(schemaVersion=1, interests=interests or [], avoids=avoids or [], text=text, feedback={})
sources=[*root.glob("App/*.swift"),*root.glob("Packages/PreferenceLearning/Sources/**/*.swift"),*root.glob("Packages/TripIntelligence/Sources/**/*.swift")]
manifest=dict(binarySHA256=hashlib.sha256(binary.read_bytes()).hexdigest(),sourceSHA256={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},scope="Live MapKit integration cases, one run each; provider data can change. Not a controlled quality or latency benchmark.")
(out/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
rows=[]
def run(name,value,extra=None):
    path=out/(name+".input.json");path.write_text(json.dumps(value,indent=2)+"\n")
    result=subprocess.run([str(binary),"--live","--profile",str(path),"--out",str(out/name),*(extra or [])],capture_output=True,text=True,timeout=180)
    (out/(name+".stderr")).write_text(result.stderr)
    (out/(name+".stdout")).write_text(result.stdout)
    row=dict(case=name,exitCode=result.returncode)
    value=None
    if result.returncode==0:
        value=json.loads((out/name/"run.json").read_text())
        row.update(status=value["status"],elapsedSeconds=value["elapsedSeconds"],search=value.get("search"),semanticTop=[r["place"]["id"] for r in value["semanticRanking"][:3]],categoryTop=[r["place"]["id"] for r in value["categoryRanking"][:3]],error=value["error"])
    rows.append(row);(out/"summary.json").write_text(json.dumps(rows,indent=2)+"\n")
    print(name,row.get("status"),row.get("elapsedSeconds"),flush=True)
    return value

first=run("text-coffee-reading",profile("Saya ingin ngopi sambil membaca di tempat yang tenang"))
if first and first["semanticRanking"]:
    liked=first["semanticRanking"][0]["place"]
    learned=profile();learned["feedback"]={liked["id"]:"liked"};learned["rememberedPlaces"]=[liked]
    second=run("liked-place-new-search",learned)
    if second:
        assert all(r["place"]["id"]!=liked["id"] for r in second["semanticRanking"]+second["categoryRanking"])
        assert any("liked" in q["basis"] for q in second["search"]["choices"])
run("empty-general",profile())
run("semantic-search-intent",profile("I enjoy looking at collections and exhibitions"))
run("explicit-reading-avoid-coffee",profile(interests=["reading"],avoids=["coffee"]))
run("native-category-baseline",profile(interests=["coffee","reading"]),["--baseline"])
