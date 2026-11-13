#!/usr/bin/env python3
"""Find zero-price logprobs models and make bounded, synthetic capability probes.

This does not edit the active PoC provider or account settings. Only sanitized
metadata, a synthetic letter response and token scores are persisted.
"""
import argparse
import datetime as dt
import fcntl
import json
import math
import subprocess
import time
from pathlib import Path

from catalog_engine import ROOT
from server import credentials

API = 'https://openrouter.ai/api/v1'


def request(path, body=None, key=None):
    config = ['url = ' + json.dumps(API + path), 'max-time = 25',
              'request = ' + json.dumps('GET' if body is None else 'POST')]
    if key:
        config.append('header = ' + json.dumps('Authorization: Bearer ' + key))
    if body is not None:
        config += ['header = "Content-Type: application/json"', 'data-binary = ' + json.dumps(json.dumps(body))]
    started = time.monotonic()
    process = subprocess.run(['/usr/bin/curl', '--silent', '--show-error', '--config', '-',
                              '--write-out', '\n%{http_code}'],
                             input=('\n'.join(config) + '\n').encode(), capture_output=True, timeout=27)
    raw, status = process.stdout.rsplit(b'\n', 1)
    try:
        data = json.loads(raw)
    except ValueError:
        data = {'error': {'message': 'non_json_response'}}
    return int(status), data, time.monotonic() - started


def reserve():
    usage = ROOT / '.local/openrouter-logprobs-usage.json'
    usage.parent.mkdir(parents=True, exist_ok=True)
    with usage.with_suffix('.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        attempts = json.loads(usage.read_text())['attempts'] if usage.exists() else 0
        if attempts >= 8:
            raise SystemExit('Capability campaign ceiling reached. No automatic reset.')
        temporary = usage.with_suffix('.tmp')
        temporary.write_text(json.dumps({'attempts': attempts + 1, 'cap': 8}))
        temporary.replace(usage)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live', action='store_true', help='Send one synthetic request per shortlisted model')
    parser.add_argument('--output', type=Path, default=ROOT / 'artifacts/catalog-2026-11-10/openrouter-logprobs.json')
    args = parser.parse_args()
    status, catalog, _ = request('/models')
    if status != 200:
        raise SystemExit('Public model catalogue unavailable')
    candidates = []
    for row in catalog['data']:
        pricing = row.get('pricing', {})
        params = row.get('supported_parameters', [])
        if row['id'].endswith(':free') and all(float(pricing.get(k, '1')) == 0 for k in ['prompt', 'completion']) and {'logprobs', 'top_logprobs'} <= set(params):
            candidates.append({k: row.get(k) for k in ['id', 'name', 'hugging_face_id', 'pricing', 'supported_parameters', 'reasoning']})
    report = {'checkedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
              'catalogSource': API + '/models', 'candidates': candidates, 'probes': [],
              'activePoCConfigurationEdited': False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    if not args.live:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return
    key = credentials().get('OPENROUTER_API_KEY')
    if not key:
        raise SystemExit('Missing OpenRouter key. Public shortlist retained.')
    for model in candidates[:4]:
        ident = model['id']
        endpoint_status, endpoints, _ = request('/models/' + ident + '/endpoints')
        provider_rows = endpoints.get('data', {}).get('endpoints', []) if endpoint_status == 200 else []
        model['endpoints'] = [{k: r.get(k) for k in ['provider_name', 'name', 'supported_parameters', 'pricing']} for r in provider_rows]
        reserve()
        body = {'model': ident, 'temperature': 0, 'max_tokens': 8,
                'messages': [{'role': 'system', 'content': 'Answer with exactly one letter A, B, or C. Do not explain.'},
                             {'role': 'user', 'content': 'Choose a label for insufficient evidence: A = supported; B = contradicted; C = unknown. No venue facts were supplied.'}],
                'logprobs': True, 'top_logprobs': 20,
                'provider': {'require_parameters': True, 'data_collection': 'deny',
                             'max_price': {'prompt': 0, 'completion': 0, 'request': 0}}}
        if not (model.get('reasoning') or {}).get('mandatory'):
            body['reasoning'] = {'enabled': False}
        else:
            body['max_tokens'] = 256
        status, response, seconds = request('/chat/completions', body, key)
        probe = {'model': ident, 'httpStatus': status, 'seconds': seconds,
                 'requestedLogprobs': True, 'requestedTopLogprobs': 20, 'actualLogprobs': False}
        if status == 200:
            choice = response.get('choices', [{}])[0]
            logprobs = choice.get('logprobs') or {}
            positions = logprobs.get('content') or []
            first = positions[0] if positions else {}
            top = first.get('top_logprobs') or []
            scores = {r['token']: r['logprob'] for r in top if isinstance(r.get('logprob'), (int, float)) and math.isfinite(r['logprob'])}
            labels = {label: scores.get(label) for label in ['A', 'B', 'C']}
            probe.update(actualLogprobs=bool(positions), content=choice.get('message', {}).get('content'),
                         reportedModel=response.get('model'), provider=response.get('provider'),
                         finishReason=choice.get('finish_reason'), firstToken=first.get('token'),
                         topLogprobs=scores, exactCandidateScores=labels,
                         allThreeCandidateScores=all(v is not None for v in labels.values()),
                         costUSD=response.get('usage', {}).get('cost'))
        else:
            error = response.get('error', {})
            message = str(error.get('message', 'request_failed')).replace(key, '[redacted]')[:400]
            probe.update(errorCode=error.get('code'), errorMessage=message,
                         failedRoutingStep=error.get('metadata', {}).get('failed_routing_step'))
        report['probes'].append(probe)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(json.dumps(probe, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
