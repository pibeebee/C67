#!/usr/bin/env python3
"""Compare one physical iPhone suite to the frozen Mac suite without enlarging sample size."""
import argparse,json,statistics,copy
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);p.add_argument('phone',type=Path);a=p.parse_args()
def canonical_input(value):
 value=copy.deepcopy(value)
 for key in ['must','prefer','avoid','excludedIDs']:
  value['profile'][key]=sorted(value['profile'].get(key,[]))
 return value
mac=json.loads((a.evidence/'masked-1/series.json').read_text());phone=json.loads(a.phone.read_text())
assert {r['input']['id'] for r in mac}=={r['input']['id'] for r in phone}
lookup={r['input']['id']:r for r in mac};details=[];metricError=0;cosineError=0
for r in phone:
 m=lookup[r['input']['id']]
 assert r['datasetID']==m['datasetID'] and r['policy']==m['policy'] and r['evaluationClock']==m['evaluationClock']
 assert canonical_input(r['input'])==canonical_input(m['input']) and r['catalog']==m['catalog'] and r['documents']==m['documents']
 for ranking in r['rankings']:
  other=next(x for x in m['rankings'] if x['id']==ranking['id'])
  if ranking.get('metrics'):
   metricError=max(metricError,max(abs(ranking['metrics'][key]-other['metrics'][key]) for key in ranking['metrics']))
  if ranking['id']=='e5':
   scores={row['id']:row['secondary'] for row in other['rows']}
   cosineError=max(cosineError,max(abs(row['secondary']-scores[row['id']]) for row in ranking['rows']))
  full=[row['id'] for row in ranking['rows']];fullMac=[row['id'] for row in other['rows']]
  if full!=fullMac:details.append(dict(case=r['input']['id'],method=ranking['id'],topThreeChanged=full[:3]!=fullMac[:3],topThreePhone=full[:3],topThreeMac=fullMac[:3]))
scored=[r for r in phone if r['input']['family']!='safety']
means={m:statistics.mean(next(x['metrics']['ndcgAt3'] for x in r['rankings'] if x['id']==m) for r in scored) for m in ['category','lexical','e5','combined']}
result=dict(device='iPhone 17 / iOS 27.0.1 (24A446)',cases=len(phone),gatesAndStatesPassed=sum(r['gatePassed'] and r['status']==r['input']['expectedStatus'] for r in phone),
 meanNDCGAt3=means,caseMetricMaxDifference=metricError,maxCosineDifference=cosineError,changedFullRankings=len(details),changedTopThreeRankings=sum(d['topThreeChanged'] for d in details),changes=details,
 firstCaseSeconds=phone[0]['totalSeconds'],sumPipelineSeconds=sum(r['totalSeconds'] for r in phone),
 limitations='One scripted on-device suite over the same authored corpus, not a human walkthrough, latency benchmark or independent relevance sample. Encoder call counts include cache hits.')
(a.evidence/'iphone-comparison.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='changes'},indent=2))
