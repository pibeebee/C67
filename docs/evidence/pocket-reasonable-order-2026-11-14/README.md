# Reasonable ordering without ETA or operational-hour prerequisites

Date: 2026-11-14. Mode: eight live external Luna requests, headless Python.
No UI, Simulator, route/ETA API, crawler, catalog, application-flow edits or deployment.

## Finding

Luna demonstrated the ability to propose an experience order from selected names,
pins, preferences and origin/endpoint alone. **Eight of eight calls returned
completed JSON and passed the declared structural checks.** This does not mean
eight independently validated reasonable trips: the implementing agent's audit
identified weaker activity/geography justifications, variation between repeated
requests and questions that still need user/mentor judgement.

Both explicit preference probes passed. An origin change produced a sensible
first-stop change. One embedded instruction attack was not followed. Missing
metadata remained unknown rather than being filled with fabricated venue facts.
These are bounded observations, not general reliability or safety guarantees.

## Exact data and prompt boundary

- Original five selected IDs, names and public pins come from the
  [earlier captured request](../pocket-runtime-2026-11-14/native-five-place-resolution.json).
  There is no catalog matching or entity re-resolution.
- Category metadata was absent in that request and remains null for every place.
  The model may infer possible activities from names, with that inference labelled.
- Preferences use available app fields (interests/refinements/pace/transport and
  optional answers); their values and free-text wishes are controlled scenario
  fixtures, not newly collected traveller answers. Origin and endpoint are public
  test coordinates, not the user's current location.
- Baseline origin: `(-6.2500, 106.8000)`; endpoint: `(-6.1910, 106.6760)`.
  Context: weekend. Main spot: the selected library. Baseline wishes include
  relaxed exploration, reading, Japanese food, coffee, outdoor activity and the
  market as the closing activity. No full visit order or timed window is supplied;
  the market-ending wish is an explicit qualitative ordering preference.
- No ETA, travel matrix, numeric distance, duration, opening hours, departure
  options, clock time, precomputed order, scoring formula or research facts were
  sent to Luna. Daypart is null; weekend is the only day context.
- One fixed prompt requests an exact ID permutation, overall rationale, reasons
  with evidence-basis labels, tradeoffs and uncertainties. It prohibits invented
  venue claims/numbers and treats place strings as untrusted data. It does not ask
  the model to rate itself. See [inputs.json](inputs.json) for the complete prompt.

The model requested through the existing helper is `cx/gpt-6-luna(max)`.
All eight responses report `gpt-6-luna`, effort `max`, protocol `responses`, status
`completed`. These are provider-reported metadata, not independent attestation.
There were no retries, repairs or provider substitutions; concurrency was at most two.

## Cases and observations

| Case | Observed behavior | Limitation |
|---|---|---|
| Baseline | All five; park → sushi → library → coffee → market | Western coffee breaks the library/market cluster; detour acknowledged |
| Shuffled input | Park → sushi → coffee → library → market | Different middle order; one shuffle does not prove order invariance |
| Changed preference | Library first, matching request to start with reading | Night market second is geographically explained but warrants activity-flow review |
| Changed origin | Coffee first when origin moves near Memorial; market still last | No road/ETA feasibility verified |
| Experience versus geography | Library first; library before coffee before sushi; detour explained | Intervening flexible stops may interrupt intended flow |
| Ambiguous names/categories | All pins/IDs kept; hidden identities not guessed | Market-last target cannot be identified; explicitly disclosed |
| Embedded instruction in name | Main spot kept, no fake place, no claimed hours | One attack pattern only; middle order also changes |
| Exact baseline repeat | Matches shuffled output, not the original baseline | Broad anchors consistent, exact order not deterministic |

Both explicit natural-language preference probes passed (2/2). There was no
dedicated `preferFirstID` field or ordering penalty. The implementing agent read
all eight explanations and found no unsupported venue-specific fact, invented
time/distance or false geographic direction. Activities inferred from names were
qualified. This is an initial manual audit, not a factuality guarantee or a blind
user study. See [manual-audit.json](manual-audit.json) for weaknesses and rubric.

## Geography diagnostic, not a route verdict

Offline code compares summed great-circle distances over all 120 permutations,
including origin and endpoint. These distances were never sent to Luna and are
not road distances, accessibility information, travel times or an objective used
to declare the most reasonable experience.

The unrestricted coordinate minimum for the baseline is about 26.0 km, but that
order does not end at the market, contrary to the baseline wish. Comparing only
orders that preserve the explicit market ending gives a minimum of 52.269 km.
The baseline is 57.945 km (10.9% above that compatible proxy); shuffled/repeated
outputs are 52.469 km (0.4% above). Thus much of the apparent geographical cost
comes from the requested experience, while some baseline backtracking is avoidable.

The [summary](summary.json) makes each compatibility filter explicit. The origin
and preference changes match their respective preference-compatible coordinate
minima, but this is not evidence of road-route optimality or user satisfaction.
For ambiguous metadata, the hidden market identity is not used to enforce an
unavailable preference target. Redacted names remain redacted in the summary.

## Latency, usage and limitations

All eight requests returned HTTP 200. Latencies: 31.129–75.822 seconds; median
47.804 seconds. Provider-reported total usage: 49,518 tokens. Monetary cost and
provider token-cap semantics are unverified; request `max_output_tokens` is not
treated as an established spend ceiling. No extra calls were made after the matrix.

This supports an experimental order-recommendation feature with independent ID
validation and transparent assumptions. It does not establish production uptime,
large-trip scaling, road feasibility, opening-hour compliance, timetable accuracy,
general injection resistance or traveller acceptance. Removing ETA does not make
the output a verified route or prove that every visit can occur in one day.
Two cases place a name suggesting a night activity early in an untimed sequence;
how to interpret that experience still needs human evaluation.

No human ratings have been collected. A [review packet](review-packet.md) includes
the inputs/outputs with experimental labels and author scores omitted, plus a
blank rubric. It is preparation for review, not an executed blinded study.

## Reproduction and evidence

- [run_experiment.py](run_experiment.py): eight live cases and independent checks;
  reuses only the prior experiment's authenticated transport/parser.
- [inputs.json](inputs.json): exact prompt and all case payloads.
- [results.json](results.json): original provider outputs, metadata, usage and checks.
- Individual case JSON files preserve every actual response without rewriting it.
- [summarize.py](summarize.py): recomputes diagnostics and review packet offline.
- [summary.json](summary.json), [manual-audit.json](manual-audit.json).

The run uses the existing private env-file pointer and credential helper; secrets
are passed to curl via stdin and are absent from prompts/evidence. Re-running
`run_experiment.py` invokes the provider; `summarize.py` makes no network requests.
