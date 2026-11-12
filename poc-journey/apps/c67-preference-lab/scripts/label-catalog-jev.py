#!/usr/bin/env python3
"""Run direct multi-label classification on authored place descriptions."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import nullcontext
import fcntl
import hashlib
import json
import math
import os
import tempfile
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo

from server import ROOT, credentials, curl_json

MODEL = 'typesafe/jev-1.14'
ENDPOINT = 'https://openrouter.ai/api/alpha/decisions'
THRESHOLD = 0.90  # Pilot cutoff. It has not been calibrated on venue data.
MAX_RECORDS = 500
RETRYABLE = {'provider_http_429', 'provider_http_500', 'provider_http_502',
             'provider_http_503', 'provider_http_504', 'provider_timeout', 'transport_28'}


def taxonomy():
    data = json.loads((ROOT / 'catalog/place-labels.json').read_text())
    parents = {label: parent for parent, group in data['subtypes'].items() for label in group}
    groups = [group for family in ('types', 'subtypes', 'features') for group in data[family].values()]
    definitions = {label: definition for group in groups for label, definition in group.items()}
    types = {label for group in data['types'].values() for label in group}
    if len(definitions) != sum(map(len, groups)) or set(parents.values()) - types:
        raise ValueError('Duplicate labels or invalid subtype parent')
    return data['version'], definitions, parents


def validate_inputs(rows):
    if not isinstance(rows, list) or not 1 <= len(rows) <= MAX_RECORDS:
        raise ValueError(f'Provide one to {MAX_RECORDS} independently sourced examples per run')
    seen = set()
    for row in rows:
        if set(row) != {'id', 'provenance', 'description', 'sourceURLs'}:
            raise ValueError('Expected authored input fields; raw provider records are unsupported')
        if not isinstance(row['id'], str) or not row['id'].strip() or row['id'] in seen:
            raise ValueError('Place IDs in this input must be nonempty and unique')
        seen.add(row['id'])
        if not isinstance(row['description'], str) or not 1 <= len(row['description'].strip()) <= 4000:
            raise ValueError('Description must be 1–4000 characters')
        urls = row['sourceURLs']
        if row['provenance'] == 'authored-synthetic' and urls == []:
            continue
        if row['provenance'] not in {'authored-public-facts', 'openstreetmap-odbl-v1', 'overture-places-v1'} or not isinstance(urls, list) or not urls:
            raise ValueError('Provide independently sourced metadata for real places')
        for url in urls:
            parsed = urlsplit(url)
            host = (parsed.hostname or '').lower()
            if parsed.scheme != 'https' or not host or any(
                part in host.split('.') for part in ('google', 'googleapis', 'gstatic', 'goo')
            ):
                raise ValueError('Source must be HTTPS and independent of Google Maps')
            if row['provenance'] == 'openstreetmap-odbl-v1' and host not in {'www.openstreetmap.org', 'openstreetmap.org'}:
                raise ValueError('OpenStreetMap inputs must cite their OpenStreetMap objects')
            if row['provenance'] == 'overture-places-v1' and host != 'explore.overturemaps.org':
                raise ValueError('Overture inputs must cite their Overture place records')


def make_questions(definitions):
    return {label: {'type': 'noul', 'instructions':
        'Apakah deskripsi secara eksplisit mendukung label berikut untuk tempat itu sendiri? '
        + definition + ' Jawab tidak jika informasi kurang atau hanya merujuk pada lokasi lain.'}
        for label, definition in definitions.items()}


def select_labels(answers, definitions, parents):
    if not isinstance(answers, dict) or set(answers) != set(definitions):
        raise ValueError('Jev must return one answer for every requested label')
    scores = {}
    for label, answer in answers.items():
        score = answer.get('noul') if isinstance(answer, dict) and answer.get('type') == 'noul' else None
        if type(score) not in (float, int) or not math.isfinite(score) or not 0 <= score <= 1:
            raise ValueError(f'Invalid Jev probability for {label}')
        scores[label] = score
    proposed = {label for label, score in scores.items() if score >= THRESHOLD}
    accepted = set(proposed)
    for label, parent in parents.items():
        if label not in proposed:
            continue
        # A subtype entails its parent. Hold contradictory results for review.
        if scores[parent] <= 0.5:
            accepted.remove(label)
        else:
            accepted.add(parent)
    return (scores, [label for label in definitions if label in accepted],
            sorted(accepted - proposed), sorted(proposed - accepted))


def classify(row, questions, definitions, parents, key, max_attempts):
    started = time.monotonic()
    for attempt in range(1, max_attempts + 1):
        try:
            response = curl_json(ENDPOINT, {'model': MODEL, 'state': {'description': row['description']},
                                          'questions': questions}, {'Authorization': 'Bearer ' + key}, 25)
            break
        except RuntimeError as error:
            if str(error) not in RETRYABLE or attempt == max_attempts:
                raise
            time.sleep(attempt)
    if response.get('provider') != 'TypeSafe' or not response.get('model', '').startswith(MODEL):
        raise ValueError('Unexpected decision model or provider')
    scores, labels, inferred, suppressed = select_labels(response.get('answers'), definitions, parents)
    usage = response.get('usage', {})
    return {'id': row['id'], 'provenance': row['provenance'], 'sourceURLs': row['sourceURLs'],
            'labels': labels, 'scores': scores, 'inferredParentLabels': inferred,
            'suppressedSubtypes': suppressed, 'model': response['model'], 'provider': response['provider'],
            'seconds': time.monotonic() - started, 'inputTokens': usage.get('input_tokens'),
            'costUSD': usage.get('cost'), 'attempts': attempt}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def write_json(path, data):
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as tmp:
        try:
            json.dump(data, tmp, ensure_ascii=False, indent=2)
            tmp.write('\n')
            tmp.flush()
            os.fsync(tmp.fileno())
            os.replace(tmp.name, path)
        finally:
            Path(tmp.name).unlink(missing_ok=True)


def run_batch(records, questions, definitions, parents, key, checkpoint, workers, signature):
    results = {}
    if checkpoint:
        manifest = checkpoint / 'manifest.json'
        if manifest.exists() and json.loads(manifest.read_text()) != signature:
            raise ValueError('Checkpoint input or model settings changed. Use a separate checkpoint directory.')
        if not manifest.exists():
            write_json(manifest, signature)
        for row in records:
            cached = checkpoint / (digest(row['id']) + '.json')
            if cached.exists():
                result = json.loads(cached.read_text())
                if result['id'] != row['id'] or set(result['scores']) != set(definitions):
                    raise ValueError('Invalid saved result in checkpoint')
                results[row['id']] = result
        print(f'Resuming with {len(results)}/{len(records)} completed', flush=True)

    failures = {}
    with ThreadPoolExecutor(max_workers=workers) as executor:
        pending = {executor.submit(classify, row, questions, definitions, parents, key,
                                   3 if checkpoint else 1): row['id']
                   for row in records if row['id'] not in results}
        for future in as_completed(pending):
            row_id = pending[future]
            try:
                result = future.result()
            except (RuntimeError, ValueError) as error:
                failures[row_id] = str(error)
                continue
            if checkpoint:
                write_json(checkpoint / (digest(row_id) + '.json'), result)
            results[row_id] = result
            if checkpoint and (len(results) % 25 == 0 or len(results) == len(records)):
                print(f'Completed {len(results)}/{len(records)}', flush=True)
    if failures:
        if checkpoint:
            write_json(checkpoint / 'failures.json', failures)
        raise RuntimeError(f'{len(results)}/{len(records)} completed; {len(failures)} failed: '
                           + ', '.join(sorted(set(failures.values()))))
    if checkpoint:
        (checkpoint / 'failures.json').unlink(missing_ok=True)
    return [results[row['id']] for row in records]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=ROOT / 'catalog/jev-label-examples.json')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--checkpoint', type=Path, help='Store and reuse completed decisions for this exact input')
    parser.add_argument('--workers', type=int, choices=range(1, 9), default=1)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists')
    records = json.loads(args.input.read_text())
    validate_inputs(records)
    if len(records) > 10 and not args.checkpoint:
        parser.error('Runs above ten examples require --checkpoint')
    version, definitions, parents = taxonomy()
    key = credentials().get('OPENROUTER_API_KEY')
    if not key:
        parser.error('OPENROUTER_API_KEY is missing in the local lab configuration')

    questions = make_questions(definitions)
    signature = {'version': 1, 'digest': digest([records, questions, parents, version, ENDPOINT, MODEL, THRESHOLD])}
    if args.checkpoint:
        args.checkpoint.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock = (args.checkpoint / 'run.lock').open('a') if args.checkpoint else nullcontext()
    with lock as lockfile:
        if lockfile:
            fcntl.flock(lockfile, fcntl.LOCK_EX | fcntl.LOCK_NB)
        results = run_batch(records, questions, definitions, parents, key, args.checkpoint, args.workers, signature)
    report = {'generatedAtWIB': datetime.now(ZoneInfo('Asia/Jakarta')).isoformat(),
              'endpoint': ENDPOINT, 'requestedModel': MODEL, 'taxonomyVersion': version,
              'labelCount': len(definitions), 'provisionalThreshold': THRESHOLD,
              'labelPolicy': 'subtype-implies-parent-unless-conflicting-v1', 'places': results}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as output:
        json.dump(report, output, ensure_ascii=False, indent=2)
        output.write('\n')
    if len(results) <= 10:
        for row in results:
            print(json.dumps({k: row[k] for k in ['id', 'labels', 'model', 'seconds', 'inputTokens', 'costUSD']},
                             ensure_ascii=False))


if __name__ == '__main__':
    main()
