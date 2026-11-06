#!/usr/bin/env python3
"""Paired replay: real committed full hybrid versus the adaptive working tree.
Reuses the independent itinerary auditor and original 22 cases, plus new seeds.
No network, weather, provider pacing or iPhone latency measurement.
"""
import argparse
import csv
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import platform
import statistics
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['root', 'committed-root', 'full', 'adaptive', 'output']:
        p.add_argument('--' + name, required=True, type=Path)
    p.add_argument('--baseline', required=True)
    args = p.parse_args()
    spec = importlib.util.spec_from_file_location('reference', args.root / 'scripts/benchmark-routing-pipeline.py')
    ref = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ref)
    cases = [ref.recorded(args.root)] + [ref.synthetic(n, g, d) for n in [4, 8, 12, 20]
                                        for g in [17, 73] for d in [False, True]]
    cases += [ref.synthetic(n, g, True, tight=True) for n in [8, 12] for g in [17, 73]]
    impossible = ref.synthetic(4, 91, False)
    impossible['id'] = 'synthetic-known-infeasible'
    impossible['kind'] = 'synthetic_infeasible'
    impossible['draft']['stops'][0]['opening'].update(opensMinute=420, closesMinute=421)
    cases.append(impossible)
    for case in cases:
        case['suite'] = 'original'
    for n in [4, 6, 10]:
        for g in [103, 149]:
            for dynamic in [False, True]:
                case = ref.synthetic(n, g, dynamic)
                case['suite'] = 'additional'
                if g == 103:
                    for stop in case['draft']['stops']:
                        stop.pop('opening', None)
                    case['id'] += '-no-windows'
                cases.append(case)
    # Fresh geometry seeds after the first iteration, with softer opening windows.
    # Their role and the fact that policy was revised are retained in the report.
    for n in [4, 6]:
        for g in [211, 307]:
            for dynamic in [False, True]:
                case = ref.synthetic(n, g, dynamic)
                case['suite'] = 'fresh'
                for i, stop in enumerate(case['draft']['stops']):
                    stop['opening']['opensMinute'] = 480 + (i % 3) * 15
                case['id'] += '-soft-windows'
                cases.append(case)
    for label in ['central-two', 'north-two', 'one-stop']:
        case = ref.recorded(args.root)
        # Explicit location IDs keep these subsets stable if input order changes.
        ids = {
            'central-two': {'0CE4F07E-E3A7-467F-A0F1-D4C715AC6FBE', 'E32284F7-2A9E-4739-9991-4A086BB990DF'},
            'north-two': {'106E65CA-64AA-4292-9D96-DED708AF9D94', 'BF2C3EFA-9309-4E4D-A550-2DE23C235AFC'},
            'one-stop': {'0CE4F07E-E3A7-467F-A0F1-D4C715AC6FBE'},
        }[label]
        case['draft']['stops'] = [s for s in case['draft']['stops'] if s['point']['id'] in ids]
        case['id'] = 'jakarta-' + label
        case['suite'] = 'small'
        cases.append(case)
    out = args.output
    (out / 'cases').mkdir()
    names = ['NativeTripModels', 'NativeTripWeatherSupport', 'NativeTripRoutingCore',
             'NativeTripEngine', 'NativeTripRoutingBridge', 'NativeTripTimeAwarePlanner']
    sources = {}
    for name in names:
        path = 'poc-c67/Features/NativePlanner/' + name + '.swift'
        sources[path] = dict(adaptive=hashlib.sha256((args.root / path).read_bytes()).hexdigest(),
                             full=hashlib.sha256(subprocess.check_output(
                                 ['git', '-C', str(args.committed_root), 'show', args.baseline + ':' + path])).hexdigest())
    for path in ['scripts/benchmark-adaptive-routing.sh', 'scripts/benchmark-adaptive-routing.py',
                 'scripts/benchmark-routing-pipeline.py', 'checks/routing/NativeTripPipelineReplay.swift']:
        sources[path] = dict(sha256=hashlib.sha256((args.root / path).read_bytes()).hexdigest())
    ref.write(out / 'manifest.json', dict(baselineCommit=args.baseline, sources=sources,
        platform=platform.platform(), swift=subprocess.check_output(['xcrun', 'swiftc', '--version'], text=True).strip(),
        originalCases=22, additionalCases=12, freshCases=8, smallCases=3, seeds=ref.SEEDS, requestLimit=96, evaluationLimit=12000,
        secondsLimit=3, network=False, weather=False,
        method='Actual committed full pipeline versus adaptive sources, same oracle/seed/budgets, cold cache, interleaved arms. Additional seeded cases are generated after policy design; not independent external validation.',
        caseSHA256={c['id']: hashlib.sha256(json.dumps(c, sort_keys=True).encode()).hexdigest() for c in cases}))
    runs = []
    rows = []
    references = {}
    with (out / 'runs.jsonl').open('w') as stream:
        for ci, case in enumerate(cases):
            path = out / 'cases' / (case['id'] + '.json')
            ref.write(path, case)
            if len(case['draft']['stops']) <= 6:
                evaluate = ref.scorer(case)
                feasible = [e for order in itertools.permutations([s['point']['id'] for s in case['draft']['stops']])
                            if (e := evaluate(list(order))) and e['feasible']]
                references[case['id']] = min(e['elapsed'] for e in feasible) if feasible else None
            for si, seed in enumerate(ref.SEEDS):
                arms = [('full-hybrid', args.full, 'default'), ('adaptive-hybrid', args.adaptive, 'default'),
                        ('baseline', args.adaptive, 'baseline')]
                if (ci + si) % 2:
                    arms.reverse()
                for system, binary, algorithm in arms:
                    proc = subprocess.run([str(binary), str(path), algorithm, str(seed)],
                                          capture_output=True, text=True, timeout=60, check=True)
                    run = json.loads(proc.stdout)
                    if 'error' in run:
                        raise AssertionError((case['id'], system, run['error']))
                    run.update(system=system, suite=case['suite'], n=len(case['draft']['stops']))
                    ref.validate(case, run)
                    chosen = run.get('selected')
                    complete = [c for c in run['candidates'] if c['feasible']]
                    if chosen and chosen['feasible'] and complete:
                        assert chosen['elapsed'] <= min(c['elapsed'] for c in complete) + .01
                    decisions = [e['fields'] for e in run['events'] if e['name'] == 'routing.adaptive_decision']
                    decision = decisions[-1] if decisions else {}
                    evaluations = sum(s['evaluations'] for s in run['solvers']) + int(decision.get('screeningEvaluations', 0))
                    assert evaluations <= 12000
                    runs.append(run)
                    stream.write(json.dumps(run, allow_nan=False) + '\n')
                    stream.flush()
                    rows.append(dict(case=case['id'], suite=case['suite'], n=run['n'], seed=seed,
                        system=system, feasible=bool(chosen and chosen['feasible']),
                        elapsedMinutes=chosen['elapsed']/60 if chosen and chosen['feasible'] else None,
                        travelMinutes=chosen['travel']/60 if chosen and chosen['feasible'] else None,
                        waitingMinutes=chosen['waiting']/60 if chosen and chosen['feasible'] else None,
                        requests=run['requests'], wallSeconds=run['wallSeconds'], evaluations=evaluations,
                        decision=decision.get('reason'), optimized=decision.get('optimize')))
            print(f'{ci + 1}/{len(cases)} {case["id"]}: audited', flush=True)
    ref.write(out / 'references.json', references)
    with (out / 'metrics.csv').open('w') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    by = {(r['case'], r['seed'], r['system']): r for r in rows}
    def compare(suite):
        pairs = [(by[c['id'], seed, 'full-hybrid'], by[c['id'], seed, 'adaptive-hybrid'])
                 for c in cases if suite == 'all' or c['suite'] == suite for seed in ref.SEEDS]
        both = [(a, b) for a, b in pairs if a['feasible'] and b['feasible']]
        delta = [b['elapsedMinutes'] - a['elapsedMinutes'] for a, b in both]
        request_delta = [b['requests'] - a['requests'] for a, b in pairs]
        return dict(pairs=len(pairs), fullFeasible=sum(a['feasible'] for a, b in pairs),
            adaptiveFeasible=sum(b['feasible'] for a, b in pairs), bothFeasible=len(both),
            faster=sum(d < -.0002 for d in delta), tied=sum(abs(d) <= .0002 for d in delta),
            slower=sum(d > .0002 for d in delta), medianElapsedDeltaMinutes=statistics.median(delta),
            maxElapsedRegressionMinutes=max([0] + delta),
            requestsSaved=-sum(request_delta), fullRequests=sum(a['requests'] for a, b in pairs),
            requestSavingsPercent=(1-sum(b['requests'] for a,b in pairs)/sum(a['requests'] for a,b in pairs))*100,
            fewerRequests=sum(d < 0 for d in request_delta), sameRequests=sum(d == 0 for d in request_delta),
            moreRequests=sum(d > 0 for d in request_delta),
            regressions=[dict(case=a['case'], seed=a['seed'], full=a['elapsedMinutes'],
                adaptive=b['elapsedMinutes'], reason=b['decision']) for a, b in both
                if b['elapsedMinutes'] > a['elapsedMinutes'] + .0002])
    aggregate = {}
    for system in ['full-hybrid', 'adaptive-hybrid', 'baseline']:
        part = [r for r in rows if r['system'] == system]
        aggregate[system] = dict(runs=len(part), feasible=sum(r['feasible'] for r in part),
            medianRequests=statistics.median(r['requests'] for r in part),
            medianWallMilliseconds=statistics.median(r['wallSeconds'] for r in part)*1000,
            skipped=sum(r['optimized'] == 'false' for r in part))
    summary = dict(cases=len(cases), runs=len(runs), auditErrors=0, aggregate=aggregate,
                   comparisons={suite: compare(suite) for suite in ['original', 'additional', 'fresh', 'small', 'all']},
                   jakarta=[r for r in rows if r['case'] == 'jakarta-recorded-static' and r['seed'] == 67])
    ref.write(out / 'summary.json', summary)
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
