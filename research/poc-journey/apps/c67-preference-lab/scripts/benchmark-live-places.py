#!/usr/bin/env python3
"""Live technical evidence only. Persist own inputs, counts and timing, never place payloads.
Not a human-accuracy study. No LLM calls or provider content embedding.
"""
import collections, datetime as dt, hashlib, json, statistics, sys, time, urllib.request, uuid
from pathlib import Path
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/(sys.argv[1] if len(sys.argv)>1 else 'artifacts/live-places-2026-11-09');OUT.mkdir(parents=True,exist_ok=True)
config=json.loads((ROOT/'.local/connection.json').read_text());opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
def need(v,must=False):return {'value':v,'must':must}
tomorrow=dt.datetime.now(ZoneInfo('Asia/Jakarta')).date()+dt.timedelta(days=1)
cases=[
 ('reading-onsite',['reading'],{'readingActivity':need('onsite',True)},{}),
 ('reading-buy',['reading'],{'readingActivity':need('buy')},{}),
 ('coffee-reading-together',['reading','coffee'],{'readingActivity':need('onsite',True),'coffeeRelation':need('together',True)},{}),
 ('coffee-reading-separate',['reading','coffee'],{'readingActivity':need('onsite'),'coffeeRelation':need('separate')},{}),
 ('shopping-no-reading-default',['shopping'],{},{}),
 ('coffee-lower-spending',['coffee'],{'spending':need('low')},{}),
 ('coffee-hours-11',['coffee'],{}, {'visitAt':dt.datetime.combine(tomorrow,dt.time(11),ZoneInfo('Asia/Jakarta')).isoformat(),'durationMinutes':60}),
 ('coffee-hours-03',['coffee'],{}, {'visitAt':dt.datetime.combine(tomorrow,dt.time(3),ZoneInfo('Asia/Jakarta')).isoformat(),'durationMinutes':60})]
rows=[];llm_before=json.loads((ROOT/'.local/usage.json').read_text()).get('attempts',0)
def post(body):
 request=urllib.request.Request(config['baseURL']+'/discover',data=json.dumps(body).encode(),headers={'Authorization':'Bearer '+config['token'],'Content-Type':'application/json'})
 began=time.monotonic()
 with opener.open(request,timeout=23) as response:result=json.load(response)
 return result,time.monotonic()-began
for ident,interests,needs,extra in cases:
 body=dict(requestID=str(uuid.uuid4()),revision=1,interests=interests,needs=needs,area='Jakarta Pusat',**extra)
 try:
  result,client=post(body);places=result['places'];ids=[p['id'] for p in places]
  assert len(ids)==len(set(ids)),'duplicate place IDs'
  assert result['requestID']==body['requestID'],'response context'
  assert places,'live case returned no results'
  expected=set(needs)|({'coffee'} if 'coffee' in interests else set())|({'readingActivity'} if 'reading' in interests else set())
  for p in places:
   checks=p['checks'];byid={c['id']:c for c in checks}
   assert expected<=set(byid),'lost requirement'
   if any(c['must'] and c['status']=='unknown' and c.get('scope','venue')=='venue' for c in checks):assert p['requiredStatus']!='supported','unknown promoted to supported'
   if any(c['must'] and c['status']=='contradicted' and c.get('scope','venue')=='venue' for c in checks):assert p['requiredStatus']=='contradicted','required conflict hidden'
   if needs.get('readingActivity',{}).get('value')=='onsite':assert byid['readingActivity']['status']=='unknown','unverified reading policy'
  if ident=='coffee-reading-together':assert len(result['searches'])==1
  if ident=='coffee-reading-separate':assert {g['id'] for g in result['searches']}=={'coffee','reading'}
  if ident=='shopping-no-reading-default':assert all('perpustakaan' not in g['query'] for g in result['searches'])
  row={'id':ident,'interests':interests,'needs':needs,'visit':extra,'places':len(places),'searchGroups':len(result['searches']),
    'queries':[g['query'] for g in result['searches']],'clientSeconds':client,'serviceSeconds':result['seconds'],
    'providerCalls':result['providerCalls'],'checks':dict(collections.Counter(c['status'] for p in places for c in p['checks'])),
    'requiredStates':dict(collections.Counter(p['requiredStatus'] for p in places)),
    'readingStates':dict(collections.Counter(c['status'] for p in places for c in p['checks'] if c['id']=='readingActivity')),
    'hoursStates':dict(collections.Counter(c['status'] for p in places for c in p['checks'] if c['id']=='visitHours')),
    'warnings':len(result['warnings']),'outcome':'passed','invariantsChecked':True}
  if ident=='reading-buy' and result['pageTokens']:
   follow=dict(body,requestID=str(uuid.uuid4()),pageTokens=result['pageTokens']);page,elapsed=post(follow)
   merged=list(dict.fromkeys(ids+[p['id'] for p in page['places']]))
   row['pagination']={'initial':len(ids),'additionalUnique':len(merged)-len(ids),'clientSeconds':elapsed,'providerCalls':page['providerCalls']}
 except Exception as error:row={'id':ident,'outcome':'failed','errorType':type(error).__name__}
 rows.append(row);(OUT/'observations.json').write_text(json.dumps(rows,indent=2)+'\n')
 print(ident,row['outcome'],row.get('places'),round(row.get('clientSeconds',0),3),flush=True)
llm_after=json.loads((ROOT/'.local/usage.json').read_text()).get('attempts',0)
summary={'cases':len(rows),'passed':sum(r['outcome']=='passed' for r in rows),'llmCallsDuringDiscovery':llm_after-llm_before,
 'participants':0,'rawProviderPayloadsPersisted':False,'timestamp':dt.datetime.now(dt.timezone.utc).isoformat()}
good=[r for r in rows if r['outcome']=='passed']
if good:summary['medianClientSeconds']=statistics.median(r['clientSeconds'] for r in good)
(OUT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
sources={}
for p in [ROOT/'scripts/live_places.py',ROOT/'scripts/server.py',ROOT/'scripts/benchmark-live-places.py',ROOT/'Sources/PreferenceCore/LivePlaceContracts.swift']:
 sources[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
(OUT/'source-hashes.json').write_text(json.dumps(sources,indent=2)+'\n')
print(json.dumps(summary,indent=2))
if summary['passed']!=len(rows) or summary['llmCallsDuringDiscovery']!=0:raise SystemExit(1)
