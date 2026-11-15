#!/usr/bin/env python3
"""Export only this frozen synthetic campaign from the current simulator container."""
import json,subprocess,shutil,argparse
from pathlib import Path
LAB=Path(__file__).resolve().parents[1];OUT=LAB/'artifacts/synthetic-user-2026-11-08'
p=argparse.ArgumentParser();p.add_argument('--persona',choices=['U1','U2','U3']);a=p.parse_args()
root=Path(subprocess.check_output(['xcrun','simctl','get_app_container','A548563C-F35D-45E9-92C8-C323A38033D1','giovanchristoffel.c67-context-lab','data'],text=True).strip())
source=root/'Documents/PersonalBenchmark/recommendations.json'
rows=json.loads(source.read_text())if source.exists()else[]
rows=[r for r in rows if (r.get('campaignLabel')or'').startswith('synthetic-user-')]
(OUT/'recommendations.json').write_text(json.dumps(rows,indent=2,ensure_ascii=False))
print('Exported synthetic recommendation attempts',len(rows))
plan=root/'Documents/PersonalBenchmark/personal-plan-latest.json'
if plan.exists():
 value=json.loads(plan.read_text());rid=value['input']['recommendationID'].upper()
 rec=next((r for r in rows if (r.get('recommendationID')or'').upper()==rid),None)
 if rec:
  case=rec['campaignLabel'].split('-')[2]
  (OUT/(case+'-plan.json')).write_text(json.dumps(value,indent=2,ensure_ascii=False));print('Exported plan',case)
 else:print('Ignored old unrelated plan')
state=root/'Library/Application Support/personal-state-ui-test.json'
if a.persona and state.exists():shutil.copy2(state,OUT/(a.persona+'-profile-state.json'))
