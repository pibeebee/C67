#!/usr/bin/env python3
"""Paired remaining-trip replay with an independent schedule auditor; no network."""
import argparse,copy,hashlib,importlib.util,itertools,json,math,subprocess,sys
from pathlib import Path
from datetime import datetime,timezone
from zoneinfo import ZoneInfo

def write(path,value): path.write_text(json.dumps(value,indent=2,allow_nan=False)+'\n')
def timestamp(value): return datetime.fromisoformat(value.replace('Z','+00:00')).timestamp() if isinstance(value,str) else value

def audit(case,run):
    errors=[];p=run['projection'];d=p['draft'];report=run['report']
    stops={s['point']['id']:s for s in d['stops']}
    end=d['origin']['id'] if d['returnsToOrigin'] else d['end']['id']
    original_start=timestamp(case['draft']['departure'])
    start=timestamp(d['departure']);deadline=timestamp(d['finishBy'])
    local=datetime.fromtimestamp(start,ZoneInfo(d['timeZoneID'])); midnight=local.replace(hour=0,minute=0,second=0,microsecond=0).timestamp()
    grouped={}
    for arc in case['oracle']:grouped.setdefault((arc['from'],arc['to'],arc['mode']),[]).append(arc)
    def evaluate(order):
        if len(order)!=len(stops) or set(order)!=set(stops):return None
        cursor=start;from_id=d['origin']['id'];travel=waiting=dwell=0;conflicts=[];legs=[]
        for i,to_id in enumerate(order+[end]):
            if from_id==to_id:seconds=0
            else:
                arc=next((a for a in grouped.get((from_id,to_id,'automobile'),[]) if a.get('start',0)<=cursor-original_start<a.get('end',172800)),None)
                if not arc or arc['status']!='available':return None
                seconds=arc['seconds']
            arrival=cursor+seconds;visit=arrival;stay=0
            if i<len(order):
                stop=stops[to_id];window=stop.get('opening') or {};stay=stop.get('dwellOverride',d['defaultDwell'])*60 if stop['role']=='visit' else 0
                if stop['role']=='visit':
                    if window.get('opensMinute') is not None:visit=max(visit,midnight+window['opensMinute']*60)
                    if window.get('closesMinute') is not None and visit+stay>midnight+window['closesMinute']*60+0.01:conflicts.append('closing')
            leave=visit+stay
            if leave>deadline+0.01:conflicts.append('deadline')
            legs.append((from_id,to_id,cursor,arrival,visit,leave,seconds))
            travel+=seconds;waiting+=visit-arrival;dwell+=stay;cursor=leave;from_id=to_id
        return dict(finish=cursor,elapsed=(cursor-start)/60,travelMinutes=travel/60,waitingMinutes=waiting/60,dwellMinutes=dwell/60,feasible=not conflicts,legs=legs)
    for candidate in report['candidates']:
        if not candidate['complete']:continue
        expected=evaluate(candidate['order'])
        if expected is None:errors.append('invalid complete order');continue
        if expected['feasible'] != (candidate['complete'] and not candidate['conflicts']):errors.append('feasibility')
        for key in ['travelMinutes','waitingMinutes','dwellMinutes','finish']:
            if abs(candidate[key]-expected[key])>0.02:errors.append('arithmetic '+key)
        if len(candidate['legs'])!=len(expected['legs']):errors.append('leg count')
        for leg,want in zip(candidate['legs'],expected['legs']):
            if (leg['from']['id'],leg['to']['id'])!=want[:2]:errors.append('leg identity')
            for key,value in zip(['departure','arrival','visit','leave'],want[2:6]):
                if abs(leg[key]-value)>0.02:errors.append('leg '+key)
            if abs(leg['chosen']['seconds']-want[6])>0.01:errors.append('ETA')
    selected=report.get('fastest')
    complete=[c for c in report['candidates'] if c['complete'] and not c['conflicts']]
    if selected and not selected['conflicts'] and complete:
        if selected['travelMinutes']+selected['waitingMinutes']+selected['dwellMinutes']>min(c['travelMinutes']+c['waitingMinutes']+c['dwellMinutes'] for c in complete)+0.01:errors.append('validated baseline lost')
    before=run['activeBefore'];after=run['activeAfter']
    if before['visits']!=after['visits'] or before['actualLegs']!=after['actualLegs']:errors.append('actual history changed')
    if end!=(case['draft']['origin']['id'] if case['draft']['returnsToOrigin'] else case['draft']['end']['id']):errors.append('endpoint changed')
    if p['draft']['origin']['id']!=next(v['stopID'] for v in before['visits'] if v['status']=='visiting'):errors.append('current anchor')
    expected_pending={v['stopID'] for v in before['visits'] if v['status']=='pending'}
    if set(stops)!=expected_pending:errors.append('pending targets lost')
    if run['requests']>96 or run['requests']!=len(run['requestTrace']):errors.append('request budget')
    if sum(s.get('evaluations',0) for s in run['solvers'])>12000:errors.append('evaluation budget')
    references=[x for order in itertools.permutations(stops) if (x:=evaluate(list(order))) and x['feasible']]
    return errors,min((r['elapsed'] for r in references),default=None)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('root',type=Path);parser.add_argument('output',type=Path);args=parser.parse_args()
    root=args.root;out=args.output;out.mkdir(parents=True,exist_ok=True)
    assert not (out/'runs.jsonl').exists(),'Use a new output directory'
    sys.dont_write_bytecode=True
    spec=importlib.util.spec_from_file_location('oldbench',root/'scripts/benchmark-routing-pipeline.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    cases=[]
    for seed in [401,613]:
        for count in [2,4,6]:
            for dynamic in [False,True]:
                c=module.synthetic(count,seed,dynamic);c['variant']='extend';cases.append(c)
    for seed in [401,613]:
        for variant in ['tight','skip']:
            c=module.synthetic(6,seed,True);c['variant']=variant;c['id']+='-'+variant;cases.append(c)
    for seed in [877,1237]:
        for count in [4,6]:
            for dynamic in [False,True]:
                c=module.synthetic(count,seed,dynamic);c['variant']='end-only' if count==4 else 'extend';c['id']+='-additional';cases.append(c)
    (out/'cases').mkdir()
    for c in cases:write(out/'cases'/(c['id']+'.json'),c)
    names=['NativeTripModels','NativeTripWeatherSupport','NativeTripInputSupport','NativeTripRoutingCore','NativeTripEngine','NativeTripRoutingBridge','NativeTripTimeAwarePlanner','NativeTripLocalStore','NativeTripActiveTrip','NativeTripActivePlanner']
    paths=[root/'poc-c67/Features/NativePlanner'/(n+'.swift') for n in names]+[root/'checks/routing/NativeTripPipelineReplay.swift',root/'checks/active/NativeTripActiveReplay.swift']
    write(out/'manifest.json',dict(network=False,cases=len(cases),seeds=[11,67,101],arms=['baseline','adaptive'],budget=dict(requests=96,evaluations=12000,CPUSeconds=3),sourceSHA256={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}))
    command=['xcrun','--sdk','macosx','swiftc','-O','-swift-version','5','-D','PIPELINE_CHECKS','-parse-as-library','-module-cache-path',str(out/'module-cache'),*map(str,paths),'-o',str(out/'active-replay')]
    with (out/'compile.log').open('w') as log:subprocess.run(command,check=True,stdout=log,stderr=subprocess.STDOUT)
    runs=[];errors=[]
    with (out/'runs.jsonl').open('w') as stream:
        for index,c in enumerate(cases):
            for seed in [11,67,101]:
                for arm in (['baseline','adaptive'] if index%2 else ['adaptive','baseline']):
                    run=json.loads(subprocess.check_output([str(out/'active-replay'),str(out/'cases'/(c['id']+'.json')),arm,str(seed)],text=True))
                    found,reference=audit(c,run);run['auditErrors']=found;run['referenceElapsedMinutes']=reference
                    errors.extend(dict(id=c['id'],arm=arm,seed=seed,error=e) for e in found);runs.append(run);stream.write(json.dumps(run,allow_nan=False)+'\n')
    summary=dict(cases=len(cases),runs=len(runs),pairs=len(cases)*3,auditErrors=errors,same=0,faster=0,slower=0,baselineFeasible=0,adaptiveFeasible=0,bothInfeasible=0,baselineRequests=0,adaptiveRequests=0)
    for c in cases:
        for seed in [11,67,101]:
            pair={r['arm']:r for r in runs if r['id']==c['id'] and r['seed']==seed}
            def chosen(arm):
                v=pair[arm]['report'].get('fastest');return v if v and v['complete'] and not v['conflicts'] else None
            a,b=chosen('baseline'),chosen('adaptive')
            summary['baselineFeasible']+=a is not None;summary['adaptiveFeasible']+=b is not None
            summary['baselineRequests']+=pair['baseline']['requests'];summary['adaptiveRequests']+=pair['adaptive']['requests']
            if a and b:
                delta=b['finish']-a['finish'];summary['same' if abs(delta)<0.01 else 'faster' if delta<0 else 'slower']+=1
            elif not a and not b:summary['bothInfeasible']+=1
    write(out/'summary.json',summary);print(json.dumps(summary,indent=2));assert not errors
if __name__=='__main__':main()
