#!/usr/bin/env python3
"""Independent arithmetic/session audit of exported live results, not field ETA validation."""
import argparse,copy,json,math,statistics
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
TZ=ZoneInfo('Asia/Jakarta');DWELL={'museum':90,'gallery':60,'park':60}
def check(report,row):
 r=row['result'];visits=r['visits'];durations=report.get('stopDurations') or DWELL
 count=row.get('stopCount') or len(durations)
 expected=DWELL if count==3 else durations
 assert r['travelCalls']<=row['budget'],'budget'
 assert math.isfinite(row['processingSeconds']) and row['processingSeconds']>=0,'processing timer'
 assert math.isfinite(row['etaWallSeconds']) and 0<=row['etaWallSeconds']<=row['processingSeconds']+0.001,'ETA timer'
 if not visits:
  assert not r['legs'] and not r.get('finish'),'non-ready consistency'
  assert r['status'] in ['needs_context','no_candidate_within_search','incomplete_travel_data'],'non-ready status'
  return {'ready':False,'status':r['status'],'stops':count}
 assert r['status'] in ['candidate','candidate_with_unknown_preferences'],'ready status'
 assert len(visits)==count and {v['placeID'] for v in visits}==set(expected),'coverage'
 assert len(r['legs'])==count+1 and r['travelCalls']<=row['budget'],'legs/budget'
 base=datetime.fromisoformat(report['day']).replace(tzinfo=TZ).timestamp();departure=base+report.get('departureMinute',660)*60;deadline=base+report.get('deadlineMinute',1140)*60;cursor=departure;last='origin';wait=travel=dwell=0
 records={x['internalID']:x for x in report['identities']};pref=0
 for i,v in enumerate(visits):
  key=v['placeID'];o=v['visit'];leg=r['legs'][i];ev=leg['evidence'];duration=expected[key]*60
  assert leg['from']==last and leg['to']==key and abs(leg['departure']-cursor)<1e-4,'continuity'
  assert abs(ev['departure']-cursor)<1e-4 and ev['source'].startswith('Apple Maps Server API'),'provider departure'
  assert ev['seconds']>=0 and abs(leg['arrival']-cursor-ev['seconds'])<1e-4,'ETA arithmetic'
  assert abs(v['arrival']-leg['arrival'])<1e-4 and o['start']>=v['arrival'],'arrival'
  assert abs(o['end']-o['start']-duration)<1e-4,'dwell'
  assert o['start']>=departure and o['end']<=deadline,'bounds'
  minute=(o['start']-base)/60;endminute=(o['end']-base)/60
  intervals=[]
  for text in records[key]['operatingWindowsWIB']:
   a,b=text.split('–');a=sum(int(v)*k for v,k in zip(a.split(':'),[60,1]));b=sum(int(v)*k for v,k in zip(b.split(':'),[60,1]))
   if b<=a:b+=1440 # returned day-clipped00–00 means through next midnight
   intervals.append((a,b))
  assert any(minute>=a and endminute<=b for a,b in intervals),'returned hours'
  # Additional independent source check, conservative common Sunday range.
  official={'museum':[(480,1200)],'gallery':[(480,720),(780,930)],'park':[(360,1200)]}
  if key in official:assert any(minute>=a and endminute<=b for a,b in official[key]),'sampled official bounds'
  if key in ['history','arts']:assert 540<=minute and endminute<=1200,'published city museum envelope'
  if key=='park' and not row['caseID'].endswith('elapsed'):pref=max(0,900-minute,minute-960)
  wait+=o['start']-v['arrival'];travel+=ev['seconds'];dwell+=duration;last=key;cursor=o['end']
 back=r['legs'][-1];assert back['from']==last and back['to']=='origin' and abs(back['departure']-cursor)<1e-4,'return'
 assert abs(back['evidence']['departure']-cursor)<1e-4 and abs(back['arrival']-cursor-back['evidence']['seconds'])<1e-4,'return arithmetic'
 travel+=back['evidence']['seconds'];finish=back['arrival']
 assert finish<=deadline and abs(r['finish']-finish)<1e-4,'deadline'
 assert wait<=report.get('maximumWaitingMinutes',30)*60+1e-4 and abs(wait-r['waitingSeconds'])<1e-4,'waiting'
 assert abs(travel-r['travelSeconds'])<1e-4 and abs(dwell-r['dwellSeconds'])<1e-4,'totals'
 assert abs(r['elapsedSeconds']-finish+departure)<1e-4,'elapsed'
 assert abs(r['penaltyByPriority'][0]-pref)<1e-4,'preferred start penalty'
 return {'ready':True,'stops':count,'satisfiesActual30MinuteWait':wait<=1800+1e-4,'waitingMinutes':wait/60,'travelMinutes':travel/60,'elapsedMinutes':r['elapsedSeconds']/60,'finishWIB':datetime.fromtimestamp(finish,TZ).strftime('%H:%M:%S')}
def audit(directory):
 report=json.loads((directory/'live-report.json').read_text())
 keys=[(r['caseID'],r['policy']) for r in report['rows']]
 assert keys and len(set(keys))==len(keys),'empty or duplicate live observations'
 assert sum(r['result']['travelCalls'] for r in report['rows'])==report['appleETACells'],'reported ETA cells'
 assert sum(r['processingSeconds'] for r in report['rows'])<=report['completeCLISeconds']+0.001,'complete pipeline timer'
 facts=[check(report,r) for r in report['rows']];controls=[]
 for name in ['dwell','waiting','departure','return','preference','missing_stop']:
  candidates=[r for r in report['rows'] if r['result']['visits']]
  if not candidates:break
  bad=copy.deepcopy(max(candidates,key=lambda r:len(r['result']['visits'])))
  if name=='dwell':bad['result']['visits'][0]['visit']['end']+=60
  if name=='waiting':bad['result']['waitingSeconds']+=60
  if name=='departure':bad['result']['legs'][0]['evidence']['departure']+=60
  if name=='return':bad['result']['finish']+=60
  if name=='preference':bad['result']['penaltyByPriority'][0]+=1
  if name=='missing_stop':bad['result']['visits'].pop()
  try:check(report,bad)
  except AssertionError:controls.append({'corruption':name,'rejected':True})
  else:raise AssertionError('Corruption accepted: '+name)
 groups=[]
 for count,method in sorted(set((r.get('stopCount') or 3,r['policy']) for r in report['rows'] if 'user-' in r['caseID'])):
  rows=[r for r in report['rows'] if r['policy']==method and (r.get('stopCount') or 3)==count and 'user-' in r['caseID']]
  ready=[r for r in rows if r['result']['visits']]
  groups.append({'stops':count,'policy':method,'repetitions':len(rows),'ready':len(ready),'medianProcessingSeconds':statistics.median(r['processingSeconds'] for r in rows),'medianETAWallSeconds':statistics.median(r['etaWallSeconds'] for r in rows),'actualCells':[r['result']['travelCalls'] for r in rows],'waitingMinutes':[r['result']['waitingSeconds']/60 for r in ready]})
 out={'audited':len(facts),'passed':len(facts),'ready':sum(x['ready'] for x in facts),'nonReady':sum(not x['ready'] for x in facts),'negativeControls':controls,'methods':groups,'facts':facts,'scope':'Independent arithmetic and common published-hour audit, not independently observed ETA, admission or actual venue conditions. Rain score not independently audited: forecast response was not archived.'}
 (directory/'independent-live-audit.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args();audit(a.directory)
