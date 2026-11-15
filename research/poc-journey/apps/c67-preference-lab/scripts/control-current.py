#!/usr/bin/env python3
"""Predetermined six-case diagnostic using the old prompt and original 17s budget.
No Google data, no hidden brief in request, no paid fallback.
"""
import json, statistics, time, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
c=json.loads((ROOT/'.local/connection.json').read_text())
cases=json.loads((ROOT/'Sources/PreferenceCore/Resources/cases.json').read_text())[:6]
scores=json.loads((ROOT/'artifacts/e5-audit.json').read_text())['scoresByQuery']
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
out=ROOT/'artifacts/current-contract-17s.json';rows=[]
for item in cases:
 query='Find experiences for these interests: '+', '.join(sorted(item['interests']))+'. '
 body={'interests':item['interests'],'candidates':item['candidates'],'semantic':scores.get(query,{})}
 request=urllib.request.Request(c['baseURL']+'/legacy-synthetic',data=json.dumps(body).encode(),
   headers={'Authorization':'Bearer '+c['token'],'Content-Type':'application/json'})
 began=time.monotonic()
 try:
  with opener.open(request,timeout=20) as response:r=json.load(response)
 except Exception as e:r={'ids':[],'mode':'failed','errorCode':type(e).__name__,'attempts':0}
 ranked=r.get('ids',[])[:3];expected=set(item['preferredIDs'])
 rows.append(dict(r,caseID=item['id'],topIDs=ranked,top1=bool(ranked and ranked[0] in expected),
  precision3=len(expected.intersection(ranked))/3,clientSeconds=time.monotonic()-began,
  budgetSeconds=17,source='current-system-prompt-and-diversity-on-owned-synthetic-data'))
 out.write_text(json.dumps(rows,indent=2)+'\n')
 print(item['id'],r.get('mode'),r.get('model'),round(rows[-1]['clientSeconds'],3),r.get('errorCode'),flush=True)
print('Saved',len(rows),'diagnostic controls')
