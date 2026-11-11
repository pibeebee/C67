#!/usr/bin/env python3
"""Build descriptive tables from original Simulator records and independently audit live arithmetic."""
import csv,json,statistics,sys
from collections import defaultdict
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
from importlib.util import spec_from_file_location,module_from_spec
spec=spec_from_file_location('audit',Path(__file__).with_name('audit-dynamic-context.py'));audit=module_from_spec(spec);spec.loader.exec_module(audit)
d=Path(sys.argv[1]);records=json.loads((d/'controlled-observations.json').read_text());meta=json.loads((d/'runtime-selection.json').read_text());live=json.loads((d/'live-observations.json').read_text());controlled=defaultdict(list);groups=defaultdict(list)
for r in records:controlled[r['response']['scenario']['id']].append(r)
for r in live:groups[(r['input']['policy'],len(r['input']['stops']),r['input']['startStepMinutes'])].append(r)
def at(t):return datetime.fromtimestamp(t,ZoneInfo('Asia/Jakarta')).strftime('%H:%M')
def summary(rows,controlled=False):
 results=[r['response']['output'] if controlled else r['response'] for r in rows]
 median=lambda f:statistics.median(f(r,v) for r,v in zip(rows,results))
 first=results[0]['itinerary'];out={'runs':len(rows),'candidateCount':sum(bool(v['itinerary']['visits']) for v in results),'clientMedianSeconds':median(lambda r,v:r['clientSeconds']),'clientMinSeconds':min(r['clientSeconds'] for r in rows),'clientMaxSeconds':max(r['clientSeconds'] for r in rows),'routingMedianSeconds':median(lambda r,v:v['metrics']['routingSeconds']),'etaAdapterMedianSeconds':median(lambda r,v:v['metrics']['etaAdapterSeconds']),'serverMedianSeconds':median(lambda r,v:v['metrics']['serverTotalSeconds']),'preparationMedianSeconds':median(lambda r,v:v['metrics']['preparationSeconds']),'etaCalls':[v['metrics']['etaCalls'] for v in results],'status':sorted(set(v['itinerary']['status'] for v in results)),'waitingMinutes':[v['itinerary']['waitingSeconds']/60 for v in results],'searchTruncated':all(v['itinerary']['searchTruncated'] for v in results),'sampleOrder':[(meta['stops'].get(x['placeID'],{}).get('label',x['placeID']),at(x['visit']['start']),at(x['visit']['end'])) for x in first['visits']],'rainPenalty':first['penaltyByPriority'][1] if first['penaltyByPriority'] else None,'preferredTimePenaltyMinutes':first['penaltyByPriority'][0] if first['penaltyByPriority'] else None}
 return out
checks=[]
for r in live:
 reqs={};count=len(r['input']['stops'])
 for s in r['input']['stops']:
  match=next((pid,v) for pid,v in meta['stops'].items() if v['preparedID']==s['endpoint']['preparedID'])
  reqs[match[0]]={'durationMinutes':s['durationMinutes'],'startStepMinutes':r['input']['startStepMinutes'],'preferredTime':s.get('preferredTime')}
 r['requestByID']=reqs
 checks.append({'stops':count,'grid':r['input']['startStepMinutes'],'repetition':r['repetition'],**audit.audit(r['response'],controlled=False,live_row=r)})
 require=audit.require
require({k for k in groups if k[0]=='firstFeasible'}=={('firstFeasible',3,15),('firstFeasible',3,5),('firstFeasible',5,15),('firstFeasible',5,5)},'live coverage')
require(all(len(v)==3 for k,v in groups.items() if k[0]=='firstFeasible'),'three repetitions per primary live pair')
result={'controlled':{k:summary(v,True) for k,v in controlled.items()},'live':{f'{k[0]}-{k[1]}stops-grid{k[2]}':summary(v) for k,v in sorted(groups.items())},'liveAudit':checks,'limits':'n=3; descriptive only; live ETA changes over time and all plans remain bounded searches'}
(d/'benchmark-summary.json').write_text(json.dumps(result,indent=2))
with (d/'benchmark-summary.csv').open('w') as file:
 fields=['case','runs','candidateCount','clientMedianSeconds','clientMinSeconds','clientMaxSeconds','routingMedianSeconds','serverMedianSeconds','etaCalls','status','waitingMinutes','sampleOrder'];writer=csv.DictWriter(file,fieldnames=fields);writer.writeheader()
 for prefix,bucket in [('controlled',result['controlled']),('live',result['live'])]:
  for name,values in bucket.items():writer.writerow({'case':prefix+'/'+name,**{k:values[k] for k in fields if k!='case'}})
print(json.dumps(result['live'],indent=2))
