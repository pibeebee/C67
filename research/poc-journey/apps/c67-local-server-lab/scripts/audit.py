#!/usr/bin/env python3
"""Independent reconstruction: no runner pass/feasible flag is accepted as proof."""
import argparse,base64,csv,datetime,hashlib,json,math,statistics
from pathlib import Path
from zoneinfo import ZoneInfo
root=Path(__file__).resolve().parents[1]
WIB=ZoneInfo('Asia/Jakarta')
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);p.add_argument('--live',action='store_true');p.add_argument('--fast',action='store_true');p.add_argument('--pair',help='Two live variants, e.g. D,E; no synthetic parity assertion');a=p.parse_args()
rows=json.loads((a.directory/'observations.json').read_text())
quality=json.loads((root/'Sources/PlannerEngine/Resources/quality.json').read_text())
timing=json.loads((root/'Sources/PlannerEngine/Resources/timing.json').read_text())
candidates={x['id']:x for x in quality['candidates']}; venues={x['id']:x for x in timing['venues']}
def epoch(v):
 if isinstance(v,(int,float)):return v
 return datetime.datetime.fromisoformat(v.replace('Z','+00:00')).timestamp()
def minute(value):
 d=datetime.datetime.fromtimestamp(value,WIB);return d.hour*60+d.minute+d.second/60+d.microsecond/60000000
def near(a,b,tol=1e-5):return abs(a-b)<=tol
checks=[];bycase={};flat=[]
for row in rows:
 errors=[]
 def check(ok,why):
  if not ok:errors.append(why)
 o=row.get('outcome');plan=(o or {}).get('plan');case=row['caseID'];variant=row['variant']
 if not a.live:
  check(not row.get('error'),'client error: '+str(row.get('error')))
  check(o is not None,'missing outcome')
 else:check(o is not None or bool(row.get('error')),'missing error/outcome')
 if o:
  check(o['evidence'] in ['live_native','live_rest','live_native_shared_real_pins','live_rest_shared_real_pins'] if a.live else o['evidence'].startswith('synthetic_replay'),'evidence mode mislabeled')
  if o['outcome'] in ['needs_places','needs_locations']:check(plan is None,'input-review outcome must not contain a completed plan')
  if plan and plan.get('status')=='ready':check(o['outcome']=='ready','ready plan/outcome mismatch')
  metrics=o['providerMetrics'];batches=metrics['requests'];queries=[q for batch in batches for q in batch]
  if not (a.live and variant=='A'):
   check(len(batches)==metrics['calls'],'call accounting')
   check(len(queries)==metrics['cells'],'cell accounting')
  for batch in batches:
   check(0<len(batch)<=10,'batch size')
   keys={(q['fromLatitude'],q['fromLongitude'],q['mode'],q['departure']) for q in batch}
   check(len(keys)==1,'incompatible batch origin/mode/departure')
  if case=='SIX' or case=='UNKNOWN':
   check(o['outcome']=='needs_places' and plan is None and metrics['cells']==0,'invalid facts/catalogue outcome')
  elif case=='TIGHT5':
   check(o['outcome'] in ['infeasible_lower_bound','no_feasible_candidate','incomplete_data','provider_unavailable','needs_places'],'deadline rejection reason')
   if o['outcome']=='needs_places':
    # The contemporary 09–13 case can fail the sourced session gate before the
    # aggregate dwell lower bound. Independently prove that earlier rejection.
    req=(o.get('review')or{}).get('request',{})
    weekday=datetime.datetime.fromtimestamp(req['departure'],WIB).isoweekday()
    blocked=[];total_dwell=0
    for ident in req['requiredCandidateIDs']:
     venue_id=candidates[ident]['venueID'];duration=req['durationByVenue'].get(venue_id,req['defaultDuration']);total_dwell+=duration*60
     schedule=next((x for x in venues[venue_id]['schedule'] if x['weekday']==weekday),{})
     sessions=schedule.get('sessions',[])
     possible=any(math.ceil(max(minute(req['departure']),s['start'])/15)*15+duration<=min(minute(req['deadline']),s['end']) for s in sessions)
     if not possible:blocked.append(ident)
    check(plan is None and metrics['cells']==0 and bool(blocked) and total_dwell>req['deadline']-req['departure'],'independent source-session and dwell rejection')
   elif o['outcome']=='infeasible_lower_bound':
    proof_request=(o.get('review')or{}).get('request',{})
    available=proof_request.get('deadline',0)-proof_request.get('departure',0)
    check(o['lowerBoundSeconds']==450*60 and o['availableSeconds']==available and o['lowerBoundSeconds']>available>0 and metrics['cells']==0,'lower-bound proof')
   else:check(plan is not None and plan.get('status')!='ready','rejected plan cannot be ready')
  elif not a.live:check(o['outcome']=='ready' and plan is not None,'expected ready')
  if plan and o['outcome']=='ready':
   req=plan['request'];stops=plan['stops'];legs=plan['legs'];selected=plan['prepared']['selectedIDs']
   if case=='REV5':
    baseline=next(((x.get('outcome')or{}).get('plan') for x in rows if x['caseID']=='N5-R3' and x['variant']==variant),None)
    check(baseline is not None,'revision baseline unavailable')
    if baseline:
     check(plan.get('baseAcceptedID')==baseline['id'],'revision wrong accepted baseline')
     final_venue=baseline['stops'][-1]['venueID']
     for baseline_stop in baseline['stops']:
      original=baseline['request']['durationByVenue'].get(baseline_stop['venueID'],baseline['request']['defaultDuration'])
      updated=req['durationByVenue'].get(baseline_stop['venueID'],req['defaultDuration'])
      check(updated==original+(30 if baseline_stop['venueID']==final_venue else 0),'revision changed wrong dwell')
     check(set(selected)==set(baseline['prepared']['selectedIDs']),'revision dropped or added a venue')
   check(set(s['id'] for s in stops)==set(selected) and len(stops)==len(set(selected)),'selected set/duplicates')
   check(set(req['requiredCandidateIDs']).issubset(selected),'required selection lost')
   check(len(stops)>=req['desiredCount'],'desired count lost')
   check(len({s['venueID'] for s in stops})==len(stops),'duplicate venues')
   check(len(legs)==len(stops)+1,'missing return leg')
   check(plan.get('finish') is not None and plan['finish']<=req['deadline'],'return deadline')
   if not a.live:check(plan['createdAt']==epoch('2026-11-06T00:00:00Z'),'evaluation clock drift')
   check(bool(plan['quality'].get('embedding')),'E5 silently fell back')
   if plan['quality'].get('embedding'):
    check(plan['quality']['embedding']['revision']=='614241f622f53c4eeff9890bdc4f31cfecc418b3','model revision')
   native_events=[]
   if a.live and variant=='A':
    try:
     all_events=[json.loads(line) for line in base64.b64decode(plan['providerLog']).splitlines()]
     session=next(e['sessionID'] for e in reversed(all_events) if e['event']=='routing.pipeline_completed')
     native_events=[e for e in all_events if e.get('sessionID')==session]
     native_calls=next(m['requests'] for m in plan['metrics'] if m['stage']=='mapkit_eta')
     check(native_calls==metrics['calls']==metrics['cells'],'native ETA accounting')
    except (KeyError,ValueError,StopIteration):check(False,'native provider evidence missing')
   cursor=req['departure'];fromID='origin';fromPin=next(x['selected'] for x in plan['prepared']['locations'] if x['id']=='origin')
   travel=0;waiting=0
   for index,leg in enumerate(legs):
    check(leg['providerStatus']=='available','unavailable final leg')
    duration=leg.get('seconds');arrival=leg.get('arrival')
    check(duration is not None and math.isfinite(duration) and duration>=0,'invalid ETA')
    if duration is None or arrival is None:continue
    check(near(leg['departure'],cursor),'leg departure skips previous visit')
    check(near(arrival,leg['departure']+duration),'arrival/ETA mismatch')
    travel+=duration
    if index<len(stops):
     stop=stops[index];id=stop['id'];venue=venues[stop['venueID']];candidate=candidates[id]
     check(candidate['venueID']==stop['venueID'],'venue identity')
     check(stop['area']==candidate['scope'],'area facts mismatch')
     toPin=stop['pin'];toID=id
     check(near(stop['arrival'],arrival),'stop arrival mismatch')
     check(stop['visit']>=arrival,'visit before arrival')
     expected=req['durationByVenue'].get(stop['venueID'],req['defaultDuration'])
     check(stop['duration']==expected and near(stop['leave']-stop['visit'],expected*60),'dwell duration')
     check(near(minute(stop['visit'])%15,0),'visit not on 15-minute grid')
     date=datetime.datetime.fromtimestamp(stop['visit'],WIB)
     day=next((x for x in venue['schedule'] if x['weekday']==date.isoweekday()),None)
     vm=minute(stop['visit']);lm=minute(stop['leave'])
     check(day is not None and any(s['start']<=vm and lm<=s['end'] for s in day['sessions']),'full stay outside published session')
     if day:
      check(day.get('lastEntry') is None or vm<=day['lastEntry'],'past last entry')
      check(not any(x['start']<=vm<x['end'] for x in day.get('entryPauses',[])),'entry during published pause')
     check(set(stop['sourceIDs'])==set(candidate['sourceIDs']+venue['sourceIDs']),'missing fact sources')
     needed=set(candidate['sourceIDs']+venue['sourceIDs'])
     sources=quality['sources']+timing['sources']
     for sid in needed:
      source=next((s for s in sources if s['id']==sid),None)
      check(source is not None,'missing source '+sid)
      if source:check(-300<=plan['createdAt']-epoch(source['checkedAt'])<7*86400,'stale/future source '+sid)
     waiting+=stop['visit']-arrival;cursor=stop['leave']
    else:
     toID='origin';toPin=next(x['selected'] for x in plan['prepared']['locations'] if x['id']=='origin')
     check(near(arrival,plan['finish']),'return endpoint finish mismatch')
    matching=[q for q in queries if q['fromID']==fromID and q['toID']==toID and near(q['departure'],leg['departure'])
      and near(q['fromLatitude'],fromPin['latitude']) and near(q['fromLongitude'],fromPin['longitude'])
      and near(q['toLatitude'],toPin['latitude']) and near(q['toLongitude'],toPin['longitude']) and q['mode']=='automobile']
    if a.live and variant=='A':
     observed=[]
     for event in native_events:
      if event['event']!='eta.requested':continue
      f=event.get('fields',{})
      try:
       origin=[float(x) for x in f['fromCoordinate'].split(',')]
       dest=[float(x) for x in f['toCoordinate'].split(',')]
       if f.get('mode')=='automobile' and abs(epoch(f['departure'])-leg['departure'])<1 and near(origin[0],fromPin['latitude']) and near(origin[1],fromPin['longitude']) and near(dest[0],toPin['latitude']) and near(dest[1],toPin['longitude']):observed.append(f['requestID'])
      except (KeyError,ValueError):pass
     check(bool(observed),'native final query identity/departure missing '+str(index))
    else:check(bool(matching),'no exact-time provider query for final leg '+str(index))
    fromID=toID;fromPin=toPin
   check(near(travel/60,plan['travelMinutes']),'travel objective accounting')
   check(near(waiting/60,plan['waitingMinutes']),'waiting objective accounting')
   check(not plan['conflicts'],'ready conflicts')
   if a.live:
    for stop in stops:
     weather=next((w for w in plan['weather'] if stop['id'] in w['memberIDs']),None)
     if stop.get('weatherProvider') is not None:
      check(weather is not None and weather['provider']==stop['weatherProvider'],'weather group/provider identity')
     if stop.get('rainChance') is not None and weather is not None:
      cursor=stop['visit'];highest=0.0
      for hour in sorted(weather['hours'],key=lambda x:x['start']):
       if hour['start']<=cursor<hour['start']+3600:
        check(0<=hour['rainChance']<=1,'invalid rain probability')
        highest=max(highest,hour['rainChance']);cursor=min(stop['leave'],hour['start']+3600)
        if cursor>=stop['leave']:break
      check(cursor>=stop['leave'],'rain score without full visit coverage')
      check(near(stop['rainChance'],highest),'rain score aggregation')
   bycase.setdefault(case,{})[variant]=plan['finish']-req['departure']
  weather=(plan or {}).get('weather',[])
  weather_complete=bool(weather) and all(w['provider']=='weatherkit' and w['status']=='available' and w.get('credit') and w['hours'] and w['expiresAt']>plan['createdAt'] for w in weather)
  flat.append({'case':case,'family':row['family'],'variant':variant,'condition':row['condition'],'outcome':o['outcome'],
    'client_seconds':row['clientSeconds'],'calls':metrics['calls'],'cells':metrics['cells'],'weather_complete':weather_complete,'valid':not errors})
 else:
  flat.append({'case':case,'family':row['family'],'variant':variant,'condition':row['condition'],'outcome':'failed',
   'client_seconds':row['clientSeconds'],'calls':None,'cells':None,'weather_complete':False,'valid':not errors})
 checks.append({'case':case,'variant':variant,'errors':errors,'passed':not errors})
parity=[]
for case,values in ({} if a.live else bycase).items():
 for variant in (['D'] if a.fast else ['B','C']):
  baseline='C' if a.fast else 'A'
  if baseline in values and variant in values:
   parity.append({'case':case,'variant':variant,'differenceSeconds':values[variant]-values[baseline],
     'passed':values[variant]<=values[baseline]+1})
summary={'observations':len(rows),'audited':len(checks),'passed':sum(c['passed'] for c in checks),'failed':[c for c in checks if not c['passed']],
 'parityComparisons':len(parity),'parityFailures':[x for x in parity if not x['passed']],
 'maximumAbsoluteObjectiveDifferenceSeconds':max((abs(x['differenceSeconds']) for x in parity),default=None),
 'speedConclusion':'NOT_EVALUATED: synthetic replay, not live provider latency','parity':parity,'checks':checks}
(a.directory/'audit.json').write_text(json.dumps(summary,indent=2)+'\n')
if a.live:
 paired={}
 for row in rows:
  audited=next(c for c in checks if c['case']==row['caseID'] and c['variant']==row['variant'])
  weather_ok=next(f['weather_complete'] for f in flat if f['case']==row['caseID'] and f['variant']==row['variant'])
  if row['condition'].startswith('fresh') and (row.get('outcome') or {}).get('outcome')=='ready' and audited['passed'] and weather_ok:
   paired.setdefault((row['family'],row['caseID']),{})[row['variant']]=row['clientSeconds']
 families={}
 for family in ['N3','N4','N5']:
  complete=[v for (f,c),v in paired.items() if f==family and set(v)=={'A','B','C'}]
  ratios=[v['C']/v['A'] for v in complete]
  ratios_b=[v['C']/v['B'] for v in complete]
  families[family]={'completePairs':len(complete),'medianCOverA':statistics.median(ratios) if ratios else None,
    'medianCOverB':statistics.median(ratios_b) if ratios_b else None,'supported':len(complete)>=3 and statistics.median(ratios)<=.70}
 if a.fast:
  families={}
  for family in ['N3','N4','N5']:
   complete=[v for (f,c),v in paired.items() if f==family and set(v)=={'C','D'}]
   families[family]={'completePairs':len(complete),
     'medianDOverC':statistics.median([v['D']/v['C'] for v in complete]) if complete else None,
     'medianDSeconds':statistics.median([v['D'] for v in complete]) if complete else None}
 summary['pairedLive']=families
 if a.pair:
  left,right=a.pair.split(',');families={}
  for family in ['N1','N3','N4','N5']:
   complete=[v for (f,c),v in paired.items() if f==family and set(v)=={left,right}]
   families[family]={'completePairs':len(complete),'medianRightOverLeft':statistics.median([v[right]/v[left] for v in complete]) if complete else None}
  summary['pairedLive']=families
 summary['allObservations']=len(rows)
 summary['successfulReady']=sum((r.get('outcome') or {}).get('outcome')=='ready' for r in rows)
 summary['speedConclusion']='INSUFFICIENT_EVIDENCE' if any(f['completePairs']<3 for f in families.values()) else 'SUPPORTED_IN_THIS_EXPERIMENT' if all(f.get('supported',False) for f in families.values()) and not summary['failed'] else 'NOT_SUPPORTED'
 if a.pair:summary['speedConclusion']='DESCRIPTIVE_POLICY_TRADEOFF; inspect paired client latency and objectives, no fixed speedup gate'
 if a.fast:
  n5=families['N5']
  summary['speedConclusion']='INSUFFICIENT_EVIDENCE' if n5['completePairs']<3 else 'N5_FIRST_VALID_TARGET_UNDER_10S_OBSERVED' if n5['medianDSeconds']<10 and not summary['failed'] else 'N5_FIRST_VALID_TARGET_NOT_SUPPORTED'
  summary['qualityConclusion']='Hard constraints audited; inspect paired-quality.csv and adversarial tests. Speed is not a proof of optimality or general quality equivalence.'
 (a.directory/'audit.json').write_text(json.dumps(summary,indent=2)+'\n')
with (a.directory/'metrics.csv').open('w') as f:
 writer=csv.DictWriter(f,fieldnames=flat[0].keys() if flat else ['case','family','variant','condition','outcome','client_seconds','calls','cells','valid']);writer.writeheader();writer.writerows(flat)
print(json.dumps({k:v for k,v in summary.items() if k!='parity'},indent=2))
raise SystemExit(1 if summary['failed'] or summary['parityFailures'] else 0)
