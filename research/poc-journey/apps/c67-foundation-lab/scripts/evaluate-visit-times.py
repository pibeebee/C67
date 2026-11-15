#!/usr/bin/env python3
"""Real publication-derived scenarios. These runs are not on-site opening observations."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("binary", type=Path)
parser.add_argument("out", type=Path)
args = parser.parse_args()
cases = [
    ("gbk-midday", "gbk", "2026-11-06", 600, 900, 60, "no_window"),
    ("gbk-split", "gbk", "2026-11-06", 360, 1080, 60, "regular_hours_options"),
    ("gbk-cross-session", "gbk", "2026-11-06", 540, 1020, 120, "regular_hours_options"),
    ("ragunan-monday", "ragunan", "2026-11-09", 420, 960, 60, "closed_regular"),
    ("ragunan-late", "ragunan", "2026-11-07", 930, 1080, 60, "no_window"),
    ("cikini-friday-entry", "cikini", "2026-11-06", 690, 780, 30, "no_window"),
    ("cikini-friday-stay", "cikini", "2026-11-06", 660, 840, 120, "regular_hours_options"),
    ("cikini-friday-resume", "cikini", "2026-11-06", 780, 840, 60, "regular_hours_options"),
    ("nyi-ageng-friday-entry", "nyi-ageng", "2026-11-06", 690, 780, 30, "no_window"),
    ("hb-jassin-friday-entry", "hb-jassin", "2026-11-06", 690, 780, 30, "no_window"),
    ("petojo-friday-entry", "petojo", "2026-11-06", 690, 780, 30, "no_window"),
    ("jatinegara-weekend", "jatinegara", "2026-11-08", 840, 960, 30, "regular_hours_options"),
    ("petojo-weekend", "petojo", "2026-11-08", 840, 960, 60, "no_window"),
    ("tanjung-weekend", "tanjung-duren", "2026-11-08", 540, 1200, 60, "hours_unknown"),
    ("gandaria-weekend", "gandaria", "2026-11-08", 540, 1200, 60, "hours_unknown"),
    ("koja-weekend", "koja", "2026-11-08", 540, 1200, 60, "hours_unknown"),
    ("macan-closure-notice", "macan", "2026-11-06", 600, 1080, 60, "suspended"),
]
args.out.mkdir(parents=True, exist_ok=True)
summary = []
for name, venue, date, start, end, duration, expected in cases:
    folder = args.out / name
    folder.mkdir(exist_ok=True)
    invocation = [str(args.binary.resolve()), "--venue", venue, "--date", date,
                  "--start", str(start), "--end", str(end), "--duration", str(duration),
                  "--out", str(folder)]
    proc = subprocess.run(invocation, capture_output=True, text=True, timeout=30)
    (folder / "process.log").write_text(proc.stdout + proc.stderr)
    files = list(folder.glob("*.json"))
    run = json.loads(max(files, key=lambda p: p.stat().st_mtime).read_text()) if files else {}
    summary.append(dict(case=name, expected=expected, actual=run.get("status"),
                        passed=proc.returncode == 0 and run.get("status") == expected,
                        sourceIDs=run.get("venue", {}).get("sourceIDs"), invocation=invocation,
                        runID=run.get("id"), options=len(run.get("options", []))))
    print(name, run.get("status"))
root = Path(__file__).resolve().parents[1]
catalog = root / "Packages/VisitTiming/Sources/VisitTiming/Resources/jakarta-2026-11-05.json"
(args.out / "summary.json").write_text(json.dumps(dict(
    scope="published regular rules, not on-site verification or blind quality benchmark",
    binarySHA256=hashlib.sha256(args.binary.read_bytes()).hexdigest(),
    catalogSHA256=hashlib.sha256(catalog.read_bytes()).hexdigest(), cases=summary),
    ensure_ascii=False, indent=2) + "\n")
raise SystemExit(0 if all(item["passed"] for item in summary) else 1)
