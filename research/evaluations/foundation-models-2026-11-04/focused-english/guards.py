"""Experimental application-side checks and templates, separate from model grading."""
from datetime import datetime


def validate_intent(result, context, current_revision):
    """Accept only a well-formed proposal. Semantic agreement still requires review."""
    if context.get('stateRevision') != current_revision:
        return 'reject: stale context revision'
    if not isinstance(result, dict):
        return 'reject: invalid result'
    intent = result.get('intent')
    if intent in ('clarify', 'none'):
        return 'no mutation: clarification or no action'
    if result.get('question'):
        return 'reject: unresolved question accompanies a proposed action'
    fields = {'extend': {'intent', 'target', 'minutes'}, 'skip': {'intent', 'target'},
              'deadline': {'intent', 'target', 'deadline'}, 'apply': {'intent', 'proposalID'}}
    if intent not in fields:
        return 'reject: unsupported intent'
    if any(value is not None and key not in fields[intent] for key, value in result.items()):
        return 'reject: unexpected fields'
    stops = {s['id']: s for s in context.get('stops', [])}
    target = result.get('target')
    if intent == 'extend':
        minutes = result.get('minutes')
        if target != context.get('currentStopID') or target not in stops or stops[target].get('status') != 'visiting':
            return 'reject: extension target is not the active visit'
        if type(minutes) is not int or not 1 <= minutes <= 240:
            return 'reject: invalid extension duration'
        if result.get('deadline') or result.get('proposalID'):
            return 'reject: unexpected fields'
    elif intent == 'skip':
        if target not in stops or stops[target].get('status') != 'pending':
            return 'reject: skip target is not pending'
        if result.get('minutes') or result.get('deadline') or result.get('proposalID'):
            return 'reject: unexpected fields'
    elif intent == 'deadline':
        if target != context.get('endPointID') or not result.get('deadline'):
            return 'reject: invalid deadline or endpoint'
        try:
            deadline = datetime.fromisoformat(result['deadline'])
            now = datetime.fromisoformat(context['now'])
            if deadline.tzinfo is None or deadline <= now:
                return 'reject: invalid deadline time'
        except (ValueError, TypeError):
            return 'reject: invalid deadline time'
        if result.get('minutes') or result.get('proposalID'):
            return 'reject: unexpected fields'
    elif intent == 'apply':
        proposal = context.get('proposal') or {}
        if (result.get('proposalID') != proposal.get('id') or proposal.get('basedOnRevision') != current_revision
                or not all(proposal.get(k) is True for k in ('valid', 'complete', 'feasible'))):
            return 'reject: proposal is stale or invalid'
    return 'proposed only: requires confirmation and revalidation'


def render_fact(fact):
    """Render verified structured app results; no model output is used."""
    kind = fact['kind']
    if kind == 'weather':
        return f"At {fact['stop']}, the forecast gives a {fact['probability']}% chance of rain; rain is not certain. [{fact['evidenceID']}]"
    if kind == 'route':
        return f"The app-calculated arrival is {fact['arrival']}; the deadline is {fact['deadline']}. [{fact['evidenceID']}]"
    if kind == 'golden':
        return (f"Golden hour ends at {fact['end']}; arrival is {fact['arrival']}. "
                f"The stop remains open until {fact['closes']}; missing golden hour does not itself require cancellation. [{fact['evidenceID']}]")
    raise ValueError('Unsupported fact type')
