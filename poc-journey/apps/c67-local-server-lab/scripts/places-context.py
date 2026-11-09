#!/usr/bin/env python3
"""Load only Places variables privately, then run the compiled engine. Never prints a key."""
import argparse,os,shlex,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--config',type=Path,default=root/'.env.local');p.add_argument('arguments',nargs=argparse.REMAINDER);a=p.parse_args()
env=dict(os.environ)
if a.config.exists():
    for line in a.config.read_text().splitlines():
        line=line.strip().removeprefix('export ')
        if '=' not in line:continue
        name,value=line.split('=',1);name=name.strip()
        if name not in ['GOOGLE_PLACES_API_KEY','GOOGLE_PLACES_MAX_REQUESTS']:continue
        parts=shlex.split(value,comments=True)
        if len(parts)>1:raise SystemExit('Invalid private Places configuration format')
        if not env.get(name):env[name]=parts[0] if parts else ''
binary=root/'.build/debug/places-context'
if not binary.exists():raise SystemExit('Run swift build -j 4 --product places-context first')
raise SystemExit(subprocess.run([str(binary)]+(a.arguments or ['status']),env=env).returncode)
