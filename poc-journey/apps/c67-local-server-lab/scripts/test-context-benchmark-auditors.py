#!/usr/bin/env python3
"""Regression controls for benchmark status, coverage and accounting validation."""
import copy
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

live = module('live_audit', 'audit-context-pilot-live.py')
fixture = module('fixture_audit', 'context-pilot-fixtures.py')
report = json.loads((ROOT / 'artifacts/context-five-2026-11-07/diagnostic60/live-report.json').read_text())
cases = json.loads((ROOT / 'artifacts/context-five-2026-11-07/fixtures.json').read_text())['cases']
observations = json.loads((ROOT / 'artifacts/context-five-2026-11-07/observations.json').read_text())

results = []
def rejected(name, operation):
    try:
        operation()
    except AssertionError:
        results.append({'control': name, 'rejected': True})
    else:
        raise AssertionError('Invalid benchmark accepted: ' + name)

wrong_status = copy.deepcopy(report['rows'][0])
wrong_status['result']['status'] = 'no_candidate_within_search'
rejected('live visits with non-ready status', lambda: live.check(report, wrong_status))

empty_success = {'ablation': 'full', 'budget': 24,
                 'result': {'visits': [], 'legs': [], 'travelCalls': 0, 'status': 'candidate'}}
rejected('fixture empty successful result', lambda: fixture.audit_row(cases[0], empty_success))

for name, changes in [('missing observation', observations[:-1]),
                      ('duplicate observation', observations + [observations[0]])]:
    with tempfile.TemporaryDirectory(prefix='c67-audit-regression-') as temporary:
        directory = Path(temporary)
        (directory / 'fixtures.json').write_text(json.dumps({'cases': cases}))
        (directory / 'observations.json').write_text(json.dumps(changes))
        rejected(name, lambda: fixture.audit(directory))

for name, key, value in [('wrong ETA total', 'appleETACells', report['appleETACells'] + 1),
                         ('impossible pipeline timer', 'completeCLISeconds', 0)]:
    corrupted = copy.deepcopy(report)
    corrupted[key] = value
    with tempfile.TemporaryDirectory(prefix='c67-live-audit-regression-') as temporary:
        directory = Path(temporary)
        (directory / 'live-report.json').write_text(json.dumps(corrupted))
        rejected(name, lambda: live.audit(directory))

print(json.dumps({'controlsPassed': len(results), 'results': results}, indent=2))
