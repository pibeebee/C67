#!/usr/bin/env python3
"""Independent artifact checks; never interprets prose as proven semantic accuracy."""
import collections
import hashlib
import json
import pathlib
import sys

ROOT=pathlib.Path(__file__).resolve().parents[1]
BASE=ROOT/'docs/verification/foundation-lab-2026-11-04'
errors=[]
def check(condition,message):
    if not condition: errors.append(message)
def load(path): return json.loads(path.read_text())
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

series=BASE/'english-series-v3'
rows=[json.loads(line) for line in (series/'assessed-runs.jsonl').read_text().splitlines()]
check(len(rows)==72,'Final evaluation must contain 72 attempts')
counts=collections.Counter(r['caseID'] for r in rows)
check(len(counts)==24 and set(counts.values())=={3},'Expected 24 cases with three attempts each')
check(len({r['runID'] for r in rows})==72,'Run IDs must be unique')
summary=load(series/'summary.json')
for capability,group in summary['groups'].items():
    selected=[r for r in rows if r['capability']==capability]
    check(len(selected)==18,capability+' denominator')
    check(sum(r['attempt'].get('shapeAndReferencesValid',False) for r in selected)==group['shapeAndReferencesValid'],capability+' shape count')
    check(sum(not r['objectiveFindings'] for r in selected)==group['objectiveChecksClear'],capability+' objective count')
check(all(r['humanSemanticReview']=='pending' for r in rows),'Human review may not be silently promoted')
freeze=load(series/'freeze.json')
changed=[name for name,old in freeze['sourceSHA256'].items() if not (ROOT/name).is_file() or digest(ROOT/name)!=old]
post_path=BASE/'post-freeze-changes.json'
post=load(post_path) if post_path.exists() else {}
for name in changed:
    entry=post.get(name)
    check(entry is not None,'Unexplained source change after v3 freeze: '+name)
    if entry:
        check(entry['evaluatedSHA256']==freeze['sourceSHA256'][name],'Wrong evaluated hash: '+name)
        check(digest(ROOT/name)==entry['finalSHA256'],'Final hash mismatch: '+name)
        check(digest(BASE/entry['evaluatedCopy'])==entry['evaluatedSHA256'],'Evaluated copy mismatch: '+name)
critical=['Contracts.swift','ModelEngine.swift','ImportAndSearch.swift','Evaluation.swift','Fixtures.swift','main.swift']
check(not any(pathlib.Path(name).name in critical for name in changed),'Model evaluation code changed after freeze')

pipelines=[]
for name in ['mac-live-v3','mac-baseline-v3','simulator-restored','iphone-observed','iphone-smoke']:
    path=BASE/name/'run.json'
    if not path.exists(): continue
    run=load(path);pipelines.append(name)
    check(not run['validatedScheduleChanges'],name+': must not validate a new timetable')
    check(len(run['context']['stops'])<=6,name+': stop limit')
    check(run['context']['timeZoneID']=='Asia/Jakarta',name+': time zone')
    for stage in run['stages']:
        if stage['source']=='Foundation Models':
            check(stage['rawOutput']==stage['displayedOutput'],name+': raw model output altered before display')
            check(stage['status']=='validated_shape_and_references',name+': unvalidated model output displayed')
        else:
            check(stage['status']!='validated_shape_and_references',name+': fallback mislabelled as model')
    ids=[x['candidateID'] for x in run['candidates']['choices']]
    check(len(ids)<=3 and len(set(ids))==len(ids),name+': duplicate or excessive candidate choices')
    check(set(ids).issubset({c['place']['id'] for c in run['search']['candidates']}),name+': invented candidate ID')
    check({x['stopID'] for x in run['windows']['suggestions']}=={s['place']['id'] for s in run['context']['stops']},name+': changed visit set')
    check(len(run['search']['queries'])<=2 and len(run['search']['candidates'])<=10,name+': search bounds')

model=load(BASE/'mac-live-v3/run.json');baseline=load(BASE/'mac-baseline-v3/run.json')
check(model['context']==baseline['context'],'Comparison context differs')
check(model['direction']==baseline['direction'],'Comparison user direction differs')
# Live search is performed twice and is allowed to change; do not claim identical provider observations.
old=load(BASE/'routing-source-before.json')
external_changes=[name for name,sha in old.items() if not pathlib.Path(name).is_file() or digest(pathlib.Path(name))!=sha]
result=dict(errors=errors,checkedFinalAttempts=len(rows),checkedPipelineArtifacts=pipelines,
            finalSourceChangedSinceFreeze=changed,explainedPostFreezeChanges=post,modelEvaluationCodeUnchanged=True,routingSourceChangesObserved=external_changes,
            routingSourcePolicy='This implementation only writes inside c67-foundation-lab; concurrent routing changes, if any, require separate attribution',
            semanticQuality='not established by this auditor')
(BASE/'audit.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
sys.exit(bool(errors))
