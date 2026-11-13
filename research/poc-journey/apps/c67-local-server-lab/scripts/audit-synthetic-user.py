#!/usr/bin/env python3
"""Check frozen inputs, real inference and technical outputs; never infer human satisfaction."""
import hashlib,importlib.util,json,re,copy
from pathlib import Path
LAB=Path(__file__).resolve().parents[1];OUT=LAB/'artifacts/synthetic-user-2026-11-08'
brief_path=OUT/'frozen-briefs.json';assert hashlib.sha256(brief_path.read_bytes()).hexdigest()==(OUT/'frozen-briefs.sha256').read_text().split()[0]
briefs={p['id']:p for p in json.loads(brief_path.read_text())['personas']}
old=json.loads((OUT/'engine-before-sha256.json').read_text())
assert all(hashlib.sha256((LAB/p).read_bytes()).hexdigest()==h for p,h in old.items()),'Engine/UI behavior changed during evaluation'
spec=importlib.util.spec_from_file_location('independent',LAB/'scripts/audit-personal-recommendation.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
rows=json.loads((OUT/'recommendations.json').read_text());checks=[]
for row in rows:
 case=row['campaignLabel'].split('-')[2];b=briefs[case];c=row['context']
 assert c=={'area':b['area'],'day':'2026-11-10','departureMinute':b['departureMinute'],'deadlineMinute':b['deadlineMinute']},'Frozen context drift'
 assert set(row['interests'])==set(b['interests']),'Frozen interest drift'
 check=mod.recommendation(row)
 available=set().union(*(set(p['categories'])for p in row.get('allCandidateFacts')or[])) if row.get('allCandidateFacts')else set()
 shown=set().union(*(set(p['categories'])for p in row['candidates']))if row['candidates']else set()
 check.update(persona=case,campaign=row['campaignLabel'],requestedMissingBeforeLLM=sorted(set(b['interests'])-available),requestedMissingAfterLLM=sorted(set(b['interests'])-shown),clientSeconds=row['clientSeconds'],model=(row.get('metrics')or{}).get('llmModel'))
 checks.append(check)
def scope_check(row,case):
    if case=='U3':
        # Frozen mall origin; a tenant containing the mall name is a different entity.
        def tokens(v):return set(re.findall(r'[a-z0-9]+',v.lower()))-{'jakarta'}
        origin=next(i for i in row['identities'] if i['id']==row['originPlaceID'])
        assert tokens(origin['appleName'])==tokens(briefs[case]['originQuery']),'Mall origin replaced by a tenant'
plans={}
for path in sorted(OUT.glob('U?-plan.json')):
 case=path.stem.split('-')[0];row=json.loads(path.read_text());scope_check(row,case);plans[case]=mod.itinerary(row,rows)
 assert row['input']['plan']['maximumWaitingMinutes']==briefs[case]['waitMinutes'],'Waiting preference drift'
 for stop in row['input']['plan']['stops']:
  assert stop['durationMinutes']in set(briefs[case]['activityDurations'].values()),'Dwell drift'
bad_path=OUT/'U3-plan-rejected-tenant-origin.json'
if bad_path.exists():
    try:scope_check(json.loads(bad_path.read_text()),'U3')
    except AssertionError:pass
    else:raise AssertionError('Tenant origin negative control was accepted')
for case in briefs:
 assert any(c['persona']==case for c in checks),'Persona not executed'
result={'frozenBriefSHA256':hashlib.sha256(brief_path.read_bytes()).hexdigest(),'engineBehaviorSourceFilesUnchanged':len(old),'recommendationAttempts':checks,'plans':plans,'tenantOriginNegativeControlRejected':bad_path.exists(),'humanAccuracy':'not_measured','syntheticUserVerdictsSource':'U1/U2/U3-judgment.json; subjective authored evaluation separate from this rule audit'}
(OUT/'independent-audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
