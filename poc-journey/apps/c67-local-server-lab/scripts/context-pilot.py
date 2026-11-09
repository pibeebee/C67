#!/usr/bin/env python3
"""Private env loader and hard wall-time boundary; keys never enter argv/output."""
import argparse,os,shlex,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('arguments',nargs=argparse.REMAINDER);a=p.parse_args()
env=dict(os.environ)
allowed={'GOOGLE_PLACES_API_KEY','APPLE_TEAM_ID','MAPS_KEY_ID','MAPS_KEY_PATH','WEATHER_KEY_ID','WEATHER_KEY_PATH','WEATHER_SERVICE_ID'}
for raw in (root/'.env.local').read_text().splitlines():
    line=raw.strip().removeprefix('export ')
    if '=' not in line:continue
    name,value=line.split('=',1);name=name.strip()
    if name not in allowed:continue
    parts=shlex.split(value,comments=True)
    if len(parts)>1:raise SystemExit('Invalid private config format')
    if not env.get(name):env[name]=parts[0] if parts else ''
try:result=subprocess.run([str(root/'.build/debug/context-pilot')]+a.arguments,env=env,timeout=1500)
except subprocess.TimeoutExpired:raise SystemExit('Pilot exceeded frozen25min wall limit; checkpoint files retained')
raise SystemExit(result.returncode)
