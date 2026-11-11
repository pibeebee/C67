#!/usr/bin/env python3
"""Summarize raw and objective-only checks without inventing human grades."""
import collections
import json
import math
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
PACKAGE = Path('/Users/neuhendra/Downloads/foundation-models-evaluation-2026-11-04')
preflight = json.loads((HERE / 'manifest.json').read_text())['runtimePreflight']
if preflight['id_ID'] is not False or preflight['en_US'] is not True:
    raise SystemExit('This summary is specific to id_ID unsupported / en_US supported; adapt it for this device.')
cases = [json.loads(line) for line in (PACKAGE / 'inputs.jsonl').read_text().splitlines()]
oracles = {x['id']: x for x in map(json.loads, (PACKAGE / 'evaluator-only.jsonl').read_text().splitlines())}
runs = [json.loads(line) for line in (HERE / 'assessed-runs.jsonl').read_text().splitlines()]


def latency(records):
    values = sorted(r['wallSeconds'] for r in records if r['result']['outcome'] == 'response')
    if not values:
        return None
    return {'nResponses': len(values), 'p50Seconds': round(statistics.median(values), 3),
            'p90NearestRankSeconds': values[math.ceil(.9 * len(values)) - 1], 'maxSeconds': max(values)}


primary = [r for r in runs if r['phase'] == 'primary']
diagnostic = [r for r in runs if r['phase'] in ('development-diagnostic', 'evaluation-diagnostic')]
response_primary = [r for r in primary if r['result']['outcome'] == 'response']
offline = json.loads((HERE / 'offline-both-control.json').read_text())
first_action = lambda r: (r['result'].get('parsedFields', {}).get('actions') or [{}])[0]
summary = {'plannedCases': 32, 'plannedRepeatsPerCase': 10, 'plannedRunsIfAllEligible': 320,
           'localeEligibleCases': 1, 'localeBlockedCases': 31, 'blockedPlannedRuns': 310,
           'primaryAttempted': len(primary), 'primaryResponses': len(response_primary),
           'primaryTimeouts': sum(r['result']['outcome'] == 'timeout' for r in primary),
           'primarySchemaValidAttempted': sum(r['schemaValid'] for r in primary),
           'primaryIntentAllFieldsExactAttempted': sum(r['assessment']['objectiveChecks'].get('actionsExact') is True for r in primary),
           'primaryTypeTargetMinutesCorrectResponses': sum(first_action(r).get('type') == 'extend_current_visit'
                and first_action(r).get('targetID') == 'B' and first_action(r).get('minutes') == 30 for r in response_primary),
           'primaryLatencyM1ResponseOnly': latency(primary),
           'primaryMaxObservedIncludingTimeoutSeconds': max(r['wallSeconds'] for r in primary),
           'primaryDistinctCanonicalResponses': len({json.dumps(r['result']['parsedFields'], sort_keys=True) for r in response_primary}),
           'indonesianDiagnosticAttempted': len(diagnostic),
           'indonesianDiagnosticResponses': sum(r['result']['outcome'] == 'response' for r in diagnostic),
           'indonesianDiagnosticTimeouts': sum(r['result']['outcome'] == 'timeout' for r in diagnostic),
           'indonesianDiagnosticSchemaValid': sum(r['schemaValid'] for r in diagnostic),
           'indonesianDiagnosticM1ResponseOnly': latency([r for r in diagnostic if r['mode'] == 'M1']),
           'indonesianDiagnosticM2ResponseOnly': latency([r for r in diagnostic if r['mode'] == 'M2']),
           'indonesianDiagnosticToolCases': sum(r['mode'] == 'M2' for r in diagnostic),
           'indonesianDiagnosticActualToolCalls': sum(r['toolCalls'] for r in diagnostic),
           'indonesianDiagnosticObjectiveFailures': sum(r['assessment']['semanticGrade'] == 'objective_failure' for r in diagnostic),
           'indonesianDiagnosticObjectiveChecksOnlyPendingHuman': sum(r['assessment']['semanticGrade'] == 'pending_two_human_reviewers' for r in diagnostic),
           'separateOfflineControlRuns': len(offline.get('runs', [])),
           'separateOfflineControlCases': [r['caseID'] for r in offline.get('runs', [])],
           'humanReviewers': 0, 'unverifiedSemanticAccuracy': True,
           'indonesianSupport': 'blocked by SystemLanguageModel.supportsLocale(id_ID) == false',
           'latencyCaveat': 'Mac process/session per run, mixed warm/cold unknown; repeated greedy outputs are not independent.'}
(HERE / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')

by_id = {r['caseID']: r for r in diagnostic}
lines = ['# Case disposition', '',
         'Main Indonesian cases are blocked by the runtime language-support gate. Diagnostic observations do not count as supported-product passes. “Pending human review” only means the automated checks did not establish a failure; it is not a pass. The separate offline control repeated LANG-01 and TOOL-01 once each; those two controls are not included in the counts below.', '',
         '| Case | Group / split | Main outcome | Diagnostic or objective observation |',
         '| --- | --- | --- | --- |']
for case in cases:
    case_id = case['id']
    if case_id == 'LANG-01':
        observation = (f"{len(primary)} attempts; {summary['primaryTimeouts']} timeout; "
                       f"{summary['primaryIntentAllFieldsExactAttempted']}/{len(primary)} exact action fields")
        status = 'Failed'
    else:
        r = by_id[case_id]
        a = r['assessment']
        if r['result']['outcome'] == 'timeout':
            observation = '1 diagnostic timeout'
        elif a['objectiveFailures']:
            observation = '1 diagnostic: ' + ', '.join(a['objectiveFailures'])
        else:
            observation = '1 diagnostic: objective checks only; human review pending'
        status = 'Blocked: id_ID unsupported'
    title = oracles[case_id]['title'].replace('|', '\\|')
    lines.append(f"| {case_id} — {title} | {case['family']} / {case['split']} | {status} | {observation} |")
(HERE / 'case-status.md').write_text('\n'.join(lines) + '\n')
print(json.dumps(summary, indent=2))
