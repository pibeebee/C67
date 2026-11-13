#!/usr/bin/env python3
"""C/D paired latency and itinerary quality. Failures remain in all-attempt denominators."""
import argparse,csv,json,statistics,base64
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args()
rows=json.loads((a.directory/'observations.json').read_text())
audit=json.loads((a.directory/'audit.json').read_text())
invalid={(x['case'],x['variant']) for x in audit['failed']}
def good(r):return (r.get('outcome')or{}).get('outcome')=='ready' and (r['caseID'],r['variant']) not in invalid
def med(v):return statistics.median(v) if v else None
families={};pairs=[];flat=[]
for family in ['N1','N3','N4','N5','REV5','MIX5','TIGHT5','SIX','UNKNOWN']:
 families[family]={}
 for variant in ['C','D']:
  allrows=[r for r in rows if r['family']==family and r['variant']==variant]
  ready=[r for r in allrows if good(r)]
  families[family][variant]={'attempted':len(allrows),'readyValid':len(ready),'outcomes':[(r.get('outcome')or{}).get('outcome','failed') for r in allrows],
    'medianReadySeconds':med([r['clientSeconds'] for r in ready]),'medianObservedSeconds':med([r['clientSeconds'] for r in allrows]),
    'medianETACalls':med([r['outcome']['providerMetrics']['calls'] for r in ready]),
    'medianETACells':med([r['outcome']['providerMetrics']['cells'] for r in ready])}
 grouped={}
 for r in rows:
  if r['family']==family and good(r):grouped.setdefault(r['caseID'],{})[r['variant']]=r
 for case,values in grouped.items():
  if set(values)!=set(['C','D']):continue
  c,d=values['C'],values['D'];pc=c['outcome']['plan'];pd=d['outcome']['plan']
  ec=pc['finish']-pc['request']['departure'];ed=pd['finish']-pd['request']['departure']
  delta=ed-ec;ratio=ed/ec
  pairs.append({'case':case,'family':family,'CSeconds':c['clientSeconds'],'DSeconds':d['clientSeconds'],
    'latencyRatioDOverC':d['clientSeconds']/c['clientSeconds'],'CElapsedSeconds':ec,'DElapsedSeconds':ed,
    'elapsedDifferenceSeconds':delta,'elapsedRatioDOverC':ratio,
    'travelDifferenceMinutes':pd['travelMinutes']-pc['travelMinutes'],
    'waitingDifferenceMinutes':pd['waitingMinutes']-pc['waitingMinutes'],
    'weatherRainExposureDifferenceMinutes':None,
    'COrder':[s['id'] for s in pc['stops']],'DOrder':[s['id'] for s in pd['stops']],
    'sameOrder':[s['id'] for s in pc['stops']]==[s['id'] for s in pd['stops']],
    'qualityFlag':delta>300 or ratio>1.05})
for f in ['N1','N3','N4','N5']:
 subset=[p for p in pairs if p['family']==f]
 families[f]['paired']={'completePairs':len(subset),'medianLatencyRatioDOverC':med([p['latencyRatioDOverC'] for p in subset]),
   'maximumElapsedWorseningSeconds':max([p['elapsedDifferenceSeconds'] for p in subset],default=None),
   'qualityFlags':sum(p['qualityFlag'] for p in subset)}
for r in rows:
 o=r.get('outcome')or{};plan=o.get('plan')or{}
 report=json.loads(base64.b64decode(plan['rawRoutingReport'])) if plan.get('rawRoutingReport') else {}
 traces=[]
 if plan.get('providerLog'):
  traces=[json.loads(x) for x in base64.b64decode(plan['providerLog']).splitlines()]
 validations=[e for e in traces if e['event']=='routing.fast_surrogate']
 chosen=report.get('fastest') or {}
 flat.append({'case':r['caseID'],'family':r['family'],'variant':r['variant'],'client_seconds':r['clientSeconds'],
  'outcome':o.get('outcome','failed'),'error':r.get('error',''),'ready_valid':good(r),
  'eta_calls':o.get('providerMetrics',{}).get('calls'),'eta_cells':o.get('providerMetrics',{}).get('cells'),
  'eta_failures':o.get('providerMetrics',{}).get('failures'),
  'validationAttempts':len(validations) if r['variant']=='D' else None,
  'elapsed_seconds':plan.get('finish',0)-plan.get('request',{}).get('departure',0) if plan.get('finish') else None,
  'travel_minutes':plan.get('travelMinutes'),'waiting_minutes':plan.get('waitingMinutes'),
  'rainExposureMinutes':chosen.get('rainExposureMinutes'),'unknownWeatherMinutes':chosen.get('unknownWeatherMinutes'),
  'order':'>'.join(s['id'] for s in plan.get('stops',[]))})
for pair in pairs:
 c=next(x for x in flat if x['case']==pair['case'] and x['variant']=='C')
 d=next(x for x in flat if x['case']==pair['case'] and x['variant']=='D')
 if c['rainExposureMinutes'] is not None and d['rainExposureMinutes'] is not None:pair['weatherRainExposureDifferenceMinutes']=d['rainExposureMinutes']-c['rainExposureMinutes']
summary={'observations':len(rows),'readyValid':sum(good(r) for r in rows),'auditFailures':audit['failed'],
 'families':families,'pairs':pairs,'qualityFlags':[p for p in pairs if p['qualityFlag']],
 'liveQualityInterpretation':'Provider responses/time may drift; actual paired objective differences are observations, not proof of algorithm regret or global optimality.',
 'firstValidTargetN5Under10s':families['N5']['D']['readyValid']>=3 and families['N5']['D']['medianReadySeconds']<10,
 'scope':'Shared real pins, live ETA/weather; no live discovery inside timer; first feasible D vs completed bounded optimizer C',
 'ETACalls':sum((r.get('outcome')or{}).get('providerMetrics',{}).get('calls',0) for r in rows)}
(a.directory/'fast-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
for name,data in [('fast-metrics.csv',flat),('paired-quality.csv',pairs)]:
 if data:
  with (a.directory/name).open('w') as f:w=csv.DictWriter(f,fieldnames=data[0].keys());w.writeheader();w.writerows(data)
print(json.dumps({k:summary[k] for k in ['observations','readyValid','qualityFlags','firstValidTargetN5Under10s','ETACalls']},indent=2))
