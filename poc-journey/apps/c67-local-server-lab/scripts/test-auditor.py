#!/usr/bin/env python3
import argparse,copy,json,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);p.add_argument('--live',action='store_true');a=p.parse_args()
rows=json.loads((a.evidence/'observations.json').read_text())
ready=next(r for r in rows if r['outcome'].get('plan') and r['outcome']['outcome']=='ready')
mutations={
 'short_dwell':lambda r:r['outcome']['plan']['stops'][0].update(leave=r['outcome']['plan']['stops'][0]['leave']-60),
 'missing_source':lambda r:r['outcome']['plan']['stops'][0].update(sourceIDs=[]),
 'wrong_departure':lambda r:r['outcome']['plan']['legs'][0].update(departure=r['outcome']['plan']['legs'][0]['departure']+60),
 'missing_return':lambda r:r['outcome']['plan']['legs'].pop(),
 'unsupported_ready':lambda r:r['outcome'].update(outcome='needs_places'),
 'false_batch_accounting':lambda r:r['outcome']['providerMetrics'].update(calls=0),
}
results=[]
for name,mutate in mutations.items():
 row=copy.deepcopy(ready);mutate(row)
 with tempfile.TemporaryDirectory() as directory:
  d=Path(directory);(d/'observations.json').write_text(json.dumps([row]))
  result=subprocess.run(['python3',str(root/'scripts/audit.py'),str(d)]+(['--live'] if a.live else []),capture_output=True,text=True)
  results.append({'mutation':name,'rejected':result.returncode!=0})
(a.evidence/'auditor-negative-controls.json').write_text(json.dumps(results,indent=2)+'\n')
assert all(x['rejected'] for x in results),results
print('Auditor rejected all',len(results),'forged results')
