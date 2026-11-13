#!/usr/bin/env python3
"""Prove the fixture auditor rejects corrupted results; no provider calls."""
import copy,json,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];e=root/'artifacts/decision-sequence-2026-11-07'
rows=json.loads((e/'development-baseline.json').read_text())
index=next(i for i,r in enumerate(rows) if r['candidate'] and r['candidate']['complete'] and not r['candidate']['conflicts'])
changes={
 'wrong_eta':lambda r:r['candidate']['legs'][0]['chosen'].update(seconds=r['candidate']['legs'][0]['chosen']['seconds']+60),
 'wrong_departure':lambda r:r['candidate']['legs'][0].update(departure=r['candidate']['legs'][0]['departure']+60),
 'wrong_visit':lambda r:r['candidate']['legs'][0].update(visit=r['candidate']['legs'][0]['visit']+60),
 'wrong_dwell_accounting':lambda r:r['candidate'].update(dwellMinutes=r['candidate']['dwellMinutes']+15),
 'missing_return':lambda r:r['candidate']['legs'].pop(),
 'missing_stop':lambda r:r['candidate']['order'].pop(),
}
output=[]
for name,change in changes.items():
    altered=copy.deepcopy(rows);change(altered[index])
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp);path=tmp/'observations.json';path.write_text(json.dumps(altered))
        result=subprocess.run(['python3',str(root/'scripts/decision-fixtures.py'),'audit',str(e),'--observations',str(path),'--output',str(tmp/'audit.json')],capture_output=True,text=True)
        # An actual validation error is required, not just a crashed auditor.
        audit=json.loads((tmp/'audit.json').read_text()) if (tmp/'audit.json').exists() else {}
        output.append(dict(mutation=name,rejected=result.returncode!=0 and bool(audit.get('problems'))))
(e/'fixture-auditor-negative-controls.json').write_text(json.dumps(output,indent=2)+'\n')
assert all(x['rejected'] for x in output),output
print('Rejected',len(output),'corruptions with explicit audit errors')
