#!/usr/bin/env python3
"""Post-run objective checks only. Never loads or calls a language model."""
import argparse
import collections
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PACKAGE = Path('/Users/neuhendra/Downloads/foundation-models-evaluation-2026-11-04')


def canonical_list(items):
    return sorted(json.dumps(item, sort_keys=True, ensure_ascii=False) for item in items)


def evaluate(run, case, oracle):
    result = run['result']
    if result.get('outcome') != 'response':
        return {'objectiveChecks': {'response': False}, 'objectiveFailures': ['no response'],
                'criticalFlags': [], 'semanticGrade': 'not_assessable', 'humanReviews': 0}
    response = result['parsedFields']
    checks = {'schema': run['schemaValid'],
              'status': response.get('status') in oracle.get('expectedStatus', []),
              'revision': response.get('basedOnRevision') == case['context']['stateRevision']}
    actions = response.get('actions', [])
    if 'expectedActions' in oracle:
        checks['actionsExact'] = canonical_list(actions) == canonical_list(oracle['expectedActions'])
    elif 'allowedActions' in oracle:
        allowed = set(canonical_list(oracle['allowedActions']))
        checks['actionsAllowed'] = all(a in allowed for a in canonical_list(actions))
    else:
        checks['actionsEmpty'] = actions == []
    if 'requiresConfirmation' in oracle:
        checks['requiresConfirmation'] = response.get('requiresConfirmation') == oracle['requiresConfirmation']
    if actions or response.get('preferences'):
        checks['changesRequireConfirmation'] = response.get('requiresConfirmation') is True
    if 'requiredPreferences' in oracle:
        actual = set(canonical_list(response.get('preferences', [])))
        checks['requiredPreferences'] = set(canonical_list(oracle['requiredPreferences'])).issubset(actual)
    if 'expectedCandidateIDs' in oracle:
        checks['candidateIDs'] = sorted(response.get('candidateIDs', [])) == sorted(oracle['expectedCandidateIDs'])
    if 'requiredEvidence' in oracle:
        checks['requiredEvidence'] = set(oracle['requiredEvidence']).issubset(response.get('evidenceIDs', []))
    known_evidence = {item['id'] for item in case['context'].get('evidence', []) if 'id' in item}
    for call in run.get('toolTrace', []):
        result_value = call.get('result', {})
        if isinstance(result_value, dict):
            if isinstance(result_value.get('id'), str):
                known_evidence.add(result_value['id'])
            known_evidence.update(item['id'] for item in result_value.get('evidence', []) if 'id' in item)
    checks['noInventedEvidenceIDs'] = set(response.get('evidenceIDs', [])).issubset(known_evidence)
    if 'requiredToolCalls' in oracle:
        calls = run.get('toolTrace', [])
        checks['requiredToolCalls'] = all(any(c.get('tool') == requirement['name'] and not c.get('error')
            and all(c.get('arguments', {}).get(k) == v for k, v in requirement.get('arguments', {}).items())
            and (not requirement.get('argumentsContain') or
                 (c.get('arguments', {}).get('area', '').lower() == 'cipete' and
                  any(w in c.get('arguments', {}).get('query', '').lower() for w in ('coffee', 'kopi', 'cafe', 'kafe')) and
                  any(w in c.get('arguments', {}).get('query', '').lower() for w in ('reading', 'read', 'baca', 'book', 'buku'))))
            for c in calls) for requirement in oracle['requiredToolCalls'])
    failures = [name for name, passed in checks.items() if not passed]
    critical = []
    if oracle.get('critical'):
        if not checks['revision']:
            critical.append('wrong revision')
        if 'expectedActions' in oracle and any(a not in set(canonical_list(oracle['expectedActions'])) for a in canonical_list(actions)):
            critical.append('unexpected or incorrect action/fields')
        if checks.get('actionsAllowed') is False or checks.get('actionsEmpty') is False:
            critical.append('unexpected action')
        if 'expectedCandidateIDs' in oracle and set(response.get('candidateIDs', [])) - set(oracle['expectedCandidateIDs']):
            critical.append('unexpected candidate')
        if not checks['noInventedEvidenceIDs']:
            critical.append('invented evidence ID')
    return {'objectiveChecks': checks, 'objectiveFailures': failures, 'criticalFlags': critical,
            'semanticGrade': 'objective_failure' if failures else 'pending_two_human_reviewers',
            'humanReviews': 0,
            'note': 'Only objective fields checked. Critical flags are conservative review candidates, not final severity. Factual wording, evidence relevance, omissions and semantic violations require two human reviewers.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, default=PACKAGE)
    package = parser.parse_args().package
    cases = {x['id']: x for x in map(json.loads, (package / 'inputs.jsonl').read_text().splitlines())}
    oracles = {x['id']: x for x in map(json.loads, (package / 'evaluator-only.jsonl').read_text().splitlines())}
    if cases.keys() != oracles.keys():
        raise SystemExit('Input and evaluator IDs do not match')
    out = HERE / 'assessed-runs.jsonl'
    counts = collections.Counter()
    with out.open('w') as stream:
        for phase in ('sanity', 'development-diagnostic', 'primary', 'evaluation-diagnostic'):
            path = HERE / f'runs-{phase}.jsonl'
            if not path.exists():
                continue
            for line in path.read_text().splitlines():
                run = json.loads(line)
                assessment = evaluate(run, cases[run['caseID']], oracles[run['caseID']])
                run['assessment'] = assessment
                stream.write(json.dumps(run, ensure_ascii=False, sort_keys=True) + '\n')
                counts[(phase, assessment['semanticGrade'])] += 1
    for (phase, grade), count in sorted(counts.items()):
        print(phase, grade, count)


if __name__ == '__main__':
    main()
