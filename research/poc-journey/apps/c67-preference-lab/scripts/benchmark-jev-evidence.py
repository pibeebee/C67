#!/usr/bin/env python3
"""Compare four evidence bundles on the same frozen diagnostic venue sample."""

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import importlib.util
from pathlib import Path
from statistics import median
import time

from server import ROOT, credentials

spec = importlib.util.spec_from_file_location('destination_scope', ROOT / 'scripts/benchmark-destination-scope.py')
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)
baseline, jev = scope.baseline, scope.jev

VARIANTS = {
    'A': 'Google types, primary type display name and business status',
    'B': 'A + structured amenities',
    'C': 'B + editorial summary',
    'D': 'C + review excerpts',
}
SOURCES = {
    'south': ROOT / '.local/google-jev-500-2026-11-10/google',
    'wide': ROOT / '.local/jakarta-wide-jev-2026-11-10/google',
}


def bundles(place):
    without_reviews = {key: value for key, value in place.items() if key != 'reviews'}
    base = {key: value for key, value in without_reviews.items() if key not in baseline.FACTS}
    return dict(zip(VARIANTS, (
        baseline.description(base, False),
        baseline.description(place, False),
        baseline.description(without_reviews, True),
        baseline.description(place, True),
    )))


def run_case(row, place, campaign, types, definitions, parents):
    pid = row['id']
    by_description = {}
    variants = {}
    for variant, description in bundles(place).items():
        reused = description in by_description
        if not reused:
            # Key checkpoints by place and evidence. Empty optional fields do not add a provider request.
            checkpoint = pid + '-' + variant
            gate = campaign.decide_scope(checkpoint, place, description, types)
            # Score label quality on a fixed group of known destinations, including false holds.
            # The additional calls are for evaluation. Production output still obeys the gate.
            labels = (campaign.label(checkpoint, description, definitions, parents)
                      if gate['status'] == 'include' or row['expected'] == 'include' else None)
            by_description[description] = {'gate': gate, 'labelDecision': labels, 'checkpoint': variant}
        variants[variant] = {**by_description[description], 'identicalEvidenceReused': reused}
    return {'id': pid, 'variants': variants}


def summarize(references, results):
    stats = {}
    for variant in VARIANTS:
        counts = Counter()
        matrix = {status: Counter() for status in scope.ELIGIBILITY_CRITERIA}
        gate_meta, label_meta, deployment_times = [], [], []
        for row in references:
            v = results[row['id']]['variants'][variant]
            gate, decision = v['gate'], v['labelDecision']
            admitted = gate['status'] == 'include'
            matrix[row['expected']][gate['status']] += 1
            labels = set(decision['labels']) if decision else set()
            emitted = labels if admitted else set()
            counts['admittedWithLabels'] += bool(emitted)
            counts['unscoredEmissions'] += len(emitted - set(row['yes']) - set(row['no']))
            counts['emittedKnownPositive'] += len(set(row['yes']) & emitted)
            counts['emittedKnownNegative'] += len(set(row['no']) & emitted)
            if row['expected'] == 'include':
                counts['fixedPositiveHits'] += len(set(row['yes']) & labels)
                counts['fixedNegativeHits'] += len(set(row['no']) & labels)
            gate_meta.append(gate['meta'])
            if admitted:
                label_meta.append(decision['meta'])
            deployment_times.append(gate['meta']['seconds'] + (decision['meta']['seconds'] if admitted else 0))
        stats[variant] = {
            'gateMatrix': {key: dict(value) for key, value in matrix.items()},
            'gateExact': sum(matrix[k][k] for k in matrix),
            'admittedWithLabels': counts['admittedWithLabels'],
            'knownPositivesRecoveredLabelStage': counts['fixedPositiveHits'],
            'knownNegativesEmittedLabelStage': counts['fixedNegativeHits'],
            'knownPositivesEmittedEndToEnd': counts['emittedKnownPositive'],
            'knownNegativesEmittedEndToEnd': counts['emittedKnownNegative'],
            'unscoredEmissions': counts['unscoredEmissions'],
            'hypotheticalProductionCostUSD': sum(m['costUSD'] or 0 for m in gate_meta + label_meta),
            'medianGateSeconds': median(m['seconds'] for m in gate_meta),
            'medianLabelSecondsForAdmitted': median(m['seconds'] for m in label_meta) if label_meta else None,
            'medianProductionPathSeconds': median(deployment_times),
        }

    actual_metas = []
    changes = Counter()
    for row in results.values():
        for variant, value in row['variants'].items():
            if not value['identicalEvidenceReused']:
                changes[variant] += 1
                actual_metas.append(value['gate']['meta'])
                if value['labelDecision']:
                    actual_metas.append(value['labelDecision']['meta'])
    return {
        'variants': stats,
        'references': {
            'scopes': dict(Counter(r['expected'] for r in references)),
            'positiveLabelChecks': sum(len(r['yes']) for r in references),
            'negativeLabelChecksOnKnownDestinations': sum(len(r['no']) for r in references if r['expected'] == 'include'),
            'negativeLabelChecksEndToEnd': sum(len(r['no']) for r in references),
        },
        'changedEvidenceByVariant': dict(changes),
        'successfulModelRequests': len(actual_metas),
        'modelVersions': sorted({m['model'] for m in actual_metas}),
        'inputTokens': sum(m['inputTokens'] or 0 for m in actual_metas),
        'reportedModelCostUSD': sum(m['costUSD'] or 0 for m in actual_metas),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    directory = args.directory
    reference = directory / 'reference.json'
    rows = baseline.load(reference)['cases']
    if len(rows) != 60 or len({r['id'] for r in rows}) != len(rows):
        parser.error('Expected 60 unique frozen reference places')
    taxonomy_path = ROOT / 'catalog/place-labels.json'
    tax = baseline.load(taxonomy_path)
    types = {label: definition for group in tax['types'].values() for label, definition in group.items()}
    _, definitions, parents = jev.taxonomy()
    sources = {r['id']: SOURCES[r['batch']] / (r['id'] + '.json') for r in rows}
    places = {pid: baseline.load(path)['place'] for pid, path in sources.items()}
    for row in rows:
        pid = row['id']
        if places[pid]['id'] != pid or row['name'] != places[pid]['displayName']['text']:
            parser.error('Reference identity mismatch')
        if row['expected'] not in scope.ELIGIBILITY_CRITERIA or (set(row['yes']) | set(row['no'])) - definitions.keys() or set(row['yes']) & set(row['no']):
            parser.error('Invalid reference judgment')

    manifest = {
        'referenceHash': baseline.fingerprint(reference),
        'taxonomyHash': baseline.fingerprint(taxonomy_path),
        'sourceHashes': {pid: baseline.fingerprint(path) for pid, path in sources.items()},
        'scriptHashes': {Path(file).name: baseline.fingerprint(Path(file))
                         for file in (__file__, scope.__file__, baseline.__file__, jev.__file__)},
        'variants': VARIANTS,
        'model': jev.MODEL,
        'gateCutoff': scope.GATE_CUTOFF,
        'labelCutoff': jev.THRESHOLD,
        'requestCap': 540,
    }
    scope.REQUEST_CAP = manifest['requestCap']
    key = credentials().get('OPENROUTER_API_KEY')
    if not key:
        parser.error('OpenRouter key is missing')
    with (directory / 'run.lock').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        path = directory / 'manifest.json'
        if path.exists() and baseline.load(path) != manifest:
            parser.error('Frozen experiment inputs changed')
        if not path.exists():
            jev.write_json(path, manifest)
        for folder in ('scope', 'labels'):
            (directory / folder).mkdir(exist_ok=True)
        campaign = scope.Campaign(directory, key)
        started = time.monotonic()
        # Exercise all four conditions on one record before starting the remaining batch.
        first = rows[0]
        result = run_case(first, places[first['id']], campaign, types, definitions, parents)
        results = {first['id']: result}
        print('Preflight passed', flush=True)
        failures = {}
        with ThreadPoolExecutor(max_workers=8) as executor:
            futures = {executor.submit(run_case, r, places[r['id']], campaign, types, definitions, parents): r['id']
                       for r in rows[1:]}
            for future in as_completed(futures):
                pid = futures[future]
                try:
                    results[pid] = future.result()
                except (ValueError, RuntimeError) as error:
                    failures[pid] = str(error)
                if (len(results) + len(failures)) % 10 == 0:
                    print(f'{len(results)}/{len(rows)} completed, {len(failures)} failed', flush=True)
        jev.write_json(directory / 'failures.json', failures)
        if failures:
            raise SystemExit('Incomplete experiment. Successful requests can be resumed from checkpoints.')
        if manifest['referenceHash'] != baseline.fingerprint(reference) or any(
                manifest['sourceHashes'][pid] != baseline.fingerprint(path) for pid, path in sources.items()):
            raise SystemExit('Evidence or reference changed during the run.')
        summary = summarize(rows, results)
        summary['wallSecondsThisInvocation'] = time.monotonic() - started
        summary['attemptedModelRequests'] = baseline.load(directory / 'usage.json')['attempts']
        summary['googleRequests'] = 0
        jev.write_json(directory / 'results.json', results)
        jev.write_json(directory / 'summary.json', summary)


if __name__ == '__main__':
    main()
