#!/usr/bin/env python3
"""Independent synthetic fixture generator, exhaustive reference and result auditor.
No planner imports, no distance/time prior, and no provider requests.
"""
import argparse, collections, hashlib, itertools, json, math, random, statistics
from pathlib import Path

def write(p, value):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(value, indent=2, sort_keys=True)+'\n')

def cost(case, a, b, seconds):
    if case['unavailable']: return None
    # Continuous triangular congestion, slope bounded so arrival functions are FIFO.
    minute=seconds/60
    peak=max(0, 1-abs(minute-600)/180, 1-abs(minute-1020)/180)
    return case['costs'][a][b]*(1+case['amplitudes'][a][b]*peak)

def evaluate(case, order):
    cursor=case['departure']*60; start=cursor; travel=wait=0; legs=[]; valid=True
    nodes={x['id']:x for x in case['stops']}; a='origin'
    for b in list(order)+['origin']:
        seconds=cost(case,a,b,cursor)
        if seconds is None: return None
        arrival=cursor+seconds; visit=arrival; dwell=0
        if b!='origin':
            node=nodes[b]; dwell=node['dwell']*60
            choices=[max(math.ceil((arrival-1e-7)/900)*900,lo*60)
                     for lo,hi in node['windows']
                     if max(math.ceil((arrival-1e-7)/900)*900,lo*60)+dwell<=hi*60+1e-7]
            if not choices: valid=False
            else: visit=min(choices)
        leave=visit+dwell
        legs.append(dict(a=a,b=b,departure=cursor,seconds=seconds,arrival=arrival,visit=visit,leave=leave))
        travel+=seconds; wait+=visit-arrival; cursor=leave; a=b
    valid=valid and cursor<=case['deadline']*60+1e-7
    return dict(feasible=valid,elapsed=cursor-start,travel=travel,waiting=wait,finish=cursor,order=list(order),legs=legs)

def oracle(case):
    values=[evaluate(case,p) for p in itertools.permutations(x['id'] for x in case['stops'])]
    good=[x for x in values if x and x['feasible']]
    return dict(state='unavailable' if case['unavailable'] else 'feasible' if good else 'infeasible',
                permutations=len(values),best=min(good,key=lambda x:(x['elapsed'],x['travel'],x['order'])) if good else None)

def generate(directory):
    if (directory/'fixtures.json').exists(): raise FileExistsError('Use a fresh output directory; existing fixtures are preserved')
    cases=[]
    for split,seeds in [('development',[1103,2207]),('holdout',[3301,4409,5501,6607])]:
        for n in range(3,7):
            for family in ['asymmetric','bottleneck','time_dependent','sessions','deadline','unavailable']:
                for seed in seeds:
                    rng=random.Random(f'{seed}/{family}/{n}')
                    ids=['origin']+[f's{i}' for i in range(n)]
                    matrix={a:{b:(0 if a==b else rng.randrange(120,2101,30)) for b in ids} for a in ids}
                    amps={a:{b:(rng.choice([0,.4,.8,1.2]) if family=='time_dependent' else 0) for b in ids} for a in ids}
                    stops=[dict(id=f's{i}',latitude=-6.2-.009*i,longitude=106.83+.006*((i*3)%n),
                                dwell=rng.choice([30,45,60]),windows=[[420,1140]]) for i in range(n)]
                    case=dict(id=f'{split}-{family}-N{n}-{seed}',split=split,family=family,
                              departure=480,deadline=1140,stops=stops,costs=matrix,amplitudes=amps,
                              unavailable=family=='unavailable')
                    if family=='bottleneck':
                        # Coordinate-nearest first stop is expensive; this is an explicit stress case.
                        matrix['origin']['s0']=4200
                        for i in range(n-1): matrix[f's{i}'][f's{i+1}']=3000
                    planted=[x['id'] for x in stops];rng.shuffle(planted)
                    if family=='sessions':
                        cursor=case['departure']*60;a='origin';byid={x['id']:x for x in stops}
                        for b in planted:
                            cursor=math.ceil((cursor+matrix[a][b])/900)*900
                            node=byid[b];lo=int(cursor/60)
                            node['windows']=[[lo,lo+node['dwell']+15],[min(1050,lo+180),1140]]
                            cursor+=node['dwell']*60;a=b
                    if family=='deadline':
                        p=evaluate(case,planted)
                        case['deadline']=int(math.ceil(p['finish']/900)*15)
                        if seed in [2207,4409]: case['deadline']=480+sum(x['dwell'] for x in stops)-15
                    cases.append(case)
    write(directory/'fixtures.json',dict(schemaVersion=1,provenance='synthetic directed FIFO costs; not observed roads',cases=cases))
    refs={x['id']:oracle(x) for x in cases}
    write(directory/'reference.json',refs)
    write(directory/'fixture-manifest.json',dict(caseCount=len(cases),splits=dict(collections.Counter(x['split'] for x in cases)),
         sha256=hashlib.sha256((directory/'fixtures.json').read_bytes()).hexdigest(),
         referenceSHA256=hashlib.sha256((directory/'reference.json').read_bytes()).hexdigest(),
         objective='earliest-valid-start FIFO elapsed; then travel; every stop and return required'))
    print('Generated',len(cases),'cases; independent exhaustive references')

def audit(directory, observations, output):
    cases={x['id']:x for x in json.loads((directory/'fixtures.json').read_text())['cases']}
    refs=json.loads((directory/'reference.json').read_text());rows=json.loads(observations.read_text())
    problems=[];metrics=[]
    epoch=1793984400.0  # 2026-11-07T00:00:00+07:00
    for row in rows:
        case=cases[row['caseID']];ref=refs[row['caseID']];candidate=row.get('candidate')
        feasible=bool(candidate and candidate['complete'] and not candidate['conflicts'])
        computed=evaluate(case,candidate['order']) if candidate else None
        if feasible and (not computed or not computed['feasible']): problems.append([row['caseID'],row['variant'],'false_feasible'])
        if feasible:
            if len(candidate['order'])!=len(case['stops']) or set(candidate['order'])!={x['id'] for x in case['stops']}:
                problems.append([row['caseID'],row['variant'],'stop_coverage'])
            expected=computed['legs'] if computed else []
            legs=candidate['legs']
            if len(legs)!=len(expected):problems.append([row['caseID'],row['variant'],'leg_coverage'])
            for leg,ex in zip(legs,expected):
                for key in ['departure','arrival','visit','leave']:
                    if abs(leg.get(key,0)-epoch-ex[key])>.01:problems.append([row['caseID'],row['variant'],'leg_'+key])
                if abs((leg.get('chosen') or {}).get('seconds',-999)-ex['seconds'])>.01:
                    problems.append([row['caseID'],row['variant'],'provider_value'])
            actual_elapsed=(candidate['travelMinutes']+candidate['waitingMinutes']+candidate['dwellMinutes'])*60
            if abs(actual_elapsed-computed['elapsed'])>.01: problems.append([row['caseID'],row['variant'],'elapsed'])
        gap=(computed['elapsed']-ref['best']['elapsed']) if feasible and ref['best'] else None
        metrics.append(dict(caseID=row['caseID'],variant=row['variant'],split=case['split'],family=case['family'],
            oracle=ref['state'],feasible=feasible,missedFeasible=ref['state']=='feasible' and not feasible,
            gapSeconds=gap,materialGap=gap is not None and (gap>300+.01 or gap>ref['best']['elapsed']*.05+.01),
            calls=row['requests'],cells=row['cells'],cpuSeconds=row['cpuSeconds'],
            elapsedSeconds=computed['elapsed'] if feasible else None,travelSeconds=computed['travel'] if feasible else None))
    summary={}
    for split in sorted(set(x['split'] for x in metrics)):
        for variant in sorted(set(x['variant'] for x in metrics)):
            group=[x for x in metrics if x['split']==split and x['variant']==variant]
            if not group:continue
            gaps=[x['gapSeconds'] for x in group if x['gapSeconds'] is not None]
            eligible=[x for x in group if x['oracle']=='feasible']
            summary[f'{split}/{variant}']=dict(observations=len(group),oracleFeasible=len(eligible),
                missedFeasible=sum(x['missedFeasible'] for x in group),materialGaps=sum(x['materialGap'] for x in group),
                qualityFailures=sum(x['missedFeasible'] or x['materialGap'] for x in group),
                medianGapSeconds=statistics.median(gaps) if gaps else None,maxGapSeconds=max(gaps) if gaps else None,
                medianCalls=statistics.median(x['calls'] for x in eligible),medianCells=statistics.median(x['cells'] for x in eligible),
                medianLocalWallSeconds=statistics.median(x['cpuSeconds'] for x in group))
    # No duplicates or missing variants within a split.
    signatures=[(x['caseID'],x['variant']) for x in metrics]
    if len(signatures)!=len(set(signatures)):problems.append(['duplicate_observation'])
    for split in set(x['split'] for x in metrics):
        expected={k for k,v in cases.items() if v['split']==split}
        for variant in set(x['variant'] for x in metrics if x['split']==split):
            if {x['caseID'] for x in metrics if x['split']==split and x['variant']==variant}!=expected:problems.append([split,variant,'missing_case'])
    write(output,dict(passed=not problems,problems=problems,summary=summary,metrics=metrics,
        scope='synthetic FIFO oracle; raw cpuSeconds is local wall time, not process CPU; no field accuracy or production optimality claim'))
    print(json.dumps(dict(passed=not problems,problems=problems[:5],summary=summary),indent=2))
    if problems: raise SystemExit(1)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('command',choices=['generate','audit']);p.add_argument('directory',type=Path)
    p.add_argument('--observations',type=Path);p.add_argument('--output',type=Path);a=p.parse_args()
    if a.command=='generate':generate(a.directory)
    else:audit(a.directory,a.observations,a.output)
