#!/usr/bin/env python3
from pathlib import Path
import json,statistics
import argparse
parser=argparse.ArgumentParser();parser.add_argument('evidence',type=Path);args=parser.parse_args()
root=Path(__file__).resolve().parents[1];base=args.evidence
cases=json.loads((root/'Packages/PreferenceQuality/Sources/PreferenceQuality/Resources/quality-cases-v1.json').read_text())
index={c['id']:c for c in cases};summary=json.loads((base/'model-verified/series-summary.json').read_text())
runs={row['case']:json.loads((base/'model-verified'/(row['runID']+'.json')).read_text()) for row in summary}
rows=[];violations=[]
for cid,run in runs.items():
 c=index[cid];p=run['profile'];soft=set(p['prefer'])|({p['likedFeature']} if p.get('likedFeature') else set());soft-=set(p['must'])
 scores={}
 for method in ['category','semantic','combined']:
  top=run[method][:3];ids=[x['candidateID'] for x in top]
  if c['expectedReview'] and ids:violations.append([cid,method,'unconfirmed text ranked'])
  for id in ids:
   if id not in c['expectedEligible']:violations.append([cid,method,id])
  scores[method]={'top3':ids,'desirableHitCount':len(set(ids)&set(c['desirable'])),'supportedSoftFraction':(sum(len(set(x['supportedPreferences'])&soft) for x in top)/(len(top)*len(soft))) if soft and top else None}
 rows.append(dict(case=cid,status=run['status'],scores=scores,softCount=len(soft)))
comparison=[r for r in rows if r['status']=='comparison_completed' and r['softCount']>0]
wins={'combined_over_category':0,'category_over_combined':0,'ties':0}
for r in comparison:
 a=r['scores']['combined']['supportedSoftFraction'];b=r['scores']['category']['supportedSoftFraction']
 wins['combined_over_category' if a>b else 'category_over_combined' if a<b else 'ties']+=1
result=dict(scope='Diagnostic source-attribute coverage, not satisfaction, holdout accuracy or preference ground truth',modelCases=len(rows),semanticComparisons=sum(r['status']=='comparison_completed' for r in rows),gatePassed=sum(r['gatePassed']=='true' for r in summary),unsupportedTop3IDs=violations,softPreferenceComparisons=len(comparison),coverageComparison=wins,meanSupportedSoftFraction={m:statistics.mean(r['scores'][m]['supportedSoftFraction'] for r in comparison) for m in ['category','semantic','combined']},cases=rows)
(base/'evaluation-verified-metrics.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='cases'},indent=2))
