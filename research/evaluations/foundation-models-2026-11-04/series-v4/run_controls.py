#!/usr/bin/env python3
"""Separate runtime controls; no oracle or product mutation is involved."""
import json
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
profile = '(version 1)(allow default)(deny network*)'
controls = []
for mode in ('tokens', 'long', 'cancel'):
    start = time.monotonic()
    try:
        proc = subprocess.run(['/usr/bin/sandbox-exec', '-p', profile, '/tmp/c67-runtime-controls-v4', mode],
                              capture_output=True, text=True, timeout=20, check=False)
        try:
            result = json.loads(proc.stdout)
        except json.JSONDecodeError:
            result = {'outcome': 'runner_error', 'stdout': proc.stdout, 'stderr': proc.stderr,
                      'exitCode': proc.returncode}
    except subprocess.TimeoutExpired:
        result = {'outcome': 'timeout', 'error': 'control process terminated after 20 seconds'}
    controls.append({'control': mode, 'wallSeconds': round(time.monotonic() - start, 3), 'result': result})
    print(mode, result.get('outcome', result.get('canceledRequest', 'recorded')), flush=True)

first = next(x for x in map(json.loads, (HERE / 'runs-primary.jsonl').read_text().splitlines())
             if x['result'].get('outcome') == 'response')
revision = first['result']['parsedFields']['basedOnRevision']
current_revision = revision + 1
controls.append({'control': 'stale-revision-synthetic-wrapper', 'responseRevision': revision,
                 'currentRevision': current_revision, 'accepted': revision == current_revision,
                 'note': 'Evaluator demonstration only; no C67 application validator or storage was exercised.'})
controls.append({'control': 'network-denial', 'observed': 'sandboxed TCP connect returned errno 1 (EPERM)',
                 'note': 'Evaluator-process socket restriction only; separately hosted OS daemons were not proven offline.'})
controls.append({'control': 'unavailable-device', 'observed': 'not run: actual device was available',
                 'note': 'No system settings or product fallback were changed.'})
controls.append({'control': 'unsupported-locale', 'observed': 'id_ID false, en_US true in runtime preflight',
                 'note': 'Unsupported Indonesian responses are diagnostic and not eligible product results.'})
(HERE / 'controls.json').write_text(json.dumps(controls, indent=2, ensure_ascii=False) + '\n')
