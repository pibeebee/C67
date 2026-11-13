#!/usr/bin/env python3
import argparse,json,os,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--config',type=Path,default=root/'.local/client-config.json');a=p.parse_args()
c=json.loads(a.config.read_text())
if c['mode']!='replay': raise SystemExit('Refusing replay against non-replay server')
env=dict(os.environ,LAB_URL=c['baseURL'],LAB_ACCESS_TOKEN=c['token'])
raise SystemExit(subprocess.run([str(root/'.build/debug/planner-bench'),'replay',str(a.output.resolve())],env=env,cwd=root).returncode)
