#!/usr/bin/env python3
"""Bounded simulator result export; no credentials in output."""
import argparse,json,shutil,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--simulator',required=True);p.add_argument('--run',required=True)
p.add_argument('--output',type=Path,required=True);p.add_argument('--limit',type=int,default=1000);a=p.parse_args()
data=Path(subprocess.check_output(['xcrun','simctl','get_app_container',a.simulator,'giovanchristoffel.c67-trip-integration','data'],text=True).strip())
source=data/'Documents/C67LocalServerLab'/a.run;began=time.monotonic();last=None;status={}
while time.monotonic()-began<a.limit:
    if (source/'status.json').exists():
        status=json.loads((source/'status.json').read_text());key=(len(status.get('results',[])),status['progress'])
        if key!=last:
            print('SIMULATOR',key[0],key[1],flush=True);last=key
        if status.get('complete') or status['progress'].startswith(('Stopped:','Cancelled')):break
    time.sleep(5)
if source.exists():shutil.copytree(source,a.output,dirs_exist_ok=True)
print('EXPORTED',str(a.output),'complete',status.get('complete',False),flush=True)
raise SystemExit(0 if status.get('complete') else 1)
