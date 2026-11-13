#!/usr/bin/env python3
"""Paired, cold-cache replay of the committed old and working-tree native pipelines.
No network; timings exclude provider latency/pacing and are not iPhone timings.
"""
import argparse
import csv
import hashlib
import itertools
import json
import math
from pathlib import Path
import platform
import random
import statistics
import subprocess
import time
from datetime import datetime
from zoneinfo import ZoneInfo

SEEDS = [11, 67, 101]

def write(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n')

def configured(draft):
    draft.update(carUse='onDemand', routingRequestLimit=96, routingEvaluationLimit=12000,
                 routingSecondsLimit=3.0, routingBeamWidth=8)
    draft.pop('routingAlgorithm', None)
    return draft

def recorded(root):
    draft = configured(json.loads((root/'docs/examples/jakarta-opening-hours.json').read_text()))
    source = root/'docs/verification/opening-hours-jakarta-2026-11-03/comparison.json'
    problem = json.loads(source.read_text())['problem']
    oracle = [dict(a, **{'from': problem['nodes'][a['from']]['id'], 'to': problem['nodes'][a['to']]['id']}) for a in problem['arcs']]
    return dict(id='jakarta-recorded-static', kind='recorded_static', draft=draft, oracle=oracle,
                provenance='Recorded MapKit departure snapshot, held static for replay. Not a forecast for all later departures.',
                source=str(source.relative_to(root)), sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest())

def synthetic(count, geometry_seed, dynamic, tight=False):
    rng = random.Random(geometry_seed * 100 + count)
    points = [dict(id=f'p{i:02}', title=f'Synthetic {i}', query='', latitude=-6.2+rng.uniform(-.07,.07), longitude=106.82+rng.uniform(-.07,.07)) for i in range(count+1)]
    draft = configured(dict(departure='2026-11-05T00:00:00Z', timeZoneID='Asia/Jakarta', searchContext='Synthetic replay only',
        origin=points[0], end=dict(id='end', title='Unused', query=''), returnsToOrigin=True, defaultDwell=30,
        walking=False, transit=False, automobile=True, maximumWalkingMinutes=45, extraWeatherMinutes=15, rainWeight=2,
        stops=[dict(point=p, role='visit', exposure='unknown', opening=dict(serviceDate='2026-11-05', timeZoneID='Asia/Jakarta',
            opensMinute=420+(i%5)*45, closesMinute=1380 if i%3==0 else 1430,
            sourceNote='Synthetic constraint; not real opening hours')) for i,p in enumerate(points[1:],1)]))
    if tight:
        draft['stops'][0]['opening'].update(opensMinute=420, closesMinute=510)
    oracle=[]
    for i,a in enumerate(points):
        for j,b in enumerate(points):
            if i==j: continue
            distance=math.hypot((a['latitude']-b['latitude'])*111, (a['longitude']-b['longitude'])*110)
            seconds=round((3+distance*1.4)*60*rng.uniform(.65,1.6))
            factor=1+rng.uniform(.25,1.2)
            ranges=[(0,7200,seconds),(7200,172800,round(seconds*factor))] if dynamic else [(0,172800,seconds)]
            oracle.extend(dict(from_=a['id'],to=b['id'],mode='automobile',seconds=s,start=s0,end=s1,status='available') for s0,s1,s in ranges)
    for arc in oracle: arc['from']=arc.pop('from_')
    return dict(id=f'synthetic-{count}-{geometry_seed}-'+('timed' if dynamic else 'static')+('-tight' if tight else ''),kind='synthetic_timed' if dynamic else 'synthetic_static',draft=draft,oracle=oracle,
        provenance='Seeded asymmetric fictional ETA oracle. Timed durations increase after +120 min (FIFO); not provider evidence.')

def scorer(case):
    draft=case['draft']; grouped={}
    for arc in case['oracle']: grouped.setdefault((arc['from'],arc['to'],arc['mode']),[]).append(arc)
    start=datetime.fromisoformat(draft['departure'].replace('Z','+00:00')).astimezone(ZoneInfo(draft['timeZoneID']))
    start_minutes=start.hour*60+start.minute+start.second/60
    deadline=(1440-start_minutes)*60
    stops={s['point']['id']:s for s in draft['stops']}
    origin=draft['origin']['id']; end=origin if draft['returnsToOrigin'] else draft['end']['id']
    modes=[m for m,k in [('walking','walking'),('transit','transit'),('automobile','automobile')] if draft.get(k)]
    def options(a,b,t):
        values=[]
        for mode in modes:
            match=next((arc for arc in grouped.get((a,b,mode),[]) if arc.get('start',0)<=t<arc.get('end',172800)),None)
            if match and match.get('status')=='available' and match.get('seconds') is not None:
                sec=match['seconds']
                if mode!='walking' or sec<=draft['maximumWalkingMinutes']*60: values.append((sec,mode))
        return sorted(values,key=lambda x:(x[0], x[1]!='walking',x[1]))
    def evaluate(order):
        if len(order)!=len(stops) or set(order)!=set(stops): return None
        t=travel=wait=dwell=0; a=origin; legs=[]; conflicts=[]
        for i,b in enumerate(order+[end]):
            opts=options(a,b,t)
            if not opts: return None
            sec,mode=opts[0]; arrival=t+sec; visit=arrival
            stop=stops.get(b) if i<len(order) else None
            stay=0
            if stop:
                stay=0 if stop['role']=='transfer' else stop.get('dwellOverride',draft['defaultDwell'])*60
                window=stop.get('opening',{}) if stop['role']=='visit' else {}
                if window.get('opensMinute') is not None: visit=max(visit,(window['opensMinute']-start_minutes)*60)
                if window.get('closesMinute') is not None and visit+stay>(window['closesMinute']-start_minutes)*60+1e-5: conflicts.append('closing')
            leave=visit+stay
            legs.append(dict(from_=a,to=b,mode=mode,seconds=sec,departure=t,arrival=arrival,visit=visit,leave=leave))
            travel+=sec;wait+=visit-arrival;dwell+=stay;t=leave;a=b
            if t>deadline: conflicts.append('deadline')
        return dict(elapsed=t,travel=travel,waiting=wait,dwell=dwell,feasible=not conflicts,legs=legs)
    return evaluate

def validate(case,run):
    errors=[]; selected=run.get('selected')
    if run['requests']>case['draft']['routingRequestLimit']: errors.append('request cap exceeded')
    if run['requests']!=len(run['requestTrace']): errors.append('request trace/count mismatch')
    evaluate=scorer(case)
    for label,c in [('selected',selected)]+[(f'candidate-{i}',c) for i,c in enumerate(run.get('candidates',[]))]:
        if not c or not c['complete']: continue
        expected=evaluate(c['order'])
        if expected is None: errors.append(label+': no full oracle tour');continue
        if expected['feasible']!=c['feasible']: errors.append(label+': feasibility mismatch')
        for key in ['travel','waiting','dwell','elapsed']:
            if c[key] is None or abs(c[key]-expected[key])>.01: errors.append(label+': '+key+' mismatch')
        if len(c['legs'])!=len(expected['legs']): errors.append(label+': leg count');continue
        for actual,want in zip(c['legs'],expected['legs']):
            if actual['from']!=want['from_'] or actual['to']!=want['to'] or actual['mode']!=want['mode']: errors.append(label+': invalid leg/mode')
            for key in ['seconds','departure','arrival','visit','leave']:
                if actual[key] is None or abs(actual[key]-want[key])>.01: errors.append(label+': invalid '+key)
    if run['system']=='new-hybrid' and selected and selected['feasible']:
        feasible=[c for c in run.get('candidates',[]) if c['complete'] and c['feasible']]
        if feasible and selected['elapsed']>min(c['elapsed'] for c in feasible)+.01: errors.append('validated candidate discarded')
    run['auditErrors']=errors
    if errors: raise AssertionError(f"{case['id']}/{run['system']}/{run['seed']}: {errors}")

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['root','old','new','output']: p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--baseline',required=True);args=p.parse_args()
    out=args.output;out.mkdir(parents=True,exist_ok=True);(out/'cases').mkdir(exist_ok=True)
    cases=[recorded(args.root)]+[synthetic(n,g,d) for n in [4,8,12,20] for g in [17,73] for d in [False,True]]
    cases += [synthetic(n,g,True,tight=True) for n in [8,12] for g in [17,73]]
    impossible=synthetic(4,91,False);impossible['id']='synthetic-known-infeasible'
    impossible['kind']='synthetic_infeasible'
    impossible['draft']['stops'][0]['opening'].update(opensMinute=420,closesMinute=421)
    cases.append(impossible)
    manifest=dict(baseline=args.baseline,platform=platform.platform(),processor=platform.machine(),swift=subprocess.check_output(['xcrun','swiftc','--version'],text=True).strip(),
                  seeds=SEEDS,caseCount=len(cases),requestLimit=96,evaluationLimit=12000,secondsLimit=3,
                  method='Actual old/new native pipeline sources; same deterministic oracle, cold cache, no network or artificial ETA pacing. Alternate execution order by case/seed. No weather data in either arm.',sources={})
    names=['NativeTripModels.swift','NativeTripWeatherSupport.swift','NativeTripRoutingCore.swift','NativeTripEngine.swift','NativeTripRoutingBridge.swift','NativeTripTimeAwarePlanner.swift']
    for name in names:
        path='poc-c67/Features/NativePlanner/'+name
        manifest['sources'][path]={'new':hashlib.sha256((args.root/path).read_bytes()).hexdigest()}
        if name!='NativeTripTimeAwarePlanner.swift': manifest['sources'][path]['old']=hashlib.sha256(subprocess.check_output(['git','-C',str(args.root),'show',args.baseline+':'+path])).hexdigest()
    for relative in ['scripts/benchmark-routing-pipeline.sh','scripts/benchmark-routing-pipeline.py','checks/routing/NativeTripPipelineReplay.swift']:
        file=args.root/relative
        if file.exists(): manifest['sources'][relative]={'sha256':hashlib.sha256(file.read_bytes()).hexdigest()}
    manifest['caseSHA256']={c['id']:hashlib.sha256(json.dumps(c,sort_keys=True,ensure_ascii=False).encode()).hexdigest() for c in cases}
    write(out/'manifest.json',manifest)
    runs=[];references={};started=time.perf_counter()
    with (out/'runs.jsonl').open('w') as stream:
        for ci,case in enumerate(cases):
            path=out/'cases'/(case['id']+'.json');write(path,case)
            if len(case['draft']['stops'])<=4:
                evaluate=scorer(case)
                full=[evaluate(list(o)) for o in itertools.permutations([s['point']['id'] for s in case['draft']['stops']])]
                valid=[e for e in full if e and e['feasible']]
                references[case['id']]=min(e['elapsed'] for e in valid) if valid else None
            for si,seed in enumerate(SEEDS):
                arms=[('old-default',args.old,'default'),('old-local',args.old,'local'),('new-baseline',args.new,'baseline'),('new-hybrid',args.new,'default')]
                if (ci+si)%2: arms.reverse()
                for system,executable,algorithm in arms:
                    process=subprocess.run([str(executable),str(path),algorithm,str(seed)],capture_output=True,text=True,timeout=60)
                    if process.returncode: raise RuntimeError(f'{system}: {process.stderr}')
                    run=json.loads(process.stdout);run['system']=system;run['kind']=case['kind'];run['n']=len(case['draft']['stops'])
                    validate(case,run);runs.append(run);stream.write(json.dumps(run,ensure_ascii=False,allow_nan=False)+'\n');stream.flush()
            print(f"{ci+1}/{len(cases)} {case['id']}: completed and independently audited",flush=True)
    write(out/'references.json',references)
    columns=['case','kind','n','seed','system','feasible','elapsedMinutes','travelMinutes','waitingMinutes','requests','cacheHits','wallSeconds','solverSeconds','solverEvaluations','gapPercent']
    rows=[]
    for r in runs:
        s=r.get('selected');feasible=bool(s and s['feasible']);reference=references.get(r['case'])
        rows.append(dict(case=r['case'],kind=r['kind'],n=r['n'],seed=r['seed'],system=r['system'],feasible=feasible,
            elapsedMinutes=s['elapsed']/60 if feasible else None,travelMinutes=s['travel']/60 if feasible else None,waitingMinutes=s['waiting']/60 if feasible else None,
            requests=r['requests'],cacheHits=r['cacheHits'],wallSeconds=r['wallSeconds'],solverSeconds=sum(x['elapsed'] for x in r['solvers']),
            solverEvaluations=sum(x['evaluations'] for x in r['solvers']),gapPercent=(s['elapsed']/reference-1)*100 if feasible and reference else None))
    with (out/'metrics.csv').open('w') as stream:
        writer=csv.DictWriter(stream,fieldnames=columns,lineterminator='\n');writer.writeheader();writer.writerows(rows)
    by={(r['case'],r['seed'],r['system']):r for r in rows}
    def comparison(arm,kind=None):
        pairs=[(by[(c['id'],s,arm)],by[(c['id'],s,'new-hybrid')]) for c in cases if kind is None or c['kind']==kind for s in SEEDS]
        both=[(a,b) for a,b in pairs if a['feasible'] and b['feasible']]
        deltas=[b['elapsedMinutes']-a['elapsedMinutes'] for a,b in both]
        return dict(pairs=len(pairs),bothFeasible=len(both),oldFeasible=sum(a['feasible'] for a,b in pairs),newFeasible=sum(b['feasible'] for a,b in pairs),
            wins=sum(d<-.0002 for d in deltas),ties=sum(abs(d)<=.0002 for d in deltas),regressions=sum(d>.0002 for d in deltas),
            medianDeltaMinutes=statistics.median(deltas) if deltas else None,minDeltaMinutes=min(deltas) if deltas else None,maxDeltaMinutes=max(deltas) if deltas else None,
            medianImprovementPercent=statistics.median([(a['elapsedMinutes']-b['elapsedMinutes'])/a['elapsedMinutes']*100 for a,b in both]) if both else None)
    aggregate={}
    for arm in ['old-default','old-local','new-baseline','new-hybrid']:
        part=[r for r in rows if r['system']==arm]
        aggregate[arm]=dict(runs=len(part),feasible=sum(r['feasible'] for r in part),medianRequests=statistics.median(r['requests'] for r in part),
            medianWallSeconds=statistics.median(r['wallSeconds'] for r in part),maxWallSeconds=max(r['wallSeconds'] for r in part),medianSolverSeconds=statistics.median(r['solverSeconds'] for r in part),
            evaluationBudgetExceeded=sum(r['solverEvaluations']>12000 for r in part))
    summary=dict(cases=len(cases),runs=len(runs),auditErrors=sum(len(r['auditErrors']) for r in runs),totalSeconds=time.perf_counter()-started,
        aggregate=aggregate,vsOldDefault=comparison('old-default'),vsOldLocal=comparison('old-local'),vsNewBaseline=comparison('new-baseline'),
        byKind={k:{a:comparison(a,k) for a in ['old-default','old-local']} for k in ['recorded_static','synthetic_static','synthetic_timed','synthetic_infeasible']})
    write(out/'summary.json',summary)
    print(json.dumps(summary,indent=2))

if __name__=='__main__': main()
