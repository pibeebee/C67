#!/usr/bin/env python3
"""Independent fixture model/reference/auditor. Does not import Swift planner/scorer."""
import argparse,copy,datetime as dt,itertools,json,math,random,statistics
from pathlib import Path
BASE=dt.datetime(2026,11,8,tzinfo=dt.timezone(dt.timedelta(hours=7))).timestamp()
GOALS=['preferredTime','lowerRain','quiet','comfortableTemperature']
def dump(p,x):p.write_text(json.dumps(x,indent=2)+'\n')
def generate(directory,seed):
    rng=random.Random(seed);cases=[]
    for split in ['development','holdout']:
      for family in ['flexible','afternoon','rain','split_hours','tight','quiet_unknown']:
       for rep in range(4):
        nodes=['origin','museum','gallery','park'];matrix=[[0 if a==b else rng.choice([300,420,600,780,960,1200,1500]) for b in range(4)] for a in range(4)]
        starts=660+rng.choice([0,15,30]);deadline=1080 if family!='tight' else 840+rng.choice([0,15])
        stops=[];windows={}
        for i,key in enumerate(nodes[1:]):
          bounds=[[540,1080]] if family!='split_hours' or key!='gallery' else [[540,750],[840,1020]]
          windows[key]=bounds
          periods=[{'open':{'day':d,'hour':a//60,'minute':a%60},'close':{'day':d,'hour':b//60,'minute':b%60}} for d in range(7) for a,b in bounds]
          place={'id':key,'displayName':{'text':'SYNTHETIC '+key},'location':{'latitude':-6.2,'longitude':106.83},'businessStatus':'OPERATIONAL','utcOffsetMinutes':420,'timeZone':{'id':'Asia/Jakarta'},'regularOpeningHours':{'periods':periods}}
          req={'placeID':key,'day':'2026-11-08','identityConfirmed':True,'availableStart':starts,'availableEnd':deadline,'durationMinutes':rng.choice([45,60,90]),'exposure':'outdoor' if key=='park' else 'indoor','exposureEvidence':'SYNTHETIC fixture activity','priorities':GOALS}
          if family=='afternoon' and key=='park':req['preferredTime']={'earliest':900,'latest':960,'required':False}
          if family=='rain' and key=='park':req['avoidRain']=True
          if family=='quiet_unknown' and key=='park':req['seeksQuiet']=True
          # Separate explicit required-window stress case within split session family.
          if family=='split_hours' and key=='gallery' and rep==3:req['preferredTime']={'earliest':840,'latest':855,'required':True}
          weather={'source':'SYNTHETIC deterministic hourly rain','fetchedAt':BASE-3600,'expiresAt':BASE+3600,'hours':[{'start':BASE+h*3600,'rainProbability':(0.9 if h<15 else 0.1) if rep%2==0 else (0.1 if h<14 else 0.9),'temperatureC':28} for h in range(8,20)]}
          stops.append({'snapshot':{'place':place,'fetchedAt':BASE-3600,'expiresAt':BASE+3600,'fieldMask':'SYNTHETIC','source':'SYNTHETIC','attribution':'SYNTHETIC no actual Google content'},'request':req,'weather':weather})
        inp={'originID':'origin','returnID':'origin','departure':BASE+starts*60,'deadline':BASE+deadline*60,'stops':stops,'priorities':GOALS,'beamWidth':12,'maxTravelCalls':512,'maximumTotalWaitingMinutes':30,'allVisitSlots':True,'policy':'beam'}
        cases.append({'id':f'{split}-{family}-{rep}','split':split,'family':family,'now':BASE,'input':inp,'nodeIDs':nodes,'matrix':matrix,'peakAfter':BASE+14*3600,'peakExtra':rng.choice([0,180,300]),'oracleWindows':windows})
    directory.mkdir(parents=True,exist_ok=True);dump(directory/'fixtures.json',{'seed':seed,'scope':'SYNTHETIC not representative Jakarta; independent discrete reference','cases':cases})
def eta(c,a,b,t):return c['matrix'][c['nodeIDs'].index(a)][c['nodeIDs'].index(b)]+(c['peakExtra'] if t>=c['peakAfter'] else 0)
def penalties(c,key,start,mode='full'):
    r=next(s['request'] for s in c['input']['stops'] if s['request']['placeID']==key);m=round((start-BASE)/60);d=r['durationMinutes'];p={}
    if 'preferredTime' in r and (mode!='elapsed' or r['preferredTime']['required']):
      w=r['preferredTime'];p['preferredTime']=max(0,w['earliest']-m,m-w['latest'])
    if mode=='full':
      if r.get('avoidRain'):
        weather=next(s['weather'] for s in c['input']['stops'] if s['request']['placeID']==key)
        overlapping=[h['rainProbability'] for h in weather['hours'] if h['start']<start+d*60 and h['start']+3600>start]
        p['lowerRain']=max(overlapping)*100 if r['exposure']=='outdoor' else 0
      if r.get('seeksQuiet'):p['quiet']=10000
    return p

def reference(c,mode='full'):
    inp=c['input'];goals=GOALS if mode=='full' else ['preferredTime'];best=None;count=0
    reqs={s['request']['placeID']:s['request'] for s in inp['stops']}
    def visit(remaining,last,t,wait,travel,pen,schedule):
      nonlocal best,count
      if not remaining:
        cost=eta(c,last,inp['returnID'],t);finish=t+cost
        if finish>inp['deadline']+1e-5:return
        count+=1;score=(*pen,finish,travel+cost)
        if best is None or score<best['score']:best={'score':score,'schedule':schedule,'waitingSeconds':wait,'finish':finish}
        return
      for key in remaining:
        cost=eta(c,last,key,t);arrive=t+cost;r=reqs[key]
        lo=max(r['availableStart'],math.ceil(((arrive-BASE)/60-1e-7)/15)*15)
        hi=min(r['availableEnd']-r['durationMinutes'],math.floor((arrive+1800-wait-BASE)/900+1e-7)*15)
        for m in range(lo,hi+1,15):
          end=m+r['durationMinutes'];w=r.get('preferredTime')
          if not any(m>=a and end<=b for a,b in c['oracleWindows'][key]):continue
          if w and w['required'] and not w['earliest']<=m<=w['latest']:continue
          start=BASE+m*60;newwait=wait+start-arrive
          if newwait>1800+1e-5:continue
          p=penalties(c,key,start,mode)
          visit([x for x in remaining if x!=key],key,BASE+end*60,newwait,travel+cost,[pen[i]+p.get(g,0) for i,g in enumerate(goals)],schedule+[(key,m)])
    visit(list(reqs),'origin',inp['departure'],0,0,[0]*len(goals),[])
    return {'best':best,'feasibleSchedules':count}

def audit_row(c,row):
    r=row['result'];visits=r['visits'];inp=c['input'];mode=row['ablation'];goals=GOALS if mode=='full' else ['preferredTime']
    ready_statuses={'candidate','candidate_with_unknown_preferences'}
    assert bool(visits)==(r.get('status') in ready_statuses),'status and visit coverage disagree'
    assert r['travelCalls']<=row['budget'],'budget'
    if not visits:
      assert r.get('status') in {'needs_context','no_candidate_within_search','incomplete_travel_data'},'unknown empty status'
      assert not r['legs'] and not r.get('finish'),'empty result inconsistency';return None
    reqs={s['request']['placeID']:s['request'] for s in inp['stops']}
    assert len(visits)==len(reqs) and {v['placeID'] for v in visits}==set(reqs),'stop coverage'
    assert len(r['legs'])==len(visits)+1,'leg coverage'
    cursor=inp['departure'];last='origin';wait=travel=dwell=0;pen=[0]*len(goals);full=[0]*len(GOALS)
    for i,v in enumerate(visits):
      key=v['placeID'];q=reqs[key];leg=r['legs'][i];o=v['visit'];start=o['start'];end=o['end'];m=(start-BASE)/60
      cost=eta(c,last,key,cursor)
      assert leg['from']==last and leg['to']==key,'leg identity'
      assert abs(leg['departure']-cursor)<1e-5 and abs(leg['evidence']['departure']-cursor)<1e-5,'departure'
      assert abs(leg['evidence']['seconds']-cost)<1e-5 and abs(leg['arrival']-cursor-cost)<1e-5,'ETA'
      assert abs(v['arrival']-leg['arrival'])<1e-5 and start>=v['arrival']-1e-5,'arrival'
      assert abs(end-start-q['durationMinutes']*60)<1e-5,'dwell'
      assert abs(m/15-round(m/15))<1e-6,'grid'
      assert q['availableStart']<=m and m+q['durationMinutes']<=q['availableEnd'],'availability'
      assert any(m>=a and m+q['durationMinutes']<=b for a,b in c['oracleWindows'][key]),'hours'
      w=q.get('preferredTime')
      if w and w['required']:assert w['earliest']<=m<=w['latest'],'required preference'
      p=penalties(c,key,start,mode);pfull=penalties(c,key,start,'full')
      actual={a['goal']:(a.get('penalty') if a.get('penalty') is not None else 10000) for a in o['assessments']}
      assert actual==p,('assessment',actual,p)
      if q.get('seeksQuiet') and mode=='full':assert o['unknowns'],'unknown quietness'
      pen=[pen[j]+p.get(g,0) for j,g in enumerate(goals)];full=[full[j]+pfull.get(g,0) for j,g in enumerate(GOALS)]
      wait+=start-v['arrival'];travel+=cost;dwell+=end-start;cursor=end;last=key
    leg=r['legs'][-1];cost=eta(c,last,'origin',cursor)
    assert leg['from']==last and leg['to']=='origin' and abs(leg['departure']-cursor)<1e-5,'return leg'
    assert abs(leg['evidence']['departure']-cursor)<1e-5 and abs(leg['evidence']['seconds']-cost)<1e-5,'return ETA'
    assert abs(leg['arrival']-cursor-cost)<1e-5,'return arrival'
    finish=cursor+cost;travel+=cost
    assert finish<=inp['deadline'] and abs(r['finish']-finish)<1e-5,'deadline'
    assert wait<=1800+1e-5 and abs(r['waitingSeconds']-wait)<1e-5,'waiting'
    assert abs(r['travelSeconds']-travel)<1e-5 and abs(r['dwellSeconds']-dwell)<1e-5,'totals'
    assert abs(r['elapsedSeconds']-(finish-inp['departure']))<1e-5,'elapsed'
    assert r['penaltyByPriority']==pen,'penalty vector'
    return {'score':(*pen,finish,travel),'fullScore':(*full,finish,travel),'wait':wait}

def audit(directory):
    cases=json.loads((directory/'fixtures.json').read_text())['cases'];rows=json.loads((directory/'observations.json').read_text());byid={c['id']:c for c in cases}
    assert len({c['id'] for c in cases})==len(cases),'duplicate fixture IDs'
    expected=set()
    for c in cases:
      configurations=[('elapsed','beam',512),('user','beam',512),('full','beam',512)]
      if c['split']=='holdout':
        caps=[24,48,96] if len(c['input']['stops'])==5 else [12,24,48]
        configurations += [('full',policy,cap) for cap in caps for policy in ['beam','firstFeasible','selectiveOrders']]
      expected.update((c['id'],*config) for config in configurations)
    keys=[(row['caseID'],row['ablation'],row['policy'],row['budget']) for row in rows]
    assert len(set(keys))==len(keys),'duplicate observations'
    assert set(keys)==expected,'missing or unexpected benchmark observations'
    refs={c['id']:reference(c) for c in cases};dump(directory/'independent-reference.json',refs)
    metrics=[]
    for row in rows:
      c=byid[row['caseID']];a=audit_row(c,row);ref=refs[c['id']]['best']
      metrics.append({'id':c['id'],'split':c['split'],'family':c['family'],'ablation':row['ablation'],'policy':row['policy'],'budget':row['budget'],'ready':a is not None,'oracleFeasible':ref is not None,'fullPriorityGap':(list(a['fullScore'][:4])!=list(ref['score'][:4])) if a and ref else None,'oracleScoreMatched':all(abs(x-y)<1e-5 for x,y in zip(a['fullScore'],ref['score'])) if a and ref else None,'calls':row['result']['travelCalls'],'processingSeconds':row['processingSeconds'],'waitingSeconds':a['wait'] if a else None,'penalties':list(a['fullScore'][:4]) if a else None})
    controls=[];base=next(row for row in rows if row['result']['visits'])
    for name in ['dwell','waiting','ETA','penalty']:
      bad=copy.deepcopy(base)
      if name=='dwell':bad['result']['visits'][0]['visit']['end']+=60
      if name=='waiting':bad['result']['waitingSeconds']+=60
      if name=='ETA':bad['result']['legs'][0]['evidence']['seconds']+=60
      if name=='penalty':bad['result']['penaltyByPriority'][0]+=1
      try:audit_row(byid[bad['caseID']],bad)
      except AssertionError:controls.append({'corruption':name,'rejected':True})
      else:raise AssertionError('Negative control accepted '+name)
    summary=[]
    for key in sorted(set((m['split'],m['ablation'],m['policy'],m['budget']) for m in metrics)):
      group=[m for m in metrics if (m['split'],m['ablation'],m['policy'],m['budget'])==key]
      summary.append({'split':key[0],'ablation':key[1],'policy':key[2],'budget':key[3],'cases':len(group),'ready':sum(m['ready'] for m in group),'oracleFeasible':sum(m['oracleFeasible'] for m in group),'missedFeasible':sum(m['oracleFeasible'] and not m['ready'] for m in group),'priorityGap':sum(m['fullPriorityGap'] is True for m in group),'oracleScoreMatched':sum(m['oracleScoreMatched'] is True for m in group),'medianCalls':statistics.median(m['calls'] for m in group),'medianProcessingSeconds':statistics.median(m['processingSeconds'] for m in group)})
    out={'observations':len(rows),'cases':len(cases),'hardAuditPassed':len(rows),'negativeControls':controls,'summary':summary,'scope':'Synthetic controlled reference, not human accuracy'}
    dump(directory/'fixture-metrics.json',metrics);dump(directory/'fixture-audit.json',out);print(json.dumps(out,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('command',choices=['generate','audit']);p.add_argument('directory',type=Path);p.add_argument('--seed',type=int,default=671107);a=p.parse_args()
    generate(a.directory,a.seed) if a.command=='generate' else audit(a.directory)
