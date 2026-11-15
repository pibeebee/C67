# Live Luna ordering capability experiment

Date: 2026-11-14. Mode: headless Python calling `https://ai.giovanc.com/v1/responses`.
No UI, Simulator, crawler, catalog, deployment or application-flow changes.

## Conclusion

Luna demonstrated bounded capability to generate an order without opening hours
from supplied preferences and directed travel costs. It is not safe to delegate
all timing arithmetic or explanations to the model unchecked. Provider reliability
and adversarial-input handling are not established.

Eight actual provider calls were attempted, without retries or fallback. Seven
returned completed JSON, and one returned HTTP 524. All seven complete answers
passed the automated structure, destination-preservation, factual-field and
constraint checks. Six proposed plans matched the exhaustive oracle's minimum
score; the seventh answer correctly refused to invent missing travel times.
**One otherwise valid plan contained incorrect arithmetic in its explanation.**
Do not describe these results as eight fully successful tests.

## Inputs and independent evaluation

The first two cases reuse the five selected names and public pins from the
[earlier real request](../pocket-runtime-2026-11-14/native-five-place-resolution.json):
Taman Bendera Pusaka, Tatemukai Signature Omakase Sushi, National Library of
Indonesia, Night market and Memorial Coffee Cipondoh. Their identities/access
were not re-researched. Categories, durations, preferred periods and travel
matrices are supplied synthetic fixtures. No live Apple ETA was requested.

The model generated orders directly; it did not receive oracle orders or a menu
of solved schedules. The Python evaluator enumerates every permutation and the
three supplied departure options: 360 combinations for five places, 18 for three.
The declared test objective is travel minutes plus twice arrival-window deviation,
plus 300 for violating an isolated first-place preference. Preferred windows are
not opening hours. No waiting is permitted in this benchmark. This artificial
objective is not an approved product scoring policy or proof of human satisfaction.

| Case | Provider result | Independent result |
|---|---|---|
| Original five | Complete, 129.045 s | All five; optimal score 190; explanation arithmetic error |
| Same five, shuffled input | Complete, 129.781 s | Same optimal order and departure; score 190 |
| Prefer park first | Complete, 21.354 s | Park first; optimal score 40 |
| Prefer library first | Complete, 11.307 s | Library first; optimal score 40 |
| Directed-cost trap | Complete, 17.767 s | Correct directed chain; optimal score 18 |
| Supplied hard visit window | Complete, 24.711 s | Entire library visit fits supplied window; optimal score 77 |
| Missing all START legs | Complete, 9.244 s | Explicit insufficient travel data; no fabricated ETA/departure |
| Instruction embedded in a place name | HTTP 524, 125.164 s | No complete answer; adversarial handling unverified |

All completed responses report model `gpt-6-luna`, reasoning effort `max`,
protocol `responses`, and completion status `completed`. These are the provider's
reported metadata, not independent attestation of its upstream implementation.
Median request latency across all attempts was 23.033 s; the two completed
five-place preference cases each took about 129 s.

The provider reported 41,502 total tokens across the seven complete responses;
usage for the failed call is unknown. Some reported output-token totals exceeded
the requested `max_output_tokens=3500` (for example 6,959 in the first case).
The provider's token-cap semantics are unverified; this request field must not be
treated as an established spend limit. No monetary cost was inferred.

## Manual explanation audit

All seven complete answers were read alongside their supplied inputs and independent
calculations. No unsupported opening-hour or access claim was found; null hours
were retained and unknown availability was disclosed. This is a small-sample
manual finding, not a general hallucination guarantee.

The first case returned the optimal order:

`park → sushi → library → coffee → market`, departure minute 660.

It described travel as **126 minutes** and objective as **198**. Independent
calculation gives **118 minutes** and objective **190**. Its quoted individual
arrivals and 72-point preference penalty were correct. The original answer has
been preserved without repair in [original-five.json](original-five.json).

The shuffled case's comparison against swapping library and sushi was checked:
that adjacent swap places sushi at minute 857, outside its soft window ending
at 840. Other numeric statements in returned explanations matched the fixtures.
The automated `validation.passed` field covers only its declared checks, not
every free-text assertion; it must be read together with this manual audit.

## Boundaries and next implementation implication

This supports trying Luna for order suggestions with independently computed
times, scores and explanation numbers. It does not establish real-world trip
feasibility, general optimality, preference-to-window inference, larger-trip
scaling, daily traffic handling, prompt-injection resistance or production uptime.
The preference reversals use explicit structured preferences, not inference from
an unstructured questionnaire. Unknown opening hours still cannot establish
that a venue will admit visitors at the suggested time.

No further model calls were made after the eighth result. Original production
flows and the earlier one-of-five live venue-resolution result remain unchanged.

## Reproduction and artifacts

- [run_experiment.py](run_experiment.py): evaluator, fixed prompt and bounded transport.
- [inputs.json](inputs.json): exact benchmark fixtures and prompt.
- [results.json](results.json): every actual request, output, model metadata, usage and validation.
- [manual-audit.json](manual-audit.json): explicit explanation audit findings.

Reproduction requires the private provider env pointer documented in the script,
the existing Pocket credential helper and the local Python dependencies. Keys
are passed to curl through stdin and are absent from evidence. Run from the repo
root with the experiment's Python environment. Reproduction causes new provider
calls; merely inspecting these files does not.
