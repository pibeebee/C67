#!/usr/bin/env python3
"""Operator setup for simulator benchmarks; selections come from runtime APIs, not an engine catalogue."""
import argparse,json,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];PRIVATE=ROOT/'.local/dynamic-context-simulator'
p=argparse.ArgumentParser();p.add_argument('action',choices=['search','prepare','export']);p.add_argument('--query');p.add_argument('--label');p.add_argument('--day',default='2026-11-10');p.add_argument('--index',type=int,default=0);p.add_argument('--apple-query');p.add_argument('--choices',type=Path);p.add_argument('--output',type=Path);a=p.parse_args()
c=json.loads((PRIVATE/'client-config.json').read_text());record=PRIVATE/'runtime-discovery.json'
d=json.loads(record.read_text()) if record.exists() else {'search':{},'prepared':{},'timings':[]}
def call(route,body):
 req=urllib.request.Request(c['baseURL']+'/v1/lab/context/'+route,data=json.dumps(body).encode(),headers={'Authorization':'Bearer '+c['token'],'Content-Type':'application/json'})
 began=time.perf_counter()
 with urllib.request.urlopen(req,timeout=180) as r:out=json.load(r)
 d['timings'].append({'phase':route,'label':a.label or a.query,'clientSeconds':time.perf_counter()-began})
 return out
if a.action=='search':
 require=a.query and a.label
 if not require:raise SystemExit('--query and --label required')
 found=call('search',{'query':a.query});d['search'][a.label]=found
 print(json.dumps([{'index':i,'id':v.get('id'),'name':v.get('displayName',{}).get('text'),'address':v.get('formattedAddress')} for i,v in enumerate(found)],ensure_ascii=False,indent=2))
elif a.action=='prepare':
 found=d['search'][a.label][a.index];body={'googlePlaceID':found['id'],'day':a.day}
 if a.apple_query:body['appleQuery']=a.apple_query
 prepared=call('prepare',body);d['prepared'][a.label]=prepared
 print(json.dumps({'label':a.label,'hours':prepared['hours'],'appleCandidates':[{'index':i,**v} for i,v in enumerate(prepared['appleCandidates'])]},ensure_ascii=False,indent=2))
else:
 choices=json.loads(a.choices.read_text());output=a.output;output.mkdir(parents=True,exist_ok=True)
 from datetime import datetime
 from zoneinfo import ZoneInfo
 day=datetime.fromisoformat(a.day).replace(tzinfo=ZoneInfo('Asia/Jakarta')).timestamp()
 def chosen(label):
  pre=d['prepared'][label];pin=pre['appleCandidates'][choices['appleIndices'][label]]
  if pre['expiresAt']<time.time()+420:raise SystemExit('Insufficient context freshness for benchmark; prepare again')
  return {'prepared':pre,'apple':pin}
 origin=chosen(choices['origin']);stops=[];sanitized={'day':a.day,'confirmation':'Operator reviewed names, addresses and pin separation from independent searches. Not user quality approval.','stops':{},'timings':d['timings']}
 for label,values in choices['stops'].items():
  place=chosen(label);stop={'place':place,'durationMinutes':values['durationMinutes'],'exposure':values['exposure'],'afternoon':values.get('afternoon',False),'avoidRain':values.get('avoidRain',False)};stops.append((label,stop))
  sanitized['stops'][place['prepared']['googlePlaceID']]={'label':label,**values,'applePinDistanceMeters':place['apple']['distanceFromGoogleMeters']}
 for name,labels in [('three',choices['three']),('five',choices['five'])]:
  selection={'origin':origin,'stops':[v for k,v in stops if k in labels],'day':day,'departureMinute':660 if name=='three' else 540,'deadlineMinute':1140}
  path=output/f'selection-{name}.json';path.write_text(json.dumps(selection));path.chmod(0o600)
 sanitized['three']=choices['three'];sanitized['five']=choices['five'];sanitized['origin']=choices['origin']
 (ROOT/'artifacts/dynamic-context-simulator-2026-11-07/runtime-selection.json').write_text(json.dumps(sanitized,indent=2))
 print('Fresh runtime selections exported privately; audit metadata sanitized')
record.write_text(json.dumps(d));record.chmod(0o600)
