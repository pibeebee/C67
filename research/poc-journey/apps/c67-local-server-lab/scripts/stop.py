#!/usr/bin/env python3
import argparse,json,os,signal,subprocess,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--data-dir',type=Path,default=root/'.local');a=p.parse_args()
state=a.data_dir/'process.json'
if not state.exists(): raise SystemExit('No lab-owned process recorded')
s=json.loads(state.read_text())
command=subprocess.run(['ps','-p',str(s['pid']),'-o','command='],text=True,capture_output=True).stdout.strip()
if command and not command.startswith(s['binary']+' '): raise SystemExit('PID no longer matches lab binary; refusing to stop')
if command:
 os.kill(s['pid'],signal.SIGTERM)
 for _ in range(50):
  status=subprocess.run(['ps','-p',str(s['pid']),'-o','stat='],text=True,capture_output=True).stdout.strip()
  if not status or status.startswith('Z'): break
  time.sleep(.1)
 else: raise SystemExit('Lab still shutting down; no forced kill issued')
Path(s['config']).unlink(missing_ok=True);state.unlink();print('Stopped lab server; revoked temporary token')
