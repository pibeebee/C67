# Task: Test Luna ordering without opening-hour prerequisites

Status: Experiment completed; production capability remains unaccepted. Owner: Codex. Review: Giovan. Branch: existing `gi/pocket-ui`.

## Outcome and scope

Test the external Luna model directly, without UI, crawling, catalog lookup,
application-flow changes, deployment, commits or pushes. Use eight bounded live
requests with at most two concurrent calls and no automatic retry. Stop if the
first request cannot produce a complete answer.

The original five public place selections are retained. All travel matrices,
duration estimates, preferred windows and the known-hours control are explicitly
synthetic. This measures model ordering capability and input fidelity, not real
route accuracy, venue accessibility or production readiness.

## Acceptance and verification

- Validate the exact selected-ID permutation, output schema, unchanged nullable
  opening-hour facts, per-place reasoning and uncertainty disclosure.
- Compute all permutations/departure choices independently; report score gaps
  separately from validity. Do not call a merely valid answer optimal.
- Include changed preferences, directed costs, a supplied hard constraint,
  missing ETA data, reordered input and an instruction embedded in a place name.
- Retain real provider model, reasoning effort, completion, latency, output and
  usage. Never include credentials in prompts or evidence.
- Manually review explanations for unsupported venue-specific claims.

Script and evidence: [headless experiment](../evidence/pocket-hours-optional-2026-11-14/run_experiment.py).
Design context: [proposal](../research/pocket-hours-optional-luna-ordering.md).

## Result

Eight live calls completed without retries: seven completed answers and one HTTP
524. All six proposed orders matched the exhaustive synthetic-fixture oracle;
one answer correctly reported insufficient travel data. All seven complete
answers passed structure/constraint checks and preserved nullable hours. Manual
review found incorrect travel/objective arithmetic in one explanation. The
adversarial-name case returned HTTP 524, so that behavior remains unverified.

No UI was started and no production flow was changed. See the
[full findings and limitations](../evidence/pocket-hours-optional-2026-11-14/README.md),
including synthetic-input boundaries, exact outputs, latency and token usage.
