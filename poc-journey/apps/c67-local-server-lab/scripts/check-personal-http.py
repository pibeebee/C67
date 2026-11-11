#!/usr/bin/env python3
"""Readiness/error contracts and a real distant-identity rejection. No LLM generations."""
import importlib.util,json,time,urllib.request,urllib.error,uuid
from pathlib import Path
LAB=Path(__file__).resolve().parents[1];OUT=LAB/'artifacts/personal-recommendation-2026-11-08'
spec=importlib.util.spec_from_file_location('smoke',LAB/'scripts/recommendation-smoke.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
results=[]
def expect(name,status,body,expected):
    assert status==expected,(name,status,body)
    results.append({'name':name,'http':status,'reason':body.get('reason')})
cfg=json.loads((LAB/'.local/dynamic-context-simulator/client-config.json').read_text())
try:
    urllib.request.urlopen(cfg['baseURL']+'/v1/lab/recommendation/capabilities',timeout=3)
    raise AssertionError('Anonymous request accepted')
except urllib.error.HTTPError as e:expect('anonymous',e.code,{},401)
before=m.api('recommendation/counters')[1]
expect('invalid-body',*m.api('recommendation/start',{}),400)
expect('forged-session',*m.api('recommendation/complete',{'id':str(uuid.uuid4()),'profileRevision':1,'scores':[],
    'embeddingStatus':'not_run','embeddingSeconds':0}),400)
latest=json.loads((OUT/'personal-plan-latest.json').read_text())
request=latest['input'];original=request['recommendationID'];request['recommendationID']=str(uuid.uuid4())
context_before=m.api('context/counters')[1]
expect('missing-llm-proof',*m.api('recommendation/plan',request),400)
context_after=m.api('context/counters')[1]
assert context_before==context_after,'Unauthorized plan consumed provider budget'
assert before==m.api('recommendation/counters')[1],'Negative control generated LLM/provider work'

# Locate the exact museum whose cross-provider mismatch was observed, without hard-coding it into the engine.
status,places=m.api('context/search',{'query':'Museum Sejarah Nasional Monas Jakarta'})
assert status==200
museum=next((p for p in places if p.get('displayName',{}).get('text')=='Museum Sejarah Nasional'),None)
if museum:
    day=next(r['context']['day'] for r in json.loads((OUT/'simulator-recommendations.json').read_text()) if r.get('recommendationID')==original)
    status,prepared=m.api('context/prepare',{'googlePlaceID':museum['id'],'day':day})
    assert status==200,(status,prepared)
    distant=next((c for c in prepared['appleCandidates'] if c['distanceFromGoogleMeters']>500),None)
    if distant:
        plan=json.loads(json.dumps(latest['input']['plan']))
        plan['stops']=[{'endpoint':{'preparedID':prepared['id'],'appleCandidateID':distant['id']},
            'durationMinutes':60,'exposure':'unknown','avoidRain':False}]
        counters_before=m.api('context/counters')[1]
        status,body=m.api('context/plan',plan)
        expect('distant-identity',status,body,400)
        assert '500' in body.get('reason','')
        counters_after=m.api('context/counters')[1]
        assert counters_before==counters_after,'Distant identity reached routing provider'
        results[-1].update(googleName=prepared['name'],appleName=distant['name'],separationMeters=distant['distanceFromGoogleMeters'],providerCallsDuringRejection=0)
    else:results.append({'name':'distant-identity','reproduced':False,'note':'Current Apple search did not return the previously observed distant candidate; pure policy boundary tests still apply'})
else:results.append({'name':'distant-identity','reproduced':False,'note':'Observed museum not returned by current search'})
# A nearby different business must also fail, even below the distance threshold.
status,places=m.api('context/search',{'query':'TOMORO COFFEE STASIUN GAMBIR'})
assert status==200
coffee=next((p for p in places if 'TOMORO' in p.get('displayName',{}).get('text','').upper()),None)
if coffee:
    day=next(r['context']['day'] for r in json.loads((OUT/'simulator-recommendations.json').read_text()) if r.get('recommendationID')==original)
    status,prepared=m.api('context/prepare',{'googlePlaceID':coffee['id'],'day':day})
    assert status==200
    wrong=next((c for c in prepared['appleCandidates'] if c['distanceFromGoogleMeters']<=500 and c.get('nameSupported') is False),None)
    if wrong:
        plan=json.loads(json.dumps(latest['input']['plan']))
        plan['stops']=[{'endpoint':{'preparedID':prepared['id'],'appleCandidateID':wrong['id']},'durationMinutes':60,'exposure':'unknown','avoidRain':False}]
        before=m.api('context/counters')[1]
        expect('nearby-different-business',*m.api('context/plan',plan),400)
        assert m.api('context/counters')[1]==before,'Wrong venue reached routing provider'
        results[-1].update(googleName=prepared['name'],appleName=wrong['name'],separationMeters=wrong['distanceFromGoogleMeters'],providerCallsDuringRejection=0)
    else:results.append({'name':'nearby-different-business','reproduced':False,'note':'Previously observed wrong candidate not returned now; pure policy tests cover it'})
else:results.append({'name':'nearby-different-business','reproduced':False})
(OUT/'http-negative-controls.json').write_text(json.dumps({'results':results,'checkedAt':time.time()},indent=2))
print(json.dumps(results,indent=2))
