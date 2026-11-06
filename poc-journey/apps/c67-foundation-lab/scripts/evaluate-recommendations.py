#!/usr/bin/env python3
"""Bounded regression smoke series; no scoring of factual prose or user benefit."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

binary, live_path, known_path, destination = map(Path, sys.argv[1:])
destination.mkdir(parents=True, exist_ok=False)
root = Path(__file__).resolve().parents[1]
live = json.loads(live_path.read_text())
known = json.loads(known_path.read_text())
cases = {"discovery-frozen-mapkit": live["brief"], "own-places-with-time-facts": known["brief"]}
correction = dict(known["brief"])
correction["experiences"] = []
correction["avoids"] = []
correction["text"] = "I first wanted coffee. Correction: I want culture and photography, and I avoid coffee."
cases["english-correction"] = correction
live_copy = destination / "mapkit-snapshot.json"
live_copy.write_text(json.dumps(live, indent=2))
inputs = {}
for name, brief in cases.items():
    path = destination / (name + ".json")
    path.write_text(json.dumps(brief, indent=2))
    inputs[name] = path
sources = [*root.glob("App/*.swift"), *root.glob("Packages/TripIntelligence/Sources/**/*.swift")]
hashes = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
manifest = {
    "createdAtUnix": time.time(), "promptVersion": "recommendations-v1",
    "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest(), "sources": hashes,
    "inputs": {name: hashlib.sha256(p.read_bytes()).hexdigest() for name, p in inputs.items()},
    "mapkitSnapshotSHA256": hashlib.sha256(live_copy.read_bytes()).hexdigest(),
    "scope": "Three development regression cases, three correlated greedy repetitions. Not a holdout or semantic accuracy estimate."
}
(destination / "manifest.json").write_text(json.dumps(manifest, indent=2))
rows = []
for name, input_path in inputs.items():
    for trial in [1, 2, 3, "baseline"]:
        output = destination / f"{name}-{trial}"
        command = [str(binary), "recommend", "--input", str(input_path), "--out", str(output)]
        if name == "discovery-frozen-mapkit":
            command += ["--search-snapshot", str(live_copy)]
        if trial == "baseline":
            command += ["--baseline"]
        started = time.monotonic()
        try:
            completed = subprocess.run(command, capture_output=True, text=True, timeout=180)
            (destination / f"{name}-{trial}.stderr").write_text(completed.stderr)
            (destination / f"{name}-{trial}.stdout").write_text(completed.stdout)
            row = {"case": name, "trial": trial, "exitCode": completed.returncode,
                   "wallSeconds": time.monotonic() - started}
            if completed.returncode == 0:
                run = json.loads((output / "recommendations.json").read_text())
                row.update({"selectedIDs": run["selectedIDs"], "profile": run["profile"],
                            "routingPerformed": run["routingPerformed"],
                            "stages": [{"capability": r["capability"], "status": r["status"],
                                        "error": r["error"], "tokens": r.get("inputTokens")}
                                       for r in run["records"]],
                            "windows": [{"name": a["candidate"]["place"]["name"],
                                         "window": a["advice"]["window"],
                                         "basis": a["advice"]["timeBasis"], "source": a["source"]}
                                        for a in run["advice"]]})
        except subprocess.TimeoutExpired:
            row = {"case": name, "trial": trial, "error": "outer_watchdog_180s"}
        rows.append(row)
        (destination / "summary.json").write_text(json.dumps(rows, indent=2))
        print(name, trial, row.get("exitCode", row.get("error")),
              "selected", len(row.get("selectedIDs", [])), flush=True)
