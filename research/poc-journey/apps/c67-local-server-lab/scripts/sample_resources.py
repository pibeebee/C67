#!/usr/bin/env python3
import argparse,csv,datetime,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--pid',required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--seconds',type=int,default=180);a=p.parse_args()
a.output.parent.mkdir(parents=True,exist_ok=True)
with a.output.open('w') as f:
 w=csv.writer(f);w.writerow(['utc','rss_kib','cpu_percent','state'])
 for _ in range(a.seconds):
  v=subprocess.run(['ps','-p',a.pid,'-o','rss=,%cpu=,stat='],capture_output=True,text=True).stdout.split()
  if len(v)!=3:break
  w.writerow([datetime.datetime.now(datetime.timezone.utc).isoformat(),*v]);f.flush()
  if v[2].startswith('Z'):break
  time.sleep(1)
