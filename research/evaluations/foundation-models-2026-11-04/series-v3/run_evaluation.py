#!/usr/bin/env python3
"""Run Apple system-model evaluation. This runner never opens the evaluator oracle."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
DEFAULT_PACKAGE = Path('/Users/neuhendra/Downloads/foundation-models-evaluation-2026-11-04')
NETWORK_PROFILE = '(version 1)(allow default)(deny network*)'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(value, schema, path='$'):
    errors = []
    types = schema.get('type', [])
    types = [types] if isinstance(types, str) else types
    matches = {'null': value is None, 'object': isinstance(value, dict),
               'array': isinstance(value, list), 'string': isinstance(value, str),
               'integer': isinstance(value, int) and not isinstance(value, bool),
               'boolean': isinstance(value, bool)}
    if types and not any(matches.get(t, False) for t in types):
        return [f'{path}: expected {types}, got {type(value).__name__}']
    if 'enum' in schema and value not in schema['enum']:
        errors.append(f'{path}: value outside allowed enum')
    if isinstance(value, dict):
        for key in schema.get('required', []):
            if key not in value:
                errors.append(f'{path}.{key}: missing required field')
        props = schema.get('properties', {})
        for key, item in value.items():
            if key in props:
                errors.extend(validate(item, props[key], f'{path}.{key}'))
            elif schema.get('additionalProperties') is False:
                errors.append(f'{path}.{key}: extra field')
    if isinstance(value, list):
        if len(value) > schema.get('maxItems', float('inf')):
            errors.append(f'{path}: too many items')
        for index, item in enumerate(value):
            errors.extend(validate(item, schema.get('items', {}), f'{path}[{index}]'))
    return errors


def load_cases(package):
    return [json.loads(line) for line in (package / 'inputs.jsonl').read_text().splitlines() if line.strip()]


def run_case(case, index, phase, package, binary, schema, seconds):
    run_id = str(uuid.uuid4())
    with tempfile.TemporaryDirectory(prefix='c67-eval-') as tmp:
        trace = Path(tmp) / 'tool-trace.jsonl'
        # No case ID, split, family or evaluator-only data is passed to the model executable.
        payload = {key: case[key] for key in ('context', 'history', 'userMessage')}
        command = ['/usr/bin/sandbox-exec', '-p', NETWORK_PROFILE, str(binary),
                   str(package / 'model-instructions.txt'), str(package / 'local-tool-fixtures.json'), str(trace)]
        started_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
        started = time.monotonic()
        try:
            proc = subprocess.run(command, input=json.dumps(payload, ensure_ascii=False), text=True,
                                  capture_output=True, timeout=seconds, check=False)
            duration = time.monotonic() - started
            stdout, stderr = proc.stdout, proc.stderr
            try:
                result = json.loads(stdout)
            except json.JSONDecodeError:
                result = {'outcome': 'runner_error', 'stdout': stdout, 'stderr': stderr,
                          'exitCode': proc.returncode}
        except subprocess.TimeoutExpired as exc:
            duration = time.monotonic() - started
            result = {'outcome': 'timeout', 'error': f'process exceeded {seconds}s and was terminated',
                      'stdout': (exc.stdout or b'').decode(errors='replace') if isinstance(exc.stdout, bytes) else (exc.stdout or ''),
                      'stderr': (exc.stderr or b'').decode(errors='replace') if isinstance(exc.stderr, bytes) else (exc.stderr or '')}
        tool_trace = [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
    parsed = result.get('parsedFields')
    errors = validate(parsed, schema) if result.get('outcome') == 'response' else []
    return {'runID': run_id, 'caseID': case['id'], 'family': case['family'], 'split': case['split'],
            'phase': phase, 'repeat': index, 'mode': 'M2' if case['mode'] == 'local_tools' else 'M1',
            'locale': case['context']['locale'], 'promptVersion': 'package-v1/schema-v3-explicit-nulls',
            'model': 'SystemLanguageModel.default', 'sampling': 'greedy', 'temperature': None,
            'seed': None, 'maxResponseTokens': 1400, 'timeoutSeconds': seconds,
            'network': 'process sandbox denies network; system-wide offline not established',
            'startedAt': started_at,
            'wallSeconds': round(duration, 3), 'result': result, 'schemaValid': not errors if parsed is not None else False,
            'schemaErrors': errors, 'toolTrace': tool_trace, 'toolCalls': len(tool_trace),
            'semanticGrade': 'not_reviewed', 'criticalViolation': 'not_reviewed',
            'reviewNote': 'No human semantic review performed'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase', required=True, choices=['sanity', 'development-diagnostic', 'primary', 'evaluation-diagnostic'])
    parser.add_argument('--repeat', type=int, default=1)
    parser.add_argument('--case', action='append', help='Filter case IDs; repeat flag for multiple IDs')
    parser.add_argument('--package', type=Path, default=DEFAULT_PACKAGE)
    parser.add_argument('--binary', type=Path, default=Path('/tmp/c67-foundation-model-evaluator-v3'))
    parser.add_argument('--timeout', type=float, default=20)
    args = parser.parse_args()
    if args.repeat < 1 or args.timeout <= 0 or not args.binary.is_file():
        parser.error('repeat/timeout must be positive and compiled binary must exist')
    freeze = HERE / 'freeze.json'
    if args.phase in ('primary', 'evaluation-diagnostic') and not freeze.exists():
        parser.error('Freeze prompt, schema, source and settings before primary/evaluation runs')
    if args.phase in ('sanity', 'development-diagnostic') and freeze.exists():
        parser.error('Development is frozen; do not change or add development runs to this series')
    if freeze.exists():
        frozen = json.loads(freeze.read_text())
        for path, expected in frozen['sha256'].items():
            if digest(Path(path)) != expected:
                parser.error(f'Frozen source changed: {path}')
        if args.timeout != frozen['settings']['timeoutSeconds']:
            parser.error('Timeout does not match frozen settings')
    cases = load_cases(args.package)
    if args.phase == 'sanity':
        cases = [c for c in cases if c['id'] == 'LANG-01']
    elif args.phase == 'development-diagnostic':
        cases = [c for c in cases if c['split'] == 'development' and c['context']['locale'] == 'id_ID']
    elif args.phase == 'primary':
        cases = [c for c in cases if c['context']['locale'] == 'en_US']
    else:
        cases = [c for c in cases if c['split'] == 'evaluation' and c['context']['locale'] == 'id_ID']
    if args.case:
        cases = [c for c in cases if c['id'] in args.case]
    if not cases:
        parser.error('No cases match phase/filter')
    schema = json.loads((args.package / 'output-contract.json').read_text())
    output = HERE / f'runs-{args.phase}.jsonl'
    for case in cases:
        for index in range(1, args.repeat + 1):
            result = run_case(case, index, args.phase, args.package, args.binary, schema, args.timeout)
            with output.open('a') as stream:
                stream.write(json.dumps(result, ensure_ascii=False, sort_keys=True) + '\n')
                stream.flush()
                os.fsync(stream.fileno())
            print(f"{case['id']} #{index}: {result['result']['outcome']} schema={result['schemaValid']} wall={result['wallSeconds']}s tools={result['toolCalls']}", flush=True)


if __name__ == '__main__':
    main()
