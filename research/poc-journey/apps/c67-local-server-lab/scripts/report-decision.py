#!/usr/bin/env python3
"""Summarize frozen quality, discovery, and contemporary D/E live evidence."""
import argparse,base64,collections,csv,datetime,json,statistics
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args();d=a.directory
def read(name):return json.loads((d/name).read_text())
def median(xs):return statistics.median(xs) if xs else None
rows=read('controlled-simulator/observations.json');audit=read('controlled-simulator/audit.json')
invalid={(x['case'],x['variant']) for x in audit['failed']};flat=[];pairs=[]
for r in rows:
    o=r.get('outcome')or{};plan=o.get('plan')or{};metrics=o.get('providerMetrics',{})
    raw=json.loads(base64.b64decode(plan['rawRoutingReport'])) if plan.get('rawRoutingReport') else {}
    first_internal=None
    if plan.get('providerLog'):
        events=[json.loads(line) for line in base64.b64decode(plan['providerLog']).splitlines()]
        event_name='routing.fast_validated_candidate' if r['variant']=='D' else 'routing.selective_validated_candidate'
        validated=[x for x in events if x['event']==event_name]
        values=raw.get('candidates',[])
        if len(validated)==len(values):
            for event,value in zip(validated,values):
                if value.get('complete') and not value.get('conflicts'):
                    stamp=datetime.datetime.fromisoformat(event['at'].replace('Z','+00:00')).timestamp()
                    first_internal=max(0,stamp-plan['createdAt']);break
    flat.append(dict(case=r['caseID'],family=r['family'],variant=r['variant'],clientSeconds=r['clientSeconds'],
        outcome=o.get('outcome','failed'),error=r.get('error'),calls=metrics.get('calls'),cells=metrics.get('cells'),
        readyValid=o.get('outcome')=='ready' and (r['caseID'],r['variant']) not in invalid,
        validationCount=len(raw.get('candidates',[])),firstInternalFeasibleApproxSeconds=first_internal,
        elapsedSeconds=plan['finish']-plan['request']['departure'] if plan.get('finish') else None,
        travelMinutes=plan.get('travelMinutes'),waitingMinutes=plan.get('waitingMinutes'),
        order='>'.join(x['id'] for x in plan.get('stops',[]))))
for case in dict.fromkeys(x['case'] for x in flat):
    by={x['variant']:x for x in flat if x['case']==case and x['readyValid']}
    if set(by)!={'D','E'}:continue
    left,right=by['D'],by['E']
    pairs.append(dict(case=case,family=left['family'],DSeconds=left['clientSeconds'],ESeconds=right['clientSeconds'],
        latencyRatioEOverD=right['clientSeconds']/left['clientSeconds'],
        elapsedDifferenceSeconds=right['elapsedSeconds']-left['elapsedSeconds'],
        travelDifferenceMinutes=right['travelMinutes']-left['travelMinutes'],
        waitingDifferenceMinutes=right['waitingMinutes']-left['waitingMinutes'],sameOrder=left['order']==right['order']))
families={}
for f in dict.fromkeys(x['family'] for x in flat):
    families[f]={}
    for v in ['D','E']:
        group=[x for x in flat if x['family']==f and x['variant']==v];ready=[x for x in group if x['readyValid']]
        families[f][v]=dict(attempts=len(group),ready=len(ready),outcomes=dict(collections.Counter(x['outcome'] for x in group)),
            medianReadySeconds=median([x['clientSeconds'] for x in ready]),medianCalls=median([x['calls'] for x in ready]),
            medianCells=median([x['cells'] for x in ready]),validationCounts=[x['validationCount'] for x in ready])
    matched=[x for x in pairs if x['family']==f]
    families[f]['paired']=dict(count=len(matched),medianEOverD=median([x['latencyRatioEOverD'] for x in matched]))
summary=dict(observations=len(rows),readyValid=sum(x['readyValid'] for x in flat),auditFailures=audit['failed'],
    families=families,pairs=pairs,holdout=read('holdout-audit.json')['summary'],discovery=read('discovery-summary.json'),
    secondaryControl=read('secondary-control-audit.json')['summary'],
    interpretation='Synthetic oracle gap is not Jakarta accuracy; live D/E objective equality is not optimality; discovery proxy is not human relevance.')
(d/'decision-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
for name,items in [('live-metrics.csv',flat),('live-paired-quality.csv',pairs)]:
    if items:
        with (d/name).open('w') as f:w=csv.DictWriter(f,fieldnames=items[0].keys());w.writeheader();w.writerows(items)
fixture_metrics=[]
for source in ['development-baseline-audit.json','development-interventions-audit.json','holdout-audit.json','secondary-control-audit.json']:
    fixture_metrics+=read(source)['metrics']
with (d/'fixture-metrics.csv').open('w') as f:
    w=csv.DictWriter(f,fieldnames=fixture_metrics[0].keys());w.writeheader();w.writerows(fixture_metrics)
print(json.dumps({k:summary[k] for k in ['observations','readyValid','auditFailures','families']},indent=2))
