#!/usr/bin/env python3
"""Validate prerequisites and freeze live bounds. Does not run providers or launch a phone."""
import argparse,datetime,hashlib,json,os
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--replay',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--confirm-provider-allowance',action='store_true');p.add_argument('--bounded-unknown-quota',action='store_true',help='Use the experiment cap, record account remainder as unknown, and stop on 429');a=p.parse_args()
audit=json.loads((a.replay/'audit.json').read_text())
if audit['passed']!=51 or audit['parityFailures']:raise SystemExit('Full replay parity gate not satisfied')
names=['APPLE_TEAM_ID','MAPS_KEY_ID','MAPS_KEY_PATH','WEATHER_KEY_ID','WEATHER_KEY_PATH','WEATHER_SERVICE_ID']
missing=[n for n in names if not os.environ.get(n)]
q=json.loads((root/'Sources/PlannerEngine/Resources/quality.json').read_text())
t=json.loads((root/'Sources/PlannerEngine/Resources/timing.json').read_text())
now=datetime.datetime.now(datetime.timezone.utc)
def epoch(v):return datetime.datetime.fromisoformat(v.replace('Z','+00:00'))
stale=[s['id'] for s in q['sources']+t['sources'] if not -300<=(now-epoch(s['checkedAt'])).total_seconds()<7*86400]
rows=json.loads((a.replay/'observations.json').read_text())
peak={}
for r in rows:
 if r.get('outcome'):
  key=(r['family'],r['variant']);m=r['outcome']['providerMetrics'];peak[key]=(m['calls'],m['cells'])
# All fresh+warm observations (five per variant/family), plus one edge each. Native search/weather
# overhead is conservatively reserved at 20 calls/job; retry/failure bounds are separate guards.
calls=cells=0
for family in ['N1','N3','N4','N5']:
 for variant in ['A','B','C']:
  c,n=peak[(family,variant)];calls+=(c+20)*5;cells+=n*5
for family in ['REV5','MIX5','TIGHT5','SIX','UNKNOWN']:
 for variant in ['A','B','C']:
  c,n=peak[(family,variant)];calls+=c+20;cells+=n
blocked=[]
if missing:blocked.append('missing_credentials')
if stale:blocked.append('stale_source_facts_require_actual_reverification')
if not a.confirm_provider_allowance and not a.bounded_unknown_quota:blocked.append('remaining_provider_allowance_not_confirmed')
full_calls,full_cells=calls,cells
subset='full'
if calls>3000 or cells>6000:
 subset='fresh_edges'
 for family in ['N1','N3','N4','N5']:
  for variant in ['A','B','C']:
   c,n=peak[(family,variant)];calls-=(c+20)*2;cells-=n*2
if calls>3000 or cells>6000:blocked.append('fresh_edges_exceeds_budget_reduce_manifest_before_launch')
manifest={'schemaVersion':1,'createdAt':now.isoformat(),'status':'blocked' if blocked else 'prepared',
 'mode':'rest','clock':'actual','observationsPlanned':75 if subset=='full' else 51,'subset':subset,'fullCampaignEstimatedCalls':full_calls,'fullCampaignEstimatedCells':full_cells,'validUntil':(now+datetime.timedelta(minutes=15)).isoformat(),'baselinePrepAdditionalIfNeeded':3,
 'accountQuotaRemaining':'confirmed externally' if a.confirm_provider_allowance else 'unknown; bounded experiment and stop on quota error','providerCallsCap':3000,'etaCellsCap':6000,'estimatedCallsWithPerJobOverhead':calls,'estimatedCells':cells,
 'providerConcurrency':1,'etaPacingSeconds':1.2,'workerConcurrency':1,'missingConfigurationNames':missing,'staleSources':stale,
 'blockedReasons':blocked,'liveGateValue':'frozen-campaign-v1' if not blocked else None,
 'requirements':['Run one minimum provider probe; preserve its failures','Use identical currently verified catalogue on A/B/C',
 'Reserve edges, fresh N3/N4/N5 before N1 and warm','Stop after two consecutive provider-unavailable jobs',
 'Any resume uses a fresh manifest; do not discard failed observations']}
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({k:manifest[k] for k in ['status','blockedReasons','estimatedCallsWithPerJobOverhead','estimatedCells']}))
raise SystemExit(2 if blocked else 0)
