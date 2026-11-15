#!/usr/bin/env python3
"""Independent controlled oracle and itinerary arithmetic checks. No Swift imports/options reused."""
import argparse,copy,itertools,json,math,statistics
from collections import Counter
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
Z=ZoneInfo('Asia/Jakarta')
SCENARIOS='dry rain_morning rain_afternoon rain_indoor weather_missing weather_stale exposure_unknown early_close late_open split_session closed hours_stale required_conflict tight_deadline eta_unavailable budget_cut five_grid15 five_grid5'.split()
def require(x,msg):
 if not x:raise AssertionError(msg)
def fixture(response):
 kind=response['scenario']['id'];i=response['input'];base=datetime.fromtimestamp(i['departure'],Z).replace(hour=0,minute=0,second=0,microsecond=0).timestamp()
 options={}
 for stop in i['stops']:
  r=stop['request'];pid=r['placeID'];slots=[]
  ranges=[(540,1080)]
  if pid=='museum':
   if kind in ['early_close','required_conflict']:ranges=[(540,630)]
   if kind=='late_open':ranges=[(720,1080)]
   if kind=='split_session':ranges=[(540,630),(780,1080)]
   if kind in ['closed','hours_stale']:ranges=[]
  step=15 if kind=='five_grid15' else 5
  for m in range(540,1021,step):
   if not any(m>=a and m+60<=b for a,b in ranges):continue
   if pid=='museum' and kind=='required_conflict' and m!=900:continue
   rain=0
   if pid=='park':
    if kind in ['weather_missing','weather_stale','exposure_unknown']:rain=10000
    elif kind in ['rain_morning','rain_afternoon']:
     probs=[(.9 if h<12 else .05) if kind=='rain_morning' else (.05 if h<12 else .9) for h in range(m//60,math.ceil((m+60)/60))]
     rain=max(probs)*100
   slots.append((base+m*60,base+(m+60)*60,rain))
  options[pid]=slots
 return options

def reference(response):
 options=fixture(response);i=response['input'];n=len(options);t=response['fixedTravelSeconds'];best=None
 if not all(options.values()):return {'feasible':False,'reason':'context'}
 if response['travelUnavailable']:return {'feasible':False,'reason':'unavailable ETA'}
 # Ignore the algorithm's search budget: enumerate all physical candidates. A cutoff cannot prove infeasibility.
 def visit(left,cursor,wait,rain,route):
  nonlocal best
  if not left:
   finish=cursor+t
   if finish<=i['deadline']:
    score=(rain,finish,tuple(route))
    if best is None or score<best:best=score
   return
  if cursor+(len(left)+1)*t+len(left)*3600>i['deadline']:return
  if best is not None and rain>best[0]:return
  for pid in sorted(left):
   arrival=cursor+t
   for a,b,p in options[pid]:
    if a<arrival:continue
    w=wait+a-arrival
    if w>1800:break
    visit(left-{pid},b,w,rain+p,route+[pid])
 visit(set(options),i['departure'],0,0,[])
 return {'feasible':best is not None,'reason':'enumeration','optimumRainPenalty':best[0] if best else None,'optimumFinish':best[1] if best else None,'optimumOrder':best[2] if best else None}

def audit(response,controlled=True,live_row=None):
 o=response['output']['itinerary'] if controlled else response['itinerary']
 if controlled:
  i=response['input'];reqs={s['request']['placeID']:s['request'] for s in i['stops']};bounds=None;opts=fixture(response)
 else:
  i=live_row['input']
  # Input has prepared IDs; observations carry IDs in selected order via a separate selection manifest.
  reqs=live_row['requestByID'];bounds=live_row['operatingBounds'];opts=None
 visits=o['visits'];legs=o['legs']
 require(o['travelCalls']<=i['maxTravelCalls'],'ETA cap')
 if not visits:
  require(not o['status'].startswith('candidate'),'empty candidate')
  return {'status':o['status'],'candidate':False}
 require(o['status'] in ['candidate','candidate_with_unknown_preferences'],'noncandidate visits')
 require(len(visits)==len(reqs) and set(v['placeID'] for v in visits)==set(reqs),'all requested places once')
 require(len(legs)==len(visits)+1,'return leg')
 cursor=i['departure'];waiting=0;travel=0;dwell=0;totalrain=0;totalpref=0;prior=None
 for index,v in enumerate(visits):
  leg=legs[index];a=v['arrival'];s=v['visit']['start'];e=v['visit']['end'];pid=v['placeID'];r=reqs[pid]
  require(abs(leg['departure']-cursor)<.002 and abs(leg['evidence']['departure']-cursor)<.002,'exact departure')
  require(leg['to']==pid and (prior is None or leg['from']==prior),'leg identity')
  require(abs(leg['arrival']-leg['departure']-leg['evidence']['seconds'])<.002 and abs(a-leg['arrival'])<.002,'ETA arithmetic')
  require(s>=a and abs(e-s-r['durationMinutes']*60)<.002,'full dwell and arrival')
  minute=datetime.fromtimestamp(s,Z).hour*60+datetime.fromtimestamp(s,Z).minute
  require(minute%r['startStepMinutes']==0,'grid')
  if controlled:
   slot=next((x for x in opts[pid] if x[0]==s and x[1]==e),None);require(slot is not None,'hours, session, required time')
   totalrain+=slot[2]
   if r['avoidRain']:
    assessment=next(x for x in v['visit']['assessments'] if x['goal']=='lowerRain')
    require(assessment.get('penalty',10000)==slot[2],'independent weather penalty')
  else:require(any(s>=b['start'] and e<=b['end'] for b in bounds[pid]),'live hours full dwell')
  pref=r.get('preferredTime')
  if pref:totalpref+=max(0,pref['earliest']-minute,minute-pref['latest'])
  waiting+=s-a;travel+=leg['evidence']['seconds'];dwell+=e-s;cursor=e;prior=pid
 ret=legs[-1];require(ret['from']==prior and ret['to']==legs[0]['from'],'return identity')
 require(abs(ret['departure']-cursor)<.002 and abs(ret['evidence']['departure']-cursor)<.002,'return departure')
 require(abs(ret['arrival']-ret['departure']-ret['evidence']['seconds'])<.002,'return arithmetic')
 travel+=ret['evidence']['seconds']
 require(ret['arrival']<=i['deadline'] and abs(ret['arrival']-o['finish'])<.002,'return deadline')
 require(waiting<=1800.001 and abs(waiting-o['waitingSeconds'])<.002,'waiting cap and arithmetic')
 require(abs(travel-o['travelSeconds'])<.002 and abs(dwell-o['dwellSeconds'])<.002,'totals')
 require(abs(o['elapsedSeconds']-(travel+dwell+waiting))<.002,'elapsed decomposition')
 if controlled:require(abs(totalrain-o['penaltyByPriority'][1])<.002,'total weather penalty')
 else:require(abs(totalpref-o['penaltyByPriority'][0])<.002,'live preferred-time penalty')
 return {'status':o['status'],'candidate':True,'waitingSeconds':waiting,'rainPenalty':totalrain if controlled else None}

def main():
 p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args();rows=json.loads((a.directory/'controlled-observations.json').read_text());counts=Counter(r['response']['scenario']['id'] for r in rows)
 require(counts==Counter({s:3 for s in SCENARIOS}),'exact 18 x 3 coverage')
 refs={};checks=[]
 for row in rows:
  response=row['response'];sid=response['scenario']['id'];ref=refs.setdefault(sid,reference(response)) if sid not in refs else refs[sid]
  check=audit(response);check.update(scenario=sid,repetition=row['repetition'],reference=ref)
  if check['candidate']:
   require(ref['feasible'],'candidate against infeasible oracle')
   check['rainRegret']=check['rainPenalty']-ref['optimumRainPenalty'];check['finishRegretSeconds']=response['output']['itinerary']['finish']-ref['optimumFinish']
  checks.append(check)
 candidate=next(r['response'] for r in rows if r['response']['scenario']['id']=='rain_afternoon')
 mutations={
  'dwell':lambda d:d['output']['itinerary']['visits'][0]['visit'].__setitem__('end',d['output']['itinerary']['visits'][0]['visit']['end']-60),
  'waiting':lambda d:d['output']['itinerary'].__setitem__('waitingSeconds',1900),
  'rain':lambda d:d['output']['itinerary'].__setitem__('penaltyByPriority',[0,99,0,0]),
  'deadline':lambda d:d['input'].__setitem__('deadline',d['input']['departure']+60),
  'status':lambda d:d['output']['itinerary'].__setitem__('status','needs_context'),
  'return':lambda d:d['output']['itinerary']['legs'][-1].__setitem__('to','forged'),
 }
 rejected=[]
 for name,change in mutations.items():
  bad=copy.deepcopy(candidate);change(bad)
  try:audit(bad)
  except AssertionError:rejected.append(name)
 require(len(rejected)==len(mutations),'negative controls rejected')
 result={'rows':len(rows),'coverage':dict(counts),'references':refs,'checks':checks,'negativeControlsRejected':rejected,'allArithmeticChecksPassed':True}
 (a.directory/'controlled-independent-audit.json').write_text(json.dumps(result,indent=2));print(json.dumps({'rows':len(rows),'candidates':sum(c['candidate'] for c in checks),'negativeControlsRejected':rejected,'references':refs},indent=2))
if __name__=='__main__':main()
