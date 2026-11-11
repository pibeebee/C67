#!/usr/bin/env python3
"""Post-run single-review dispositions. Not imported by or sent to the model."""
import json
from pathlib import Path
from guards import render_fact, validate_intent

HERE = Path(__file__).resolve().parent
NOTES = {
    'extend': (True, 'Exact extension intent, target and duration; no extra fields.'),
    'negation': (False, 'Wrong intent and target; requested skip D only.'),
    'correction': (False, '15 minutes at B, but invented proposal ID and unnecessary question.'),
    'deadline': (False, '10:30 is present, but intent is extend with extraneous duration.'),
    'ambiguity': (False, 'Skipped D rather than clarify the ambiguous reference.'),
    'preferences': (True, 'Coffee, reading and quiet all captured.'),
    'golden': (True, 'Correct distinction and evidence.'),
    'weather': (True, 'Correct probability, uncertainty and evidence.'),
    'route': (True, 'Correct arrival, deadline and evidence.'),
    'recommend': (False, 'P1 and its tradeoff are supported, but comparative P2 facts omit E-P2 citation.'),
    'unknown': (False, 'Message acknowledges unknown access, but candidateID is literal string null, not absent or JSON null.'),
    'stale': (False, 'Proposed apply on an invalid old proposal.'),
    'new-extend': (True, 'Exact extension intent, target and duration.'),
    'new-negation': (False, 'C selected, but extraneous time, duration, proposal string and question.'),
    'new-ambiguous': (False, 'Unresolved question accompanied by a skip action and invented fields.'),
    'new-deadline': (False, '11:15 is present, but intent is extend and duration is invented.'),
    'tool-weather': (False, 'Correct tool and arguments, but says 69.99% while fixture says 0.7 (70%).'),
    'tool-search': (True, 'Correct tool and arguments, returned result and unknowns with source.'),
    'tool-unavailable': (True, 'Correct tool and arguments, reported unavailable and stopped after one call.'),
}
TEMPLATE_FACTS = [
    {'kind': 'weather', 'stop': 'C', 'probability': 60, 'evidenceID': 'E-WEATHER'},
    {'kind': 'route', 'arrival': '11:40', 'deadline': '12:00', 'evidenceID': 'E-ROUTE'},
    {'kind': 'golden', 'end': '10:00', 'arrival': '10:15', 'closes': '11:00', 'evidenceID': 'E-GOLD'},
]


def main():
    records = [json.loads(line) for line in (HERE / 'runs.jsonl').read_text().splitlines()]
    assessed = []
    for row in records:
        result = row['result']
        passed, note = NOTES[row['caseID']]
        if result['outcome'] != 'response':
            passed, note = False, 'No model response: ' + result['outcome']
        guard = None
        if row['input']['kind'] == 'intent' and result['outcome'] == 'response':
            guard = validate_intent(result['parsedFields'], row['input']['context'], 7)
        assessed.append({'runID': row['runID'], 'caseID': row['caseID'], 'repeat': row['repeat'],
                         'provisionalPass': passed, 'singleReviewerNote': note,
                         'applicationGuard': guard, 'humanReview': 'pending'})
    (HERE / 'assessment.jsonl').write_text(''.join(json.dumps(x, sort_keys=True) + '\n' for x in assessed))
    (HERE / 'templates.json').write_text(json.dumps([{'input': x, 'output': render_fact(x)} for x in TEMPLATE_FACTS], indent=2) + '\n')
    print('Provisional full-task passes:', sum(x['provisionalPass'] for x in assessed), '/', len(assessed))
    for label in ('reject:', 'proposed only:', 'no mutation:'):
        print(label, sum((x['applicationGuard'] or '').startswith(label) for x in assessed))


if __name__ == '__main__': main()
