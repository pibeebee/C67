#!/usr/bin/env python3
"""Summarize one frozen live campaign; retain failed and interrupted observations separately."""
import argparse,csv,json,statistics
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args()
rows=json.loads((a.directory/'observations.json').read_text())
audit=json.loads((a.directory/'audit.json').read_text())
valid={(x['case'],x['variant']):x['passed'] for x in audit.get('checks',[])}
# Older audits store only failed checks; reconstruct success from their absence.
failed={(x['case'],x['variant']) for x in audit['failed']}
def good(r):return (r['caseID'],r['variant']) not in failed and (r.get('outcome') or {}).get('outcome')=='ready'
def median(values):return statistics.median(values) if values else None
families={};flat=[]
for family in ['N1','N3','N4','N5','REV5','MIX5','TIGHT5','SIX','UNKNOWN']:
 families[family]={}
 for variant in ['A','B','C']:
  subset=[r for r in rows if r['family']==family and r['variant']==variant]
  successes=[r for r in subset if good(r)]
  item={'attempted':len(subset),'readyValid':len(successes),
    'medianReadySeconds':median([r['clientSeconds'] for r in successes]),
    'medianObservedSeconds':median([r['clientSeconds'] for r in subset]),
    'outcomes':[(r.get('outcome') or {}).get('outcome','failed') for r in subset],
    'medianETACalls':median([(r.get('outcome')or{}).get('providerMetrics',{}).get('calls',0) for r in successes]),
    'medianETACells':median([(r.get('outcome')or{}).get('providerMetrics',{}).get('cells',0) for r in successes]),
    'stageMedians':{stage:median([m['seconds'] for r in successes for m in r['outcome']['plan']['metrics'] if m['stage']==stage])
      for stage in ['preferences','mapkit_search','weather_groups','mapkit_eta']}}
  families[family][variant]=item
for r in rows:
 o=r.get('outcome')or{};plan=o.get('plan')or{};eta=o.get('providerMetrics',{})
 weather=plan.get('weather',[])
 flat.append({'case':r['caseID'],'family':r['family'],'variant':r['variant'],'condition':r['condition'],
  'client_seconds':r['clientSeconds'],'outcome':o.get('outcome','failed'),'error':r.get('error',''),
  'ready_valid':good(r),'eta_calls':eta.get('calls'),'eta_cells':eta.get('cells'),'eta_failures':eta.get('failures'),
  'weather_groups':len(weather),'weather_available':sum(w['status']=='available' and w['provider']=='weatherkit' for w in weather),
  'stop_count':len(plan.get('stops',[])),'finish':plan.get('finish'),'deadline':plan.get('request',{}).get('deadline'),
  'travel_minutes':plan.get('travelMinutes'),'waiting_minutes':plan.get('waitingMinutes'),
  'order':'>'.join(s['id'] for s in plan.get('stops',[])),'evidence':o.get('evidence'),'thermal':r.get('thermal')})
summary={'observations':len(rows),'families':families,'paired':audit.get('pairedLive'),
 'scope':'Simulator controlled shared real pins, live ETA/weather; not full discovery E2E or physical iPhone latency',
 'audit':{'passed':audit['passed'],'failed':audit['failed'],'speedConclusion':audit['speedConclusion']},
 'allETACalls':sum((r.get('outcome')or{}).get('providerMetrics',{}).get('calls',0) for r in rows),
 'allETACells':sum((r.get('outcome')or{}).get('providerMetrics',{}).get('cells',0) for r in rows),
 'allETAFailures':sum((r.get('outcome')or{}).get('providerMetrics',{}).get('failures',0) for r in rows)}
(a.directory/'benchmark-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
with (a.directory/'benchmark.csv').open('w') as f:
 w=csv.DictWriter(f,fieldnames=flat[0].keys());w.writeheader();w.writerows(flat)
old={'N1':2.508331,'N3':28.3264385,'N4':48.533102375,'N5':65.391324042}
comparison=[]
for family in old:
 comparison.append({'family':family,'previous_iphone_e2e_seconds':old[family],
  **{v+'_simulator_shared_pins_seconds':families[family][v]['medianReadySeconds'] for v in ['A','B','C']},
  'priorities':'compare paired simulator A/B/C; old iPhone E2E is historical context'})
with (a.directory/'historical-comparison.csv').open('w') as f:
 w=csv.DictWriter(f,fieldnames=comparison[0].keys());w.writeheader();w.writerows(comparison)
print(json.dumps({'observations':summary['observations'],'ETA_calls':summary['allETACalls'],'ETA_cells':summary['allETACells'],'paired':summary['paired']},indent=2))
