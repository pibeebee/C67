#!/usr/bin/env python3
"""Independent JSON-level recommendation/itinerary audit, with deliberate corruptions.

Does not import Swift ranking, validators or the existing context oracle.
"""
import argparse,copy,json,math,statistics,re,unicodedata
from pathlib import Path

LAB=Path(__file__).resolve().parents[1]
OUT=LAB/'artifacts/personal-recommendation-2026-11-08'
def check(condition,message):
    if not condition:raise AssertionError(message)
def near(a,b):return abs(a-b)<.005
def recommendation(row):
    check(math.isfinite(row['clientSeconds']) and row['clientSeconds']>=0,'invalid client time')
    if not row['success']:
        check(bool(row.get('error')),'failure without error')
        return {'success':False,'error':row['error']}
    facts={r['id']:r for r in row.get('allCandidateFacts') or []}
    check(facts,'missing acquisition audit facts')
    judgments=row['judgments'];jids=[j['id'] for j in judgments]
    check(len(set(jids))==len(jids) and set(jids)==set(facts),'missing/repeated/foreign LLM ID')
    interests=set(row['interests'])
    for j in judgments:
        c=facts[j['id']];codes=j['reasonCodes'];evidence=j['evidenceIDs']
        check(codes and len(codes)==len(set(codes)),'empty/repeated reasons')
        check(evidence and set(evidence)<=set(c['evidenceIDs']),'foreign evidence')
        for code in codes:
            check(code in ['interest_match','hours_overlap','hours_unknown'],'unknown claim')
            if code=='interest_match':check(bool(interests & set(c['categories'])),'unsupported interest claim')
            if code=='hours_overlap':check(c['hoursState']=='available','false open-hours claim')
            if code=='hours_unknown':check(c['hoursState'] not in ['available','closed','outside_window'],'false unknown-hours claim')
            check(j['id']+(':category' if code=='interest_match' else ':hours') in evidence,'claim lacks matching evidence')
    selected=row['candidates'];ids=[c['id'] for c in selected]
    check(0<len(ids)<=6 and len(set(ids))==len(ids) and set(ids)<=set(facts),'invalid displayed candidates')
    available=set().union(*(set(c['categories'])&interests for c in facts.values()))
    represented=set().union(*(set(c['categories'])&interests for c in selected))
    if len(available)<=6:check(available<=represented,'available interest lost from diverse list')
    m=row['metrics']
    check(m['costUSD']==0,'nonzero LLM cost')
    check(m['embeddingStatus'].startswith('actual_e5_614241f622f53c4eeff9890bdc4f31cfecc418b3'),'actual pinned device E5 not confirmed')
    check(m['llmSeconds']>0 and bool(m['llmModel']),'missing real LLM measurement')
    check(row.get('displayReadySeconds') is not None and row['displayReadySeconds']<20,'display deadline missed/unmeasured')
    return {'success':True,'count':len(ids),'represented':sorted(represented),'readySeconds':row['displayReadySeconds']}

def itinerary(row,recommendations):
    request=row['input'];plan=request['plan'];result=row['response'];out=result['result']['itinerary']
    check(result['requiredPlaceIDs']==request['requiredPlaceIDs'],'required selection changed')
    mapping={k.upper():v for k,v in row['preparedPlaceIDs'].items()}
    requested={mapping[s['endpoint']['preparedID'].upper()]:s for s in plan['stops']}
    required=set(request['requiredPlaceIDs']);check(required<=set(requested),'foreign mandatory ID')
    identities=row.get('identities') or []
    check(set(requested)<=set(i['id'] for i in identities),'missing identity audit')
    check(all(math.isfinite(i['separationMeters']) and 0<=i['separationMeters']<=500 for i in identities),'distant/unverified identity')
    check(all(i.get('nameSupported') is True for i in identities),'unsupported venue name')
    for i in identities:
        if 'tomoro' in i['googleName'].lower():check('tomoro' in i['appleName'].lower(),'different coffee brand at same station')
        aliases={'national':'nasional','history':'sejarah','monument':'monumen'}
        def terms(text):
            text=unicodedata.normalize('NFKD',text.lower())
            return {aliases.get(w,w) for w in re.findall(r'[a-z0-9]+',text)}
        generic={'hotel','museum','coffee','kopi','cafe','kafe','taman','park','station','stasiun','jakarta','indonesia','of','the','central','pusat','barat','timur','utara','selatan','jalan','jl','no','rt','rw'}
        shared=(terms(i['googleName']) & terms(i['appleName']))-generic-terms(i['googleAddress'])
        check(bool(shared),'no distinctive shared venue name beyond address/generic terms')
    by_proof={r['recommendationID'].upper():r for r in recommendations if r.get('recommendationID')}
    proof_id=request['recommendationID'].upper()
    issued=set();seen=set();context=None
    while proof_id:
        check(proof_id not in seen,'cyclic recommendation continuation')
        seen.add(proof_id)
        proof=by_proof.get(proof_id)
        check(proof and proof['success'],'no successful LLM recommendation proof')
        if context is None:context=proof['context']
        check(proof['context']==context,'continuation switched trip context')
        page={c['id'] for c in proof['candidates']}
        check(issued.isdisjoint(page),'continuation repeated a previously displayed place')
        issued.update(page)
        proof_id=(proof.get('parentRecommendationID') or '').upper()
    check(set(requested)<=issued,'selection outside issued shortlist')
    visits=out['visits'];ids=[v['placeID'] for v in visits]
    check(len(set(ids))==len(ids) and set(ids)<=set(requested),'foreign/repeated visit')
    omitted=result['omitted'];check(set(o['id'] for o in omitted)==set(requested)-set(ids),'omissions not disclosed')
    check(all(o['required']==(o['id'] in required) for o in omitted),'wrong omission requirement')
    if visits:check(required<=set(ids),'mandatory visit silently dropped')
    else:
        check(not out['status'].startswith('candidate'),'empty result presented as candidate')
        return {'candidate':False,'status':out['status']}
    legs=out['legs'];check(len(legs)==len(visits)+1,'missing return leg')
    origin=('origin-'+plan['origin']['preparedID']).upper();last=origin;cursor=plan['departure'];waiting=travel=dwell=0
    for index,visit in enumerate(visits):
        leg=legs[index];start=visit['visit']['start'];end=visit['visit']['end'];pid=visit['placeID']
        check(leg['from'].upper()==last.upper() and leg['to']==pid,'wrong leg endpoint')
        check(near(leg['departure'],cursor) and near(leg['evidence']['departure'],cursor),'departure evidence mismatch')
        check(leg['evidence']['seconds']>=0 and near(leg['arrival'],cursor+leg['evidence']['seconds']),'ETA arithmetic')
        check(near(visit['arrival'],leg['arrival']) and start>=leg['arrival'],'arrival/visit mismatch')
        check(near(end-start,requested[pid]['durationMinutes']*60),'full dwell not retained')
        check(any(start>=b['start'] and end<=b['end'] for b in row['operatingBounds'][pid]),'outside opening session')
        waiting+=start-leg['arrival'];travel+=leg['evidence']['seconds'];dwell+=end-start;cursor=end;last=pid
    leg=legs[-1]
    check(leg['from']==last and leg['to'].upper()==origin,'wrong return identity')
    check(near(leg['departure'],cursor) and near(leg['evidence']['departure'],cursor),'wrong return departure')
    check(near(leg['arrival'],cursor+leg['evidence']['seconds']),'wrong return ETA')
    travel+=leg['evidence']['seconds'];finish=leg['arrival']
    check(finish<=plan['deadline'] and near(finish,out['finish']),'return deadline')
    check(waiting<=plan['maximumWaitingMinutes']*60+.005,'waiting cap')
    check(near(waiting,out['waitingSeconds']) and near(travel,out['travelSeconds']) and near(dwell,out['dwellSeconds']),'totals')
    check(near(out['elapsedSeconds'],travel+dwell+waiting) and near(finish-plan['departure'],out['elapsedSeconds']),'elapsed decomposition')
    check(out['travelCalls']<=plan['maxTravelCalls'],'combined ETA budget')
    return {'candidate':True,'visits':len(visits),'required':len(required),'omitted':len(omitted),'waitingMinutes':waiting/60,'etaCalls':out['travelCalls']}

def main():
    p=argparse.ArgumentParser();p.add_argument('--directory',type=Path,default=OUT);a=p.parse_args();out=a.directory
    rows=json.loads((out/'simulator-recommendations.json').read_text())
    primary=[r for r in rows if (r.get('campaignLabel','').endswith(':v6') and 'testControlledRecommendationCampaign' in r['campaignLabel']) or (r.get('campaignLabel','').endswith(':v7') and 'testLiveRecommendationCampaign' in r['campaignLabel'])]
    success_ids=[r['recommendationID'] for r in primary if r['success']]
    check(len(success_ids)==len(set(success_ids)),'repeated recommendation operation')
    check(sum(r['success'] and r['mode']=='live' for r in primary)>=3,'fewer than three actual live operations')
    for fixture in ['fixture-balanced','fixture-unknown_hours']:
        check(sum(r['success'] and r['mode']==fixture for r in primary)>=2,'fixture repetitions missing')
    checks=[recommendation(r) for r in primary]
    groups={}
    for mode in sorted(set(r['mode'] for r in primary)):
        group=[r for r in primary if r['mode']==mode];success=[r for r in group if r['success']]
        groups[mode]={'attempts':len(group),'successes':len(success),'failures':len(group)-len(success)}
        if success:
            groups[mode].update(readyMedian=statistics.median(r['displayReadySeconds'] for r in success),
                readyRange=[min(r['displayReadySeconds'] for r in success),max(r['displayReadySeconds'] for r in success)],
                acquisitionMedian=statistics.median(r['metrics']['acquisitionSeconds'] for r in success),
                e5Median=statistics.median(r['metrics']['embeddingSeconds'] for r in success),
                llmMedian=statistics.median(r['metrics']['llmSeconds'] for r in success),
                costUSD=sum(r['metrics']['costUSD'] for r in success))
    liveplan=json.loads((out/'personal-plan-latest.json').read_text())
    plancheck=itinerary(liveplan,primary)
    seed=next(r for r in primary if r['success'] and r['mode']=='fixture-balanced')
    mutations={
        'foreign_llm_id':lambda r:r['judgments'][0].__setitem__('id','foreign'),
        'false_unknown_hours':lambda r:r['judgments'][0].__setitem__('reasonCodes',['hours_unknown']),
        'foreign_evidence':lambda r:r['judgments'][0].__setitem__('evidenceIDs',['foreign:hours']),
        'nonzero_cost':lambda r:r['metrics'].__setitem__('costUSD',1),
        'late_display':lambda r:r.__setitem__('displayReadySeconds',21),
        'duplicate_displayed_place':lambda r:r['candidates'].__setitem__(1,copy.deepcopy(r['candidates'][0]))}
    rejected=[]
    for name,change in mutations.items():
        bad=copy.deepcopy(seed);change(bad)
        try:recommendation(bad)
        except AssertionError:rejected.append(name)
    check(len(rejected)==len(mutations),'recommendation mutation accepted')
    plan_mutations={
        'dwell':lambda r:r['response']['result']['itinerary']['visits'][0]['visit'].__setitem__('end',r['response']['result']['itinerary']['visits'][0]['visit']['end']-60),
        'waiting_total':lambda r:r['response']['result']['itinerary'].__setitem__('waitingSeconds',99999),
        'return_identity':lambda r:r['response']['result']['itinerary']['legs'][-1].__setitem__('to','foreign'),
        'required_selection':lambda r:r['response'].__setitem__('requiredPlaceIDs',[])}
    plan_mutations['nearby_different_business']=lambda r:r['identities'][0].__setitem__('appleName','Different Business')
    rejected_plan=[]
    for name,change in plan_mutations.items():
        bad=copy.deepcopy(liveplan);change(bad)
        try:itinerary(bad,primary)
        except AssertionError:rejected_plan.append(name)
    check(len(rejected_plan)==len(plan_mutations),'itinerary mutation accepted')
    result={'observations':len(primary),'groups':groups,'checks':checks,'itinerary':plancheck,
        'negativeRecommendationControls':rejected,'negativeItineraryControls':rejected_plan,
        'humanAccuracy':'not_evaluated','fieldValidity':'not_evaluated'}
    (out/'independent-audit.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
