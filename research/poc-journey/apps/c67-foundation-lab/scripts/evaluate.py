#!/usr/bin/env python3
"""Run each model attempt in a fresh process; the oracle stays in this assessor."""
import argparse
import collections
import hashlib
import json
import math
import pathlib
import platform
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]

def dump(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def assess(case, result, expected):
    issues = []
    if not result.get('shapeAndReferencesValid'):
        issues.append('shape_reference_or_runtime_failure')
    try:
        raw = json.loads(result['rawOutput'])
    except (KeyError, ValueError, TypeError):
        return issues + ['no_json_response']
    if case['capability'] == 'preferences':
        for key in ['interests', 'avoids']:
            if key in expected and set(raw.get(key, [])) != set(expected[key]): issues.append(key+'_mismatch')
        if 'pace' in expected and raw.get('pace') != expected['pace']: issues.append('pace_mismatch')
        if expected.get('clarification') and not raw.get('clarification'): issues.append('missing_clarification')
    if case['capability'] == 'candidates':
        ids = [c.get('candidateID') for c in raw.get('choices', [])]
        if not set(expected.get('required', [])).issubset(ids): issues.append('missing_required_candidate')
        if not set(ids).issubset(expected.get('allowed', ids)): issues.append('unrelated_candidate')
    if case['capability'] == 'windows':
        windows = {w.get('stopID'): w.get('window') for w in raw.get('suggestions', [])}
        if set(windows) != {s['place']['id'] for s in case['context']['stops']}: issues.append('stop_set_changed')
        for stop, allowed in expected.get('required_windows', {}).items():
            if windows.get(stop) not in allowed: issues.append('window_mismatch_'+stop)
    text = json.dumps(raw,ensure_ascii=False).lower()
    aliases = {'price':['price','cost'], 'quiet':['quiet','noise','sound']}
    for term in expected.get('unknown_terms', []):
        # This only checks presence, not whether prose correctly expresses uncertainty.
        if not any(t in text for t in aliases.get(term,[term])): issues.append('missing_unknown_'+term)
    for term in expected.get('required_terms', []):
        if term.lower() not in text: issues.append('missing_term_'+term)
    if expected.get('required_any') and not any(t.lower() in text for t in expected['required_any']): issues.append('missing_required_concept_proxy')
    for term in expected.get('forbidden_terms', []):
        if term.lower() in text: issues.append('forbidden_text_proxy_'+term)
    return issues

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('binary',type=pathlib.Path)
    parser.add_argument('output',type=pathlib.Path)
    args=parser.parse_args()
    out=args.output.resolve(); out.mkdir(parents=True,exist_ok=False)
    source={str(p.relative_to(ROOT)):sha(p) for p in sorted(ROOT.rglob('*')) if p.is_file() and
            (p.suffix=='.swift' or p.name=='project.yml' or p.parent.name=='evaluation' or 'Resources' in p.parts) and
            not any(part in ['.build','DerivedData','.git'] for part in p.parts)}
    source.update({str(p.relative_to(ROOT)):sha(p) for p in sorted((ROOT/'scripts').glob('*.py'))})
    dump(out/'freeze.json',dict(createdAt=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
        sourceSHA256=source,binarySHA256=sha(args.binary),binary=str(args.binary.resolve()),
        host=platform.platform(),sampling='greedy',maximumResponseTokens=800,timeoutSeconds=20,
        processWatchdogSeconds=25,repetitions=3,automaticRetries=0,semanticReview='pending',
        limitations=['Not a blind holdout','Greedy repeats correlated','No packet capture or network isolation in this series']))
    cases=[json.loads(line) for line in (ROOT/'evaluation/inputs.jsonl').read_text().splitlines()]
    oracle=json.loads((ROOT/'evaluation/oracle.json').read_text())
    records=[]
    for repeat in range(1,4):
        for case in cases:
            run_id=f"{case['id']}-r{repeat}"
            input_path=out/(run_id+'-input.json')
            output_path=out/(run_id+'-output.json')
            dump(input_path,case)
            started=time.monotonic()
            try:
                proc=subprocess.run([str(args.binary.resolve()),'evaluate-one','--input',str(input_path),'--out',str(output_path)],capture_output=True,text=True,timeout=25)
                (out/(run_id+'-stderr.txt')).write_text(proc.stderr)
                if output_path.exists(): result=json.loads(output_path.read_text())
                else: result=dict(status='process_error',error=proc.stderr,rawOutput='',shapeAndReferencesValid=False)
            except subprocess.TimeoutExpired as exc:
                result=dict(status='process_timeout',error='25-second process watchdog terminated runner; model daemon stop timing not independently verified',rawOutput='',shapeAndReferencesValid=False)
                dump(output_path,result)
            record=dict(runID=run_id,caseID=case['id'],capability=case['capability'],repeat=repeat,
                        processSeconds=time.monotonic()-started,attempt=result,
                        objectiveFindings=assess(case,result,oracle[case['id']]),humanSemanticReview='pending')
            records.append(record)
            with (out/'assessed-runs.jsonl').open('a') as handle: handle.write(json.dumps(record,ensure_ascii=False)+'\n')
            print(f"{len(records)}/72 {run_id}: {result['status']}; objective findings={len(record['objectiveFindings'])}",flush=True)
    def stats(values):
        values=sorted(values)
        return {f'p{p}':values[max(0,math.ceil(len(values)*p/100)-1)] for p in [50,90]}|{'max':max(values)} if values else {}
    groups={}
    for group in ['preferences','candidates','windows','explanation']:
        rows=[r for r in records if r['capability']==group]
        groups[group]=dict(attempts=len(rows),statusCounts=dict(collections.Counter(r['attempt']['status'] for r in rows)),
            shapeAndReferencesValid=sum(r['attempt'].get('shapeAndReferencesValid',False) for r in rows),
            objectiveChecksClear=sum(not r['objectiveFindings'] for r in rows),
            processLatencySeconds=stats([r['processSeconds'] for r in rows]),
            responseOnlyLatencySeconds=stats([r['attempt']['responseSeconds'] for r in rows if r['attempt'].get('rawOutput')]),
            humanReview='pending for every response')
    changed=[name for name,digest in source.items() if not (ROOT/name).is_file() or sha(ROOT/name)!=digest]
    summary=dict(attempts=len(records),groups=groups,sourceChangedSinceFreeze=changed,
                 factualAccuracy='not established; independent human review pending',userBenefit='not measured',
                 repetitions='Correlated greedy observations, not independent samples')
    dump(out/'summary.json',summary)
    with (out/'human-review.csv').open('w') as handle:
        handle.write('runID,reviewer,factual_claims_supported,preferences_correct,recommendation_useful,notes\n')
        for r in records:
            for reviewer in ['reviewer_1','reviewer_2']: handle.write(f"{r['runID']},{reviewer},,,,\n")
    report=['# Foundation Lab English evaluation','', '72 attempts: 24 synthetic cases × 3 fresh processes/sessions. English only.',
        'Automated findings are incomplete proxies; human semantic review is pending. This is not a blind holdout.','',
        '| Capability | Attempts | Shape/references valid | Objective checks clear |','| --- | ---: | ---: | ---: |']
    report += [f"| {name} | {v['attempts']} | {v['shapeAndReferencesValid']} | {v['objectiveChecksClear']} |" for name,v in groups.items()]
    report += ['',f'Source changes since freeze: {changed}.','Greedy repetitions are correlated. Mac results do not establish iPhone latency or user benefit.']
    (out/'REPORT.md').write_text('\n'.join(report)+'\n')
    print(json.dumps(summary,indent=2),flush=True)

if __name__=='__main__': main()
