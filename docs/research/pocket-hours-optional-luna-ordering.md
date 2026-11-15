# Hours-optional planning with Luna ordering

Date: 2026-11-14. Status: **Untested design proposal**, not an implemented or approved architecture change.
Scope: research and this note only; no implementation, provider calls, benchmarks, builds or tests.
Owner: C67 discussion. Review: product and Pocket integration before implementation.

Follow-up: a separate [headless live-model experiment](../evidence/pocket-hours-optional-2026-11-14/README.md)
tested synthetic ordering fixtures. It supports bounded ordering capability,
but found a numeric explanation error and an HTTP 524. The application flow is
unchanged; the original proposal's production claims remain unverified.

## Recommendation

Remove verified opening hours as a prerequisite for generating an itinerary. Let Luna propose or rank visit order using selected places, categories, preferences and Apple travel-time estimates; retain deterministic validation on the iPhone. Prefer this hybrid to LLM-only routing. This is a design inference from the sources below, not a measured Luna result.

The [current integration](../pocket-engine-integration.md) has Luna select immutable locally validated schedules after venue research. The proposal changes that dependency: missing venue hours would no longer block a provisional plan. Existing code and recorded evidence remain unchanged.

## Proposed responsibilities

1. The iPhone retains each original selected ID, coordinates and category, plus preferences, origin, endpoint, requested order/main spot and any explicit time constraints. No bundled/server catalog, geographic allowlist or Google API is introduced.
2. MapKit on the iPhone supplies Apple ETA inputs with travel mode and relevant departure context. Luna runs through the external server; it does not run inside MapKit or on the iPhone. Provider credentials remain server-side.
3. Send Luna the exact selected IDs, associated categories, preferences, labelled duration estimates, applicable constraints and available Apple leg costs. Luna returns an ordered list of those IDs and a short explanation. Categories may suggest morning/day/evening suitability; these are soft suggestions, separately labelled from verified venue facts.
4. Validate the returned order as an exact permutation of the selected IDs: no new, missing or duplicate ID. An infeasible subset requires explicit omissions and reasons, never silent truncation. Preserve explicit main-spot/manual-order requirements. Malformed or invalid output is rejected for correction.
5. Compute arrival, departure and finish from Apple ETA plus visit durations in native code; refresh candidate legs at their proposed departure times where needed. Check explicit user constraints and any trustworthy available closure, last-entry, reservation or maximum-stay facts. Missing route data remains a route-data gap, never a model-created ETA.
6. Known venue constraints remain effective opportunistically; unknown availability stays `unknown`. Never infer opening hours from category, preferred period or Luna's explanation. A preference for a morning park visit does not establish morning access.

The minimum path should not wait for exhaustive venue research. Existing usable evidence can accompany the request; missing evidence produces an availability caveat, not invented facts or a mandatory public-facts form.

## Hybrid versus LLM-only

| Choice | Useful role | Limit |
|---|---|---|
| Luna alone | Interpret preferences and suggest a plausible order | A convincing explanation does not establish valid IDs, correct arithmetic, availability or optimality. |
| Luna plus native checks | Semantic ordering with independently checked destination preservation and timing | ETA and duration estimates remain uncertain; validation alone does not prove a globally best route. |
| Optional native candidate comparison | Compare valid orders by Apple travel cost and preference penalties | Bound search for larger selections; expose computation limits rather than dropping selected places. |

[OR-Tools' TSP documentation](https://developers.google.com/optimization/routing/tsp) models travel costs as a matrix/callback and constructs orders through a routing algorithm. This supports separating supplied travel costs from route search; it does not require adopting OR-Tools or Google Maps.

[Yang et al., *Large Language Models as Optimizers*, v3](https://arxiv.org/abs/2309.03409v3) evaluates LLM-generated solutions and feeds their measured objective values into subsequent iterations, including TSP demonstrations. It supports trying LLM proposals with external evaluation, not assuming one response is optimal. It provides no Luna-specific accuracy, latency or C67 field evidence.

## What the proposal gives up

An itinerary with unknown hours cannot establish that venues will admit visitors when scheduled. It may send the traveller to a closed venue. Even valid arithmetic establishes a projected timeline, not certain arrival/finish times or verified visit feasibility. Surface “Availability unverified” beside affected stops and present the plan as provisional. Verified conflicting constraints still block the affected schedule.

## Synthetic acceptance example for later implementation

Input IDs: `park-A`, `cafe-B`, `museum-C`; preferences: outdoor morning, coffee break, relaxed pace. All hours are unknown. Supply synthetic, explicitly labelled Apple-ETA-shaped leg inputs and estimated visit durations.

An order `park-A → cafe-B → museum-C` can be accepted only after native membership, timing and supplied-constraint checks pass, with availability marked unverified. Returning `museum-D`, repeating `cafe-B`, silently omitting `museum-C`, or claiming “museum-C closes at 17:00” without evidence must fail validation. If a verified museum closure is later supplied, invalidate conflicting proposals. The order is an example, not a measured optimum or a promised category rule.

Before implementation, agree on the output schema, time-constraint behavior, explicit omissions and unverified-availability wording. Future acceptance should include malformed IDs, missing ETA, impossible time budgets and known closures. No such checks were run for this proposal; only document paths, source links and whitespace were inspected.
