#!/usr/bin/env python3
"""Opt-in provider campaign, explicit replay, or HTTP-only recommendation timing.

Do not run until the user releases the testing hold. No mode silently falls back
to invented model results. Evaluator expectations never enter model requests.
"""
import argparse
import json
import statistics
import time
import urllib.request
from pathlib import Path

from catalog_engine import LABELS, LABEL_RULE_VERSION, ROOT, config, digest, literal_label, source_guarded_label, utcnow
from catalog_fixtures import probes

OUT = ROOT / 'artifacts/catalog-2026-11-10'


def metrics(rows, method, split=None):
    total = correct = unsafe = decisive = answered = justified = failures = 0
    for row in rows:
        if split and row['split'] != split:
            continue
        predictions = row[method]
        for key, truth in row['expected'].items():
            predicted = predictions.get(key, 'unavailable')
            total += 1
            correct += predicted == truth
            unsafe += predicted == 'supported' and truth != 'supported'
            decisive += truth != 'unknown'
            answered += predicted in ['supported', 'contradicted']
            justified += predicted == truth and truth != 'unknown'
            failures += predicted == 'unavailable'
    return {'labels': total, 'correct': correct, 'accuracy': correct / total if total else None,
            'unsupportedPositive': unsafe, 'decisiveTruths': decisive, 'decisiveAnswers': answered,
            'decisiveCorrect': justified, 'decisiveRecall': justified / decisive if decisive else None,
            'unavailable': failures, 'abstentionShare': (total - answered - failures) / total if total else None}


def summarize(rows):
    methods = ['literal', 'llm', 'anyjevRaw', 'anyjevL0', 'sourceAndLLM', 'combined']
    return {split: {method: metrics(rows, method, None if split == 'all' else split) for method in methods}
            for split in ['all', 'development', 'holdout']}


def live(output):
    from catalog_models import AnyJevJudge, enrich
    from catalog_llm import CatalogLLMClient
    from server import curl_json
    client = CatalogLLMClient(curl_json)
    if not client.status()['configured']:
        raise SystemExit('API key pending. No provider calls were made.')
    cases = probes()
    cfg = config()
    judge = AnyJevJudge(cfg)
    rows = []
    for case in cases:
        venue = case['venue']
        enriched = enrich(venue, cfg, client.complete, judge, ROOT / '.local/catalog-cache')
        raw, raw_seconds = judge.judge(venue, raw=True)
        proposal = enriched['proposal']
        literal = {key: literal_label(venue, key)[0] for key in LABELS}
        llm = {key: proposal[key]['status'] if proposal else 'unavailable' for key in LABELS}
        source_llm = {key: source_guarded_label(venue, key, proposal.get(key))['status']
                      if proposal else 'unavailable' for key in LABELS}
        row = {'id': case['id'], 'split': case['split'], 'expected': case['expected'],
               'literal': literal, 'llm': llm, 'sourceAndLLM': source_llm,
               'anyjevRaw': {key: raw[key]['answer'] for key in LABELS},
               'anyjevL0': {key: enriched['judge'][key]['answer'] for key in LABELS},
               'combined': {key: enriched['labels'][key]['status'] if proposal else 'unavailable' for key in LABELS},
               'rawDecisions': raw, 'enriched': enriched, 'rawJudgeSeconds': raw_seconds}
        rows.append(row)
        checkpoint = {'createdAt': utcnow(), 'fixtureHash': digest(cases), 'config': cfg,
                      'labelRuleVersion': LABEL_RULE_VERSION,
                      'judge': judge.metadata, 'rows': rows, 'summary': summarize(rows),
                      'complete': len(rows) == len(cases), 'limitations': 'Authored evidence-policy probes, no human venue-fit validation.'}
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(checkpoint, ensure_ascii=False, indent=2))
        print(json.dumps({'case': case['id'], 'llmMode': enriched['inference']['llm']['mode'],
                          'cacheHit': enriched['cacheHit']}, ensure_ascii=False), flush=True)
        if proposal is None:
            raise SystemExit('Provider failure retained. Campaign stopped without fabricating results.')


def http_benchmark(output):
    connection = json.loads((ROOT / '.local/connection.json').read_text())
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def attempt_counters():
        paths = list((ROOT / '.local').glob('*usage*.json'))
        return {p.name: json.loads(p.read_text()).get('attempts', 0) for p in paths}
    counters_before = attempt_counters()
    scenarios = [
        ('broad-reading', ['reading'], {}, {}),
        ('read-own', ['reading'], {'readingActivity': {'value': 'onsite', 'must': True}}, {}),
        ('buy-books', ['reading'], {'readingActivity': {'value': 'buy', 'must': True}}, {}),
        ('coffee-reading', ['reading', 'coffee'], {
            'readingActivity': {'value': 'onsite', 'must': True}, 'coffeeRelation': {'value': 'together', 'must': True}}, {}),
        ('separate-activities', ['reading', 'coffee'], {
            'readingActivity': {'value': 'onsite', 'must': True}, 'coffeeRelation': {'value': 'separate', 'must': True}}, {}),
        ('dated-duration', ['reading'], {'readingActivity': {'value': 'buy', 'must': True}},
            {'visitAt': '2026-11-11T04:00:00Z', 'durationMinutes': 90}),
        ('unsupported-need', ['reading'], {'readingActivity': {'value': 'onsite', 'must': True},
            'walking': {'value': 'low', 'must': True}}, {}),
        ('outside-scope', ['reading'], {'readingActivity': {'value': 'onsite', 'must': True}}, {'area': 'Jakarta Selatan'}),
    ]
    observations = []
    for name, interests, needs, extra in scenarios:
        for repetition in range(5):
            body = {'requestID': '10000000-0000-0000-0000-000000000000', 'revision': 1,
                    'interests': interests, 'needs': needs, 'area': config()['area']}
            body.update(extra)
            req = urllib.request.Request(connection['baseURL'] + '/catalog/discover',
                data=json.dumps(body).encode(), headers={'Authorization': 'Bearer ' + connection['token'], 'Content-Type': 'application/json'})
            started = time.monotonic()
            with opener.open(req, timeout=10) as response:
                value = json.load(response)
            if not value['runID']:
                raise SystemExit('No active catalogue. Empty readiness results are not a benchmark.')
            if name == 'outside-scope' and (value['places'] or not value['warnings']):
                raise SystemExit('Scope boundary was not respected.')
            if name in ['dated-duration', 'unsupported-need'] and any(p['status'] == 'supported' for p in value['places']):
                raise SystemExit('An unsupported visit requirement was incorrectly certified.')
            observations.append({'scenario': name, 'repeat': repetition, 'clientSeconds': time.monotonic() - started,
                                 'serverSeconds': value['seconds'], 'count': len(value['places']),
                                 'supported': sum(v['status'] == 'supported' for v in value['places']),
                                 'excludedCount': value['excludedCount'], 'runID': value['runID']})
    timings = [r['clientSeconds'] for r in observations]
    counters_after = attempt_counters()
    if len({r['runID'] for r in observations}) != 1:
        raise SystemExit('Catalogue changed during timing. Results cannot be pooled.')
    report = {'createdAt': utcnow(), 'observations': observations, 'medianClientSeconds': statistics.median(timings),
              'p95ClientSeconds': sorted(timings)[int(.95 * (len(timings) - 1))],
              'firstClientSeconds': timings[0],
              'countedProviderAttemptsDuringRecommendations': sum(
                  counters_after.get(k, 0) - counters_before.get(k, 0)
                  for k in counters_before.keys() | counters_after.keys()),
              'providerCountersBefore': counters_before, 'providerCountersAfter': counters_after,
              'timingMeaning': 'Loopback HTTP plus catalogue matching. Excludes offline preparation and UI rendering. Not routing latency.'}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--live', action='store_true')
    mode.add_argument('--replay', type=Path)
    mode.add_argument('--http', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.live:
        live(args.output or OUT / 'controlled.json')
    elif args.http:
        http_benchmark(args.output or OUT / 'http.json')
    else:
        report = json.loads(args.replay.read_text())
        if report['fixtureHash'] != digest(probes()) or report.get('labelRuleVersion') != LABEL_RULE_VERSION or not report.get('complete'):
            raise SystemExit('Fixture/policy mismatch or incomplete campaign. Replay refused.')
        result = {'source': str(args.replay), 'summary': summarize(report['rows']),
                  'historicalLatencyRemeasured': False}
        if args.output:
            args.output.write_text(json.dumps(result, indent=2))
        else:
            print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
