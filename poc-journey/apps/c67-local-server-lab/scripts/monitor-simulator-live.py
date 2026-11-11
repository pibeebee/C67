#!/usr/bin/env python3
"""Read and export an existing simulator run; never launches/retries a case."""
import argparse,csv,datetime,json,shutil,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--container-file',type=Path,required=True);p.add_argument('--run',required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--server-pid',required=True);p.add_argument('--seconds',type=int,default=5400);a=p.parse_args()
source=Path(a.container_file.read_text().strip())/'Documents/C67LocalServerLab'/a.run
a.output.mkdir(parents=True,exist_ok=True)
previous=None
with (a.output/'server-resources.csv').open('w') as resource:
 writer=csv.writer(resource);writer.writerow(['utc','rss_kib','cpu_percent','state'])
 for _ in range(a.seconds//5):
  sample=subprocess.run(['ps','-p',a.server_pid,'-o','rss=,%cpu=,stat='],capture_output=True,text=True).stdout.split()
  if len(sample)==3:writer.writerow([datetime.datetime.now(datetime.timezone.utc).isoformat(),*sample]);resource.flush()
  try:status=json.loads((source/'status.json').read_text())
  except (FileNotFoundError,json.JSONDecodeError):time.sleep(5);continue
  signature=(status['progress'],len(status['results']))
  if signature!=previous:
   for file in source.iterdir():
    if file.is_file():shutil.copyfile(file,a.output/file.name)
   print(datetime.datetime.now(datetime.timezone.utc).isoformat(),*signature,flush=True)
   if status['results']:
    r=status['results'][-1];o=r.get('outcome') or {}
    print(json.dumps({'case':r['caseID'],'variant':r['variant'],'seconds':r['clientSeconds'],'outcome':o.get('outcome'),'error':r.get('error'),'eta':o.get('providerMetrics'),'weather':[(w['provider'],w['status'],len(w['hours'])) for w in (o.get('plan') or {}).get('weather',[])]},default=str)[:1500],flush=True)
   previous=signature
  if status['complete'] or status['progress'].startswith(('Stopped:','Cancelled.')):
   shutil.copytree(source,a.output,dirs_exist_ok=True)
   print('MONITOR_DONE',status['complete'],flush=True);break
  time.sleep(5)
 else:print('MONITOR_LIMIT; run may still be active',flush=True)
