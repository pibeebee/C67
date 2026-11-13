#!/usr/bin/env python3
"""Wait for primary checkpoint, then run bounded diagnostics; never retries provider failures."""
import json,subprocess,sys,time
from pathlib import Path
root=Path(__file__).resolve().parents[1];out=root/'artifacts/context-five-2026-11-07';live=out/'live-resolved'
def load(p):return json.loads(p.read_text())
def ledger():
 g=1;h=8;c=0 # one boundedGoogle probe; Apple-only probes2+6HTTP
 for name in ['live','live-recovery','live-final','live-resolved','diagnostic30','diagnostic60']:
  p=out/name/'budget-checkpoint.json'
  if p.exists():
   d=load(p);g+=d.get('googleCalls',0);h+=d.get('appleHTTPCalls',0);c+=d.get('appleETACells',0)
 return {'google':g,'appleHTTP':h,'etaCells':c}
def run(args,log):
 with (out/log).open('w') as f:
  p=subprocess.run(args,cwd=root,stdout=f,stderr=subprocess.STDOUT,timeout=1500)
 if p.returncode:raise SystemExit('Stopped: '+log+'; failed attempts retained, no retry')
start=time.monotonic()
while not (live/'live-report.json').exists():
 if (live/'budget-checkpoint.json').exists():raise SystemExit('Primary stopped without complete report; inspect checkpoints')
 if time.monotonic()-start>1500:raise SystemExit('Primary wait exceeded25min')
 time.sleep(2)
run(['swift','build','-j','4','--product','context-pilot'],'build-diagnostic.log')
run([sys.executable,'scripts/audit-context-pilot-live.py',str(live)],'live-independent-audit.log')
notes=[]
for cap in [30,60]:
 d=ledger()
 if d['google']+5>20 or d['etaCells']+64>1000 or d['appleHTTP']+80>1200:
  notes.append({'waitingCap':cap,'skipped':'would exceed frozen campaign budget','ledger':d});break
 if cap==60 and (out/'skip-extra-control').exists():
  notes.append({'waitingCap':cap,'skipped':'account usage checkpoint requested no optional expansion'});break
 destination=out/('diagnostic'+str(cap))
 run([sys.executable,'scripts/context-pilot.py','five-diagnostic',str(destination),str(cap)],'diagnostic'+str(cap)+'.log')
 run([sys.executable,'scripts/audit-context-pilot-live.py',str(destination)],'diagnostic'+str(cap)+'-audit.log')
 r=load(destination/'live-report.json');ready=bool(r['rows'][0]['result']['visits'])
 notes.append({'waitingCap':cap,'ready':ready,'ledger':ledger()})
 print('Diagnostic waiting',cap,'ready',ready,flush=True)
 if ready:break
(out/'followup-summary.json').write_text(json.dumps({'notes':notes,'ledger':ledger()},indent=2)+'\n')
print('Followup finished',ledger(),flush=True)
