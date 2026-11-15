# Task: Request-time visit research and Luna

Status: Work stopped at the user’s requested failure boundary. Local implementation exists; complete live itinerary coverage is not accepted.
Owner: Giovan and Codex
Branch: `gi/pocket-ui`

## Approved boundary

The user explicitly removed the temporary geographic restriction, rejected further use of the old venue catalog, and requested Luna on the actual first-itinerary path. Priority 1 and 2 remain accepted for now; this work concerns priority 3: selected place evidence, visit timing, order and route feasibility. Keep the existing native preference/discovery UI, car travel, default origin/endpoint and optional overrides. Do not add configuration forms to compensate for missing public facts. Accuracy takes precedence over latency. Never complete Luna's unknown facts by hand or use replacement AI output.

## Implemented path

1. Native MapKit search retains source identity, branch address, website, phone and category when available. The former 60 km/country and planning-polygon gates are removed. Valid geographic coordinates are still required.
2. Every first-plan request sends all selected places to the maintained resolver at `server/pocket`, using authenticated asynchronous HTTP. The native service exposes no catalog lookup/fallback. Missing configuration fails explicitly.
3. Luna proposes focused queries. DDGS discovers sources; the server retrieves actual documents and branch/contact/visitor links, including rendered pages where available. Unsupported access is recorded. No search snippet becomes a fact.
4. Luna extracts nullable atomic facts with exact source quotations. A second review can reject them. Missing evidence triggers another targeted search. Snapshots preserve retrieved text, hashes, timestamps, extraction, review and reasons. Unknown identity/hours/access do not become ready venues. Reservations/eligibility remain conditional.
5. Luna recommends activity durations and soft visit timing as estimates. The iPhone evaluates the next seven days, validates hours, visit limits, waiting, complete car ETA and the endpoint. Luna chooses from the resulting immutable daily options; the iPhone validates that choice again.
6. Review distinguishes partial results, retains exclusion reasons and attaches opening/entry source links. Saved jobs preserve the complete original input separately from the scheduled subset. User-edited durations are retained on later planning requests.

## Executed checks

- Python server: 24 passing behavior tests, including real local HTTP with synthetic model/source responses, exact-quote rejection, same-model stream completion, missing duration, absence of closure notices, reservation/onsite-registration distinction, authenticated requests and no catalog endpoint.
- C67Backend: 53 passing tests. The original selection survives separately from the scheduled subset. Former area boundaries do not reject resolved visits. Missing consent stops subsequent research before route/model work.
- Pocket Engine: 14 passing tests. These establish solver behavior with fixtures, not actual venue opening.
- Native Simulator: 36 targeted fixture checks passed (33 presenter and 3 UI), followed by 33 presenter checks after the last schedule-context changes. Xcode 27.2, iPhone 18 Pro Max, iOS 27.2. The fixture UI covers partial-result labeling/saving, missing public facts without a manual-hours form and token-safe settings.
- Pinned Swift formatting, whitespace, OpenAPI and fixture checks pass. The contract validator also checks the actual captured five-place native request and response against the separate camel-case Pocket schemas, preserving the legacy snake-case schemas.

## Actual five-place UI acceptance

The native UI test passed in 1,073.319 seconds using the original five public pins, real authenticated HTTP, web retrieval, Luna and Apple ETA. The harness seeds selection inputs only; it supplies no venue facts or replacement ETA. It skips new discovery because the five selections reproduce the reported failure. This establishes the request/research/review path, **not five-place itinerary coverage**.

| Selected place | Actual research result | Effect |
| --- | --- | --- |
| Taman Bendera Pusaka | Hours and public access accepted from retrieved quotations | Scheduled 09:00–10:00 on the suggested Sunday, with actual Apple driving estimates |
| Tatemukai Signature Omakase Sushi | Split service sessions and reservation-only entry | Conditional; no reservation was fabricated |
| National Library of Indonesia | Luna extraction failed twice with HTTP 524 | Unresolved; this is a provider failure, not a geography rejection |
| Night market | Retrieved sources did not identify a specific market at the pin | Unresolved; another market's schedule was not substituted |
| Memorial Coffee Cipondoh | Conflicting published schedules; insufficient accepted entry evidence | Unresolved; hours were not selected arbitrarily |

The live run made 18 logical Luna calls, 17 completed, with six upstream HTTP 524 responses across retries. Requested model was `cx/gpt-6-luna(max)`; the endpoint reported `gpt-6-luna(max)`. The review explicitly said partly ready. Only 1/5 selected places was scheduled, so the reported multi-place coverage problem is **not accepted as solved**.

Artifacts: [native request and result](../evidence/pocket-runtime-2026-11-14/native-five-place-resolution.json), [actual review screenshot](../evidence/pocket-runtime-2026-11-14/live-five-place-review.png), [processing screenshot](../evidence/pocket-runtime-2026-11-14/live-research-processing.jpg). The raw test result is `/private/tmp/c67-runtime-stream-ui.xcresult`.

## Follow-up experiments and changes

- A minimal live Luna request completed in 3.42 seconds. A streaming probe returned actual JSON content and the expected model alias in 1.43 seconds. Streaming and a longer local timeout do not by themselves eliminate the upstream HTTP 524 limit.
- Automatic discovery was refined to target local-language branch hours/entry. The crawler limits branch-link traversal and excludes account/POS/staff-login pages. It respects robots/access failures; a 403 is not converted to retrieved evidence.
- A fresh refetch of the two actual park sources, followed by batched source extraction, adjudication and review with real Luna, returned ready. This used the discovery URLs recorded in the live run, not hand-written hours. [Proof](../evidence/pocket-runtime-2026-11-14/batched-source-proof.json). It is a focused live extraction test, not a new five-place UI acceptance.
- An 18,000-character extraction-batch retry for Perpusnas still received HTTP 524 twice and returned unresolved. [Result](../evidence/pocket-runtime-2026-11-14/library-large-batch-result.json). All stored source text is now read in overlapping 6,000-character batches. The smaller-batch run also completed with unresolved status after repeated upstream HTTP 524 responses; it did not recover Perpusnas. See [the result](../evidence/pocket-runtime-2026-11-14/library-small-batch-result.json).
- Empty closure arrays are rejected: absence of a closure notice is unknown. A separate review by the same model is a consistency check, not independent ground truth.
- Schedule options sent to Luna now retain maximum feasible selected-place coverage and a feasible main spot. Automatic dates no longer populate the legacy requested-day context. The explanation prompt forbids presenting a suggested date as user-requested or exposing internal slot IDs. The earlier screenshot predates this wording fix.
- Explicitly sourced onsite visitor registration/ticket purchase can be treated as public access with its requirement retained. Existing membership and advance-only booking remain conditional. This distinction does not invent an individual's eligibility.
- OpenAI documents [background Responses polling](https://developers.openai.com/api/docs/guides/background). The actual Luna endpoint accepted a minimal `background:true` Responses request (HTTP 200, completed in 1.84 seconds), but retrieving its returned response ID returned HTTP 404. This does not establish usable background polling, so that feature was not added as an assumed workaround.
- Read-only upstream log inspection through Portainer was attempted with the Portainer Ops skill, but the connector reported `SSH_UNAVAILABLE`. No shared service was changed.

## Reproduction and limits

See [server setup](../../server/pocket/README.md), [HTTP contract](../../contracts/api/openapi.json) and [integration guide](../pocket-engine-integration.md). The runtime UI check is opt-in `C67_RUNTIME_ACCEPTANCE=1`, with private `C67_LIVE_URL`, `C67_LIVE_READ_TOKEN` and `C67_LIVE_INPUT` environment values. Credentials do not enter source or screenshots. The earlier catalog implementation is historical evidence, superseded by this task. No shared server deployment, container execution, physical iPhone or TestFlight verification is implied.

## Final checkpoint and stop

The native Responses transport completed a real source-text extraction in 122.71 seconds, preserving reported model `gpt-6-luna` and reported reasoning effort `max`. This is evidence for that specific transport/extraction, not successful Perpusnas scheduling. [Captured output](../evidence/pocket-runtime-2026-11-14/native-responses-extraction.json).

A separate real Luna re-review accepted the recorded recurring weekly-hours quotation without requiring a literal trip year. [Review](../evidence/pocket-runtime-2026-11-14/recurring-scope-proof.json). It did not establish complete access evidence or a new itinerary.

The final Simulator advice-test command reported success but ran zero tests; it is not counted as live advice acceptance. After the user requested a strict final attempt and stopping on failure, one actual request to the local advice endpoint failed with `URLError`. No further provider experiments were started. The final native Responses server/advice integration and a new complete multi-stop UI result remain unverified. The earlier actual five-place UI result remains 1/5 scheduled.
