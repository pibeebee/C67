#!/usr/bin/env python3
"""Independent arithmetic/identity audit of the Jakarta live probe artifacts."""
import json, math, sys
from datetime import datetime
from pathlib import Path

out=Path(sys.argv[1])
def read(name): return json.loads((out/name).read_text())
def stamp(value): return datetime.fromisoformat(value.replace('Z','+00:00')).timestamp()
errors=[]
def check(ok, label):
    if not ok: errors.append(label)
initial=read('initial-report.json'); remaining=read('replan-report.json')
end=read('end-only-report.json'); restored=read('restored-session.json'); completed=read('completed-session.json')
summary=read('summary.json')
original_end=initial['draft']['origin']['id']
for name,report in [('initial',initial),('replan',remaining),('end-only',end)]:
    draft=report['draft']; c=report.get('fastest')
    check(c is not None,name+' missing selected candidate')
    if c is None: continue
    check(c['complete'] and not c['conflicts'],name+' incomplete/conflicting')
    stops={s['point']['id']:s for s in draft['stops']}
    check(len(c['order'])==len(stops) and set(c['order'])==set(stops),name+' stop identities')
    target_end=draft['origin'] if draft['returnsToOrigin'] else draft['end']
    check(target_end['id']==original_end,name+' original endpoint')
    check(len(c['legs'])==len(stops)+1,name+' leg count')
    cursor=stamp(draft['departure']); travel=waiting=dwell=0
    from_id=draft['origin']['id']
    for i,leg in enumerate(c['legs']):
        last=i==len(c['order'])
        target=target_end['id'] if last else c['order'][i]
        check((leg['from']['id'],leg['to']['id'])==(from_id,target),name+' leg identity')
        eta=leg.get('chosen') or {}; seconds=eta.get('seconds')
        check(eta.get('mode')=='automobile' and isinstance(seconds,(int,float)) and math.isfinite(seconds) and seconds>=0,name+' ETA/mode')
        if seconds is None:continue
        arrival=cursor+seconds; visit=arrival
        stop=stops.get(target) if not last else None
        stay=(stop.get('dwellOverride',draft['defaultDwell']) if stop and stop.get('role','visit')=='visit' else 0)*60
        window=(stop or {}).get('opening') or {}
        midnight=datetime.fromisoformat(draft['departure'].replace('Z','+00:00')).timestamp()
        # These public-place fixtures have unknown windows; if a future fixture adds
        # one, require an explicit auditor update instead of silently ignoring it.
        check(not window,name+' auditor does not cover new opening-window fixtures')
        leave=visit+stay
        for key,expected in [('departure',cursor),('arrival',arrival),('visit',visit),('leave',leave)]:
            check(abs(stamp(leg[key])-expected)<1.01,name+' arithmetic '+key)
        check(leave<=stamp(draft['finishBy'])+1,name+' deadline')
        travel+=seconds; waiting+=visit-arrival; dwell+=stay; cursor=leave; from_id=target
    check(abs(stamp(c['finish'])-cursor)<1.01,name+' finish')
    check(abs(c['travelMinutes']*60-travel)<1.01,name+' travel sum')
    check(abs(c['waitingMinutes']*60-waiting)<1.01,name+' wait sum')
    check(abs(c['dwellMinutes']*60-dwell)<1.01,name+' dwell sum')
    check(all(f.get('provider')=='open_meteo' for f in report['forecasts']),name+' weather source')
state=restored['activeTrip']; final=completed['activeTrip']
first,second=initial['fastest']['legs'][:2]
visits={v['stopID']:v for v in state['visits']}; done={v['stopID']:v for v in final['visits']}
for leg in [first,second]:
    v=visits[leg['to']['id']]
    check(v['arrivedAt']==leg['arrival'] and v['startedAt']==leg['visit'],'scripted arrival/start preserved')
    check(done[v['stopID']]['arrivedAt']==v['arrivedAt'] and done[v['stopID']]['startedAt']==v['startedAt'],'completed actual prefix preserved')
check(visits[first['to']['id']]['departedAt']==first['leave'],'first actual departure preserved')
check(abs(stamp(visits[second['to']['id']]['plannedLeaveAt'])-stamp(second['leave'])-1800)<1.01,'extension exactly30minutes')
pending={v['stopID'] for v in state['visits'] if v['status']=='pending'}
check({s['point']['id'] for s in remaining['draft']['stops']}==pending,'remaining projection pending identities')
check(remaining['draft']['origin']['id']==second['to']['id'],'remaining anchor')
check(remaining['draft']['finishBy']==initial['draft']['finishBy'],'absolute deadline preserved')
check(all(done[i]['status']=='skipped' for i in pending),'explicit skips preserved')
check(final.get('finishedAt')==end['fastest']['finish'],'endpoint finish restored')
check(completed['schemaVersion']==2,'active schema')
events=[]
for path in (out/'logs').glob('*.jsonl'):
    events.extend(json.loads(line) for line in path.read_text().splitlines())
check(not any(r['event'].startswith('weather.') and r['fields'].get('provider')=='weatherkit' for r in events),'unexpected WeatherKit call')
for label,op in [('initial','jakarta-live-initial'),('replan','jakarta-live-replan'),('end-only','jakarta-live-end-only')]:
    found=[e for e in events if e.get('operationID')==op and e['event']=='eta.result' and e['fields'].get('source')=='provider']
    report={'initial':initial,'replan':remaining,'end-only':end}[label]
    check(len(found)==report['requests'],label+' request counter versus trace')
result={'errors':errors,'passed':not errors,'reportsAudited':3,'events':len(events),
        'basis':'Python arithmetic/ID audit of production live outputs; no app validator reused',
        'limits':'Unknown fixture opening windows; no traffic ground truth or actual attendance validation'}
(out/'audit.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
raise SystemExit(bool(errors))
