#!/usr/bin/env python3
"""Independently audit exported benchmark artifacts and summarize observations."""
import argparse
import base64
import csv
import hashlib
import json
import statistics
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


def read(path):
    return json.loads(path.read_text())


def instant(text):
    return datetime.fromisoformat(text.replace('Z', '+00:00'))


def audit(root):
    status = read(root / 'status.json')
    matrix = read(root / 'matrix.json')
    assert status['complete'], 'Run has not completed'
    assert len(matrix) == len(status['results']) == 17, 'Missing or additional cases'
    assert len({r['id'] for r in status['results']}) == 17
    replay = 'replay' in status['evidence'].lower()
    rows = []
    issues = []
    for result, spec in zip(status['results'], matrix):
        assert result['id'] == spec['id'], 'Execution order differs from frozen matrix'
        assert result == read(root / f"{result['id']}-result.json")
        row = {k: result[k] for k in ['id', 'family', 'cacheCondition', 'expected',
                                    'observed', 'passed', 'seconds', 'requestedCount', 'stopCount',
                                    'embeddingPresent', 'cachedWeatherGroups', 'thermalBefore', 'thermalAfter']}
        row.update(eta_requests=0, search_requests=0, weather_fetches=0,
                   routing_seconds=0, preferences_seconds=0, search_seconds=0,
                   weather_seconds=0, provider_responses=0, eta_cache_hits=0,
                   candidates=0, provider_errors=0, pacing_estimate_seconds=0,
                   assessment='pass' if result['passed'] else 'fail')
        path = root / f"{result['id']}-plan.json"
        if path.exists():
            plan = read(path)
            raw = json.loads(base64.b64decode(plan['rawRoutingReport']))
            metrics = {m['stage']: m for m in plan['metrics']}
            ids = plan['prepared']['selectedIDs']
            assert set(ids) == set(spec['request']['requiredCandidateIDs']), result['id']
            assert len(set(ids)) == len(ids)
            assert plan['evidenceMode'] == ('synthetic_replay' if replay else 'live')
            assert bool(raw.get('simulationKind')) == replay
            assert metrics['mapkit_eta']['requests'] == raw['requests']
            assert metrics['mapkit_search']['requests'] == len(ids) + 1
            assert result['embeddingPresent'] == bool(plan['quality'].get('embedding'))
            row.update(eta_requests=raw['requests'],
                       search_requests=metrics['mapkit_search']['requests'],
                       weather_fetches=metrics['weather_groups']['requests'],
                       routing_seconds=metrics['mapkit_eta']['seconds'],
                       preferences_seconds=metrics['preferences']['seconds'],
                       search_seconds=metrics['mapkit_search']['seconds'],
                       weather_seconds=metrics['weather_groups']['seconds'],
                       candidates=len(raw['candidates']), optimizer=raw.get('optimizerNote', ''))
            stage_sum = sum(metrics[s]['seconds'] for s in
                            ['preferences', 'mapkit_search', 'weather_groups', 'mapkit_eta'])
            assert stage_sum <= result['seconds'] + 0.1, (result['id'], stage_sum, result['seconds'])
            all_logs = [json.loads(line) for line in base64.b64decode(plan.get('providerLog', '')).splitlines()]
            # A reused production pipeline snapshots its retained log directory, which
            # also contains previous routing services. Audit only this last completed
            # session rather than incorrectly adding earlier provider calls.
            completed = [e for e in all_logs if e['event'] == 'routing.pipeline_completed']
            assert completed, 'Missing completed routing session'
            session = completed[-1]['sessionID']
            log = [e for e in all_logs if e['sessionID'] == session]
            counts = Counter(event['event'] for event in log)
            row['provider_responses'] = counts['eta.provider_response']
            row['eta_cache_hits'] = sum(e['event'] == 'eta.result' and e['fields'].get('source') == 'cache' for e in log)
            row['provider_errors'] = sum(e['event'] == 'eta.result' and e['fields'].get('source') == 'provider'
                                         and e['fields'].get('status') != 'available' for e in log)
            row['pacing_estimate_seconds'] = 0 if replay else max(0, raw['requests'] - 1) * 1.2
            # This is a pacing floor estimate under continuously queued sequential work,
            # not a measurement of SDK time or an exact additive decomposition.
            if not replay and result['passed']:
                if result['observed'] == 'ready':
                    # Unsuccessful alternative requests may coexist with a fully
                    # provider-validated final candidate. Account for both, then
                    # independently validate every returned leg below.
                    assert counts['eta.provider_response'] + row['provider_errors'] == raw['requests'], (result['id'], counts, raw['requests'])
                elif result['expected'] == 'conflicted' and any('Data transportasi belum cukup' in c for c in plan['conflicts']):
                    # A generic "conflicted" result caused by missing ETA does not
                    # establish that the app detected the intended deadline violation.
                    row['assessment'] = 'inconclusive_provider_failure'
                assert all(w['provider'] == 'weatherkit' and w['status'] == 'available' and w.get('credit') for w in plan['weather'])
            if plan['status'] == 'ready':
                assert not plan['conflicts'] and len(plan['stops']) == result['requestedCount']
                assert set(s['id'] for s in plan['stops']) == set(ids)
                assert len(plan['legs']) == len(ids) + 1
                assert instant(plan['finish']) <= instant(plan['request']['deadline'])
                assert all(l['providerStatus'] == 'available' and l['seconds'] >= 0 for l in plan['legs'])
                for stop in plan['stops']:
                    arrival, visit, leave = map(instant, [stop['arrival'], stop['visit'], stop['leave']])
                    assert arrival <= visit < leave
                    assert (leave - visit).total_seconds() == stop['duration'] * 60
                    assert stop['duration'] == plan['request']['durationByVenue'].get(stop['venueID'], plan['request']['defaultDuration'])
                    local = visit.astimezone(ZoneInfo('Asia/Jakarta'))
                    minute = local.hour * 60 + local.minute
                    assert minute % 15 == local.second == 0
                    timing = next(t for t in plan['timing'] if t['venue']['id'] == stop['venueID'])
                    assert any(r['start'] <= minute <= r['end'] for r in timing['validStartRanges'])
            elif plan['status'] == 'conflicted':
                assert plan['conflicts'], 'Conflict output must state its reason'
            if result['id'] == 'REV5' and result['passed']:
                baseline = read(root / 'N5-R3-plan.json')
                assert plan['baseAcceptedID'] == baseline['id']
                stop = baseline['stops'][-1]
                assert plan['request']['durationByVenue'][stop['venueID']] == stop['duration'] + 30
        else:
            review_path = root / f"{result['id']}-recommendation.json"
            if review_path.exists():
                review = read(review_path)
                row['preferences_seconds'] = review['quality']['elapsedSeconds']
            if result['observed'] == 'needsPlaces':
                assert not (root / f"{result['id']}-locations.json").exists()
                assert set(spec['request']['requiredCandidateIDs']).issubset(result['selectedIDs'])
        if row['assessment'] != 'pass':
            issues.append({'id': result['id'], 'observed': result['observed'],
                           'assessment': row['assessment'], 'detail': result['detail']})
        rows.append(row)
    families = defaultdict(list)
    for row in rows:
        families[row['family']].append(row)
    summary = {
        'evidence': status['evidence'], 'complete': status['complete'],
        'count': len(rows), 'passed': sum(r['assessment'] == 'pass' for r in rows),
        'harness_passed': sum(r['passed'] for r in rows), 'issues': issues,
        'families': {name: {
            'n': len(group), 'passed': sum(r['passed'] for r in group),
            'seconds': [r['seconds'] for r in group],
            'min': min(r['seconds'] for r in group),
            'median': statistics.median(r['seconds'] for r in group),
            'max': max(r['seconds'] for r in group),
            'eta_requests': [r['eta_requests'] for r in group],
            'observed': [r['observed'] for r in group],
        } for name, group in families.items()},
        'rows': rows,
        'limits': ['Three fixed-order observations per N family, not a p95/SLA.',
                   'Fresh pipeline does not mean empty OS/provider caches.',
                   'Different destination sets/departures are not a count-only comparison.',
                   'Replay wall times do not measure live provider latency.'],
    }
    (root / 'analysis.json').write_text(json.dumps(summary, indent=2) + '\n')
    fields = sorted(set().union(*(r.keys() for r in rows)))
    with (root / 'metrics.csv').open('w') as file:
        writer = csv.DictWriter(file, fields)
        writer.writeheader(); writer.writerows(rows)
    print(json.dumps({k: summary[k] for k in ['evidence', 'count', 'passed', 'issues', 'families']}, indent=2))
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('run', type=Path)
    args = parser.parse_args()
    audit(args.run)
