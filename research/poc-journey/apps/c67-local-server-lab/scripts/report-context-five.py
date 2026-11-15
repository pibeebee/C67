#!/usr/bin/env python3
"""Summarize immutable pilot observations; no provider calls."""
import json,statistics
from pathlib import Path
root=Path(__file__).resolve().parents[1];out=root/'artifacts/context-five-2026-11-07'
load=lambda p:json.loads(p.read_text())
r=load(out/'live-resolved/live-report.json');a=load(out/'live-resolved/independent-live-audit.json')
lines=['# Five-destination context results — 7 November 2026','','Actual user brief retained: park afternoon, museums flexible, total waiting <=30min. This is an autonomous five-stop extension; the user has not reviewed its itinerary.','',
'Final places: Museum Nasional90min, Museum Bank Indonesia60min, Museum Seni Rupa dan Keramik60min, Museum Sejarah Jakarta60min, Lapangan Banteng60min. Tomorrow8 November,09–19WIB, automobile, same hotel origin/return. Total dwell330min; no destination or duration removed.','',
'## Primary paired live comparison','','Same engine as the three-stop pilot, shared fresh context, exact departure ETA, per-plan cache only. N3 is the original subset but now departs09:00; do not directly equate it with the earlier11:00 run. N3cap24/N5cap64, three repetitions each. The following processing medians include failed attempts; they are not successful itinerary latencies when ready=0.','',
'| Stops | Strategy | Ready / attempts | Median attempt seconds | Actual ETA calls |',
'| --- | --- | ---: | ---: | --- |']
for g in a['methods']:
 lines.append(f"|{g['stops']}|{g['policy']}|{g['ready']}/{g['repetitions']}|{g['medianProcessingSeconds']:.2f}|{g['actualCells']}|")
lines+=['','No-candidate-within-search and incomplete-travel-data outcomes are retained. Neither proves the real trip globally infeasible. Some attempts encountered unavailable ETA evidence; unavailable co-occurrence alone does not establish the cause of every failed search.','',
'## Bounded diagnostics','',
'After primary failures, a declared exploratory diagnostic uses beamWidth1, geographically authored input order BI→Arts→History→National→Park and the same firstFeasible engine. It preserves the30min wait cap. If executed, a separate60min control is explicitly a counterfactual, not success for the actual user constraint. Google place IDs are pinned; Apple searches, five Google details and WeatherKit are fetched fresh. Timing is fresh-process with pinned Google IDs, not completely uncached Google text discovery.','']
for folder in ['diagnostic30','diagnostic60','cold-single']:
 p=out/folder/'live-report.json'
 if not p.exists():continue
 d=load(p);row=d['rows'][0];res=row['result']
 lines += [f"### {folder}",'',f"Status: `{res['status']}`; {len(res['visits'])} stops, {res['travelCalls']} ETA calls. Route processing{row['processingSeconds']:.2f}s; complete pipeline{d['completeCLISeconds']:.2f}s, discovery{d['discoverySeconds']:.2f}s, enrichment{d['enrichmentSeconds']:.2f}s. Wait cap{d.get('maximumWaitingMinutes',30)}min, actual wait{res['waitingSeconds']/60:.2f}min. Search parameters changed after observing primary results; no independent held-out superiority claim.",'']
 if res['visits']:
  from datetime import datetime
  from zoneinfo import ZoneInfo
  fmt=lambda t:datetime.fromtimestamp(t,ZoneInfo('Asia/Jakarta')).strftime('%H:%M')
  lines+=['| Visit ID | Start–end WIB |','| --- | --- |']
  lines += [f"|{v['placeID']}|{fmt(v['visit']['start'])}–{fmt(v['visit']['end'])}|" for v in res['visits']]
  lines += ['',f"Return{fmt(res['finish'])}; travel{res['travelSeconds']/60:.2f}min, waiting{res['waitingSeconds']/60:.2f}min, dwell{res['dwellSeconds']/60:.0f}min. Preferred-start penalty{res['penaltyByPriority']}.",'']
 trace=out/folder/'eta-trace.json'
 if trace.exists():
  rows=load(trace);failed=[x for x in rows if x.get('seconds') is None]
  lines += [f"Diagnostic trace: {len(rows)} observations, {len(failed)} unavailable. Sanitized unavailable pairs/notes: "+str(sorted(set((x['query']['fromID'],x['query']['toID'],x['note']) for x in failed))), '']
f=load(out/'fixture-audit.json')
lines+=['## Grid waiting finding', '', 'The successful60min counterfactual waits39.93min. Every individual wait is exactly rounding the observed arrival up to the next15-minute visit grid (5.62/12.72/8.08/6.82/6.70min). These are scheduling waits, not measured queues. This is a concrete candidate cause of excessive waiting. A finer/continuous grid would change departures and requires fresh ETA validation; it has not been tested live and is not asserted to satisfy30min. [Calculation](../artifacts/context-five-2026-11-07/grid-wait-analysis.json).', '', '## Independent five-stop fixtures','',
'24 new seeded fixtures,12 development/12 holdout, six families,120 possible orders with independently enumerated admissible slots, directed FIFO ETA and full waiting/dwell/session/return rules.180 actual policy outputs independently audited;4 corruption types rejected. Holdout has10 feasible and2 infeasible cases. These are authored stress controls, not representative Jakarta or human accuracy.','',
'| Full-context policy | ETA cap | Returned /10 feasible | Preference gaps among returned | Exact model-score match /10 |',
'| --- | ---: | ---: | ---: | ---: |']
for x in f['summary']:
 if x['split']=='holdout' and x['ablation']=='full':lines.append(f"|{x['policy']}|{x['budget']}|{x['ready']}|{x['priorityGap']}|{x['oracleScoreMatched']}|")
lines+=['',
'Even high-budget beam misses one feasible fixture and is not exact. Technical invariant tests do not establish search completeness, optimum, or user satisfaction. The three-stop high-budget score agreement does not generalize automatically to five stops.','',
'## Identity and source limitations','',
'Mandiri lookup returned parking/access-named candidates; Wayang lookup returned a same-named place in another district. Both were rejected before routing. Google History Museum search contained multiple nearby same-named pins; the selected canonical record has Taman FatahillahNo.1, matching the independent Apple museum. Area gate narrowed to100m for that museum. Failed searches remain in the ledger; no silent first-result selection or Google coordinates forwarded to Apple.','',
'Primary recovery pins stable Google IDs and fetches fresh details, including all five current schedules. Google History Museum hours09–15 conflict with a city publication describing weekend09–20; planner uses the narrower returned window. No last-entry/ticket availability or physical admission claim. Park/indoor scopes and waiting/access weather uncertainty remain as in the earlier pilot.','',
'Official sources inspected: [History museum](https://www.mitramuseumjakarta.id/sejarah), [city museum weekend policy](https://m.beritajakarta.id/read/144576/resmi-lima-museum-di-jakarta-buka-hingga-malam-setiap-akhir-pekan), [Mandiri identity](https://linktr.ee/MuseumMandiri). Source conflicts were not resolved by assuming a later closing time.','',
'## Conclusion', '', 'No five-stop itinerary meeting the actual30min waiting constraint was found in this campaign. That is a limitation of the tested bounded policies/data/grid, not proof that the real trip is impossible. A five-stop candidate was found only under the exploratory60min cap, actually waiting39.93min, with6ETA calls; it is not a passing result for the actual brief. More search calls alone did not resolve the primary failures. Next investigation should test15min versus finer/continuous starts under the unchanged30min hard cap, with fresh exact-departure ETA, and improve order/slot candidate coverage. No further live experiment is started here.', '', '## Evidence and reproduction','',
'- [Prospective protocol and amendments](CONTEXT_FIVE_PROTOCOL_2026-11-07.md).',
'- [Primary report](../artifacts/context-five-2026-11-07/live-resolved/live-report.json), [independent live audit](../artifacts/context-five-2026-11-07/live-resolved/independent-live-audit.json).',
'- [Independent fixture audit](../artifacts/context-five-2026-11-07/fixture-audit.json), [reference](../artifacts/context-five-2026-11-07/independent-reference.json).',
'- [Verification and provider ledger](../artifacts/context-five-2026-11-07/verification.json).','',
'Analysis of saved output needs no API calls. Use `python3 scripts/context-pilot-fixtures.py audit artifacts/context-five-2026-11-07` and `python3 scripts/audit-context-pilot-live.py artifacts/context-five-2026-11-07/live-resolved`. New live reproduction incurs provider calls and should use new directories/future dates. No production integration, homelab, simulator/iPhone installation, commit or publication.','']
(root/'docs/CONTEXT_FIVE_RESULTS_2026-11-07.md').write_text('\n'.join(lines))
print('Five-stop report generated from saved observations.')
