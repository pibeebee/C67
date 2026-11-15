#!/usr/bin/env python3
"""Focused local experiment. This runner does not read a grading key."""
import copy
import datetime
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import time
import uuid

HERE = pathlib.Path(__file__).resolve().parent
PARENT = HERE.parent
spec = importlib.util.spec_from_file_location('prepared', PARENT / 'prepared-english/run.py')
prepared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepared)
PACKAGE = pathlib.Path('/Users/neuhendra/Downloads/foundation-models-evaluation-2026-11-04')
BINARY = pathlib.Path('/tmp/c67-focused-evaluator')


def focused(item):
    original = prepared.build(item)
    ident, family = original['id'], original['family']
    old = original['context']
    common = {'fixture': old['fixture'], 'stateRevision': old['stateRevision']}
    if family in ('intent', 'safety'):
        common.update({k: old[k] for k in ('currentStopID', 'stops', 'now', 'serviceDate', 'timeZone', 'endPointID', 'proposal')})
        kind = 'intent'
    elif family == 'preference':
        kind = 'preference'
    elif family == 'explanation':
        index = {'golden': 'E-GOLD', 'weather': 'E-WEATHER', 'route': 'E-ROUTE'}[ident]
        common['evidence'] = [x for x in old['evidence'] if x['id'] == index]
        kind = 'explanation'
    else:
        common['evidence'] = [x for x in old['evidence'] if x['id'] in ('E-P1', 'E-P2')]
        common['placeCandidates'] = old['placeCandidates']
        kind = 'recommendation'
    return {'id': ident, 'family': family, 'input': {'kind': kind, 'context': common,
            'history': original['history'], 'userMessage': original['userMessage'], 'tools': []}}


def tool_cases():
    common = {'fixture': 'SYNTHETIC local fixtures; not live data', 'stateRevision': 7}
    prompts = [
        ('tool-weather', 'readWeather', 'Use readWeather to check the forecast for stop C at 2026-11-05T09:30:00+07:00. Is rain guaranteed?'),
        ('tool-search', 'searchPlaces', 'Use searchPlaces to find coffee and reading in Cipete. Report the result and unknowns.'),
        ('tool-unavailable', 'readOpeningHours', 'Use readOpeningHours to check stop C on 2026-11-05. If unavailable, say so and stop.'),
    ]
    return [{'id': ident, 'family': 'tool', 'input': {'kind': 'tool', 'context': common, 'history': [],
             'userMessage': message, 'tools': [tool]}} for ident, tool, message in prompts]


def cases():
    matched = [focused(c) for c in prepared.cases]
    # New paraphrases; task selection is supplied by the harness, not predicted by the model.
    new = [
        ('new-extend', 'intent', 'Please stay another 20 minutes at this stop.', [], {}),
        ('new-negation', 'intent', 'Keep D; remove C from the remaining trip.', [], {}),
        ('new-ambiguous', 'intent', 'Cancel that one.', [], {}),
        ('new-deadline', 'intent', 'Make the O arrival deadline 11:15 AM today.', [], {}),
    ]
    return matched + [focused(c) for c in new] + tool_cases()


def invoke(case, iteration):
    with tempfile.TemporaryDirectory(prefix='c67-focused-') as tmp:
        trace = pathlib.Path(tmp) / 'trace.jsonl'
        cmd = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(BINARY),
               str(PACKAGE / 'local-tool-fixtures.json'), str(trace)]
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        before = time.monotonic()
        try:
            proc = subprocess.run(cmd, input=json.dumps(case['input'], ensure_ascii=False), text=True,
                                  capture_output=True, timeout=30, check=False)
            try: result = json.loads(proc.stdout)
            except json.JSONDecodeError: result = {'outcome': 'runner_error', 'stdout': proc.stdout, 'stderr': proc.stderr, 'exitCode': proc.returncode}
        except subprocess.TimeoutExpired:
            result = {'outcome': 'timeout', 'error': '30-second process deadline'}
        duration = round(time.monotonic() - before, 3)
        calls = [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
    return {'runID': str(uuid.uuid4()), 'caseID': case['id'], 'family': case['family'], 'repeat': iteration,
            'input': case['input'], 'startedAt': started, 'wallSeconds': duration, 'result': result,
            'toolTrace': calls, 'model': 'SystemLanguageModel.default', 'locale': 'en_US',
            'sampling': 'greedy', 'maximumResponseTokens': 450, 'timeoutSeconds': 30,
            'network': 'process sandbox denies network; system daemon not separately isolated'}


def main():
    selected = cases()[:1] if sys.argv[1] == 'sanity' else cases()
    n = 1 if sys.argv[1] == 'sanity' else 2
    out = HERE / ('sanity.jsonl' if n == 1 else 'runs.jsonl')
    if out.exists(): raise SystemExit('Refusing to overwrite prior results')
    for case in selected:
        for iteration in range(1, n + 1):
            row = invoke(case, iteration)
            with out.open('a') as f: f.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n'); f.flush()
            print(case['id'], iteration, row['result']['outcome'], row['wallSeconds'], len(row['toolTrace']), flush=True)


if __name__ == '__main__': main()
