# Contextual ordering: duration, rain and golden-hour opportunities

Date: 2026-11-14. Scope: authorized bounded headless experiment. No UI, Simulator,
route/ETA API, catalog lookup, crawling, application-flow change or deployment.

## Result and completion boundary

**Ten actual Luna requests completed; ten passed the declared structural and
source-reference checks.** Six Phase A answers were manually reviewed before the
four Phase B requests. No response was retried, repaired or replaced by another
provider. No extra calls were made after the matrix.

The two planned real-WeatherKit calls were **not run**: no complete WeatherKit
REST configuration was found in the process/project/related local lab env files
inspected. A team ID alone does not supply the required key/service credentials.
No WeatherKit endpoint request was attempted and no other weather provider was
substituted. See [Phase C status](phase-C-status.json). Therefore this is not a
fully passed twelve-case test or live-weather integration acceptance.

All weather provided to Luna was explicitly synthetic. The solar windows were
actually calculated in code for the supplied coordinates/date. The model calls
were live; the weather was not. Selected-place names/pins are recorded public
test selections, while preference values/endpoints are controlled scenarios.
Case B9 uses explicitly fictional places and attributes.

## Observed output capability

Luna returned exact selected-ID order, trip rationale, per-stop activity/basis,
role, duration range or explicit unknown, qualitative daypart, weather references
and advice, solar-window reference/priority/advice, tradeoffs, uncertainties and
at most one alternative order.

| Probe | Actual finding |
|---|---|
| Missing context | Order and activity estimates still produced; weather remains unavailable |
| Duration intent | Reading changes from 90–150 to 20–35 minutes; coffee from 45–75 to 15–30 |
| Photography relevant | Park uses `L1-morning`, explicitly an opportunity rather than guaranteed light/arrival |
| Rainier afternoon | Advice changes to identify higher rain/cloud in sampled later periods; places retained |
| Dry but cloudy | Distinguishes low rain from cloudiness; computed solar times unchanged |
| Photography deprioritized | Park light priority changes to `not_relevant`, no window selected |
| Weather missing, solar present | Uses calculated opportunity without inventing weather |
| Ambiguous setting | Two uncertain activity durations become null with explanations; no asserted indoor shelter |
| Two photo targets | Fictional A morning, B evening; alternative order and explicit reachability uncertainty |
| Exact repeat | Order stable in this repeat; some duration ranges and dayparts vary |

These are bounded capability findings. Estimated durations have not been compared
with observed traveller dwell times. Structural success is not a human judgement
that every recommendation is useful, reasonable or convenient.

## Exact context and isolation

The original five selected IDs/names/pins are reused from the
[captured selection](../pocket-runtime-2026-11-14/native-five-place-resolution.json).
Absent categories remain null. No bundled/server venue catalog is read. Names may
suggest activities only as inference; public venue facts are not filled from
model memory. No Google API or external weather fallback is used.

Concrete scenario date: **2026-11-15**, zone **Asia/Jakarta**, marked as a
system-suggested test date. User input of a date is not introduced as a requirement.
The main spot is the selected park. Photography is initially prioritized along
with deep reading, a relaxed coffee break and other selected visits.

Weather fixtures provide sparse one-hour samples, at local 09–10, 15–16 and
17–18, for each selected point. They do not cover an entire day/visit. Clear:
probability 0.10, cloud 0.15, amount zero. Rainy later samples: probability 0.85,
cloud 0.95, amount 2 mm; the morning sample remains unchanged. Cloud-only variant:
rain probability/amount unchanged, cloud 0.95. All are labelled synthetic,
with source IDs, place/pin, date/zone and provenance.

The numeric fixture values and solar timestamps are not copied into model prose.
Luna returns case-scoped source IDs; independent code binds original source
objects for display. [Bound source values](bound-source-values.json) preserve
that distinction. These are experimental data bindings, not an implemented app UI.

No ETA, road distance, operational hours, departure choice, visit arrival time,
operator maximum stay or precomputed route was supplied. Model duration numbers
are expressly experience estimates, not source-derived venue limits.

## Offline checks and solar calculation

**68 offline checks passed** before any Luna dispatch. They cover valid contexts,
probability units/ranges, stale/future/date/zone/location errors, duplicate or
cross-place references, forecast-period coverage, duration ranges/basis, selected
IDs, explicit unknowns, source-value immutability, cloud/solar separation and polar
no-crossing behavior. They are local harness checks, not application tests.

Astral **3.2** is pinned in the disposable existing Python environment. The lab
uses its documented PhotoPills convention, solar elevation from -4 to +6 degrees,
with its default refraction treatment. This reproducible convention is not a
universal definition or a prediction of actual photographic quality.

Preflight initially rejected a morning event falling on the next Jakarta local
date. The wrapper now selects actual computed events from neighboring calculation
dates whose endpoints match the requested local date; it never shifts a returned
timestamp by a day to hide a mismatch. This was corrected before inputs were
frozen and before any model call. The date guard was retained.

Solar geometry was cross-checked with an independent implementation of NOAA's
simplified solar-position equations at twelve interval endpoints over February,
June and November Jakarta dates. Maximum elevation difference was **0.10713°**
against the predeclared 0.75° sanity tolerance. Sunrise/sunset containment,
local-date/zone handling and no-event behavior were also checked. This is an
approximate geometry cross-check, not an observational accuracy claim.

References: [Astral](https://astral.readthedocs.io/en/latest/package.html#astral.sun.golden_hour),
[NOAA equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF).
[Offline results](offline-checks.json) preserve individual checks/comparisons.

## Manual audit: findings that structure checks do not establish

Every completed answer was read against its exact context by the implementing
agent. No critical invented venue fact, numeric weather/solar value, hidden place
replacement or promised arrival was found in these ten answers. Unknown venue
features remained qualified; sparse forecast coverage was explicitly acknowledged.
This is not a general hallucination guarantee or stakeholder acceptance study.

Material weaknesses retained rather than patched:

1. **Daypart terminology:** `evening` is sometimes rendered as *malam*, even though
   the supplied sample is 17–18 local. Explicit local-time interval labels must
   be normalized before using this advice in the product. This is a meaning/period
   ambiguity, not an invented numeric timestamp.
2. **Forecast wording:** one response calls the zero synthetic forecast amount
   *curah tercatat*. The surrounding text says synthetic forecast, but wording
   should consistently say *diprakirakan* to avoid an observation implication.
3. **Duration variation:** repeat keeps park/sushi/library ranges, but market
   changes from 45–75 to 45–90 and coffee from 45–75 to 40–70. Library daypart
   changes from flexible to afternoon. These are suggestions, not deterministic
   measurements; persistence/regeneration policy is a later product decision.
4. **Activity priority versus main spot:** the photo-deprioritized scenario keeps
   the park anchor while prioritizing reading/food; the output respects the anchor
   but the prose has a priority tension. Clarify semantics before integration.
5. **Usefulness/readability:** repeated source/availability warnings can dominate
   output. Weather advice varies appropriately but is sometimes generic.
6. **Competing windows:** the fictional case offers both morning and evening
   opportunities, allowing the model to choose different periods. It does not
   establish handling of a forced simultaneous-window impossibility.

See [manual audit](manual-audit.json) and the pre-B [Phase A gate](phase-A-gate.json).
No human ratings have been collected. The [review packet](review-packet.md) omits
author ratings and experiment labels for future review; no blinded study occurred.

## Runtime and usage

All ten calls returned HTTP 200 and a completed response. Provider-reported model:
`gpt-6-luna`, effort `max`, protocol `responses`. Requested alias:
`cx/gpt-6-luna(max)`. These are provider reports, not upstream attestation.

Latency range **65.065–136.013 seconds**, median **93.880 seconds**. Reported total
usage **108,033 tokens** across the ten calls. No monetary cost was inferred.
The provider's output-token-cap semantics remain unverified; `max_output_tokens`
is not treated as a proven billing/spend ceiling. The hard experiment limit was
twelve API requests; ten were used, and two live-weather slots remain unused.

## Reproduction and delivery

- [experiment.py](experiment.py): fixed prompt, immutable cases, context/output
  checks, ledger and phase gate. Network runs require existing private credentials.
- [requirements.txt](requirements.txt): added solar dependency, pinned.
- [inputs.json](inputs.json): exact input payloads and prompt, including provenance.
- [call-ledger.json](call-ledger.json): reservations before dispatch, all ten outcomes,
  no repeated case or automatic retry.
- Individual A/B JSON files retain raw visible provider output, actual metadata,
  usage and automated checks without repair.
- [summary.json](summary.json): all results and paired comparisons.
- [summarize.py](summarize.py): offline replay, original source binding and review packet.
- [check_offline.py](check_offline.py): offline failure-boundary and solar checks.
- [phase-C-status.json](phase-C-status.json): missing real-source dependency.

The credential helper is reused read-only; API keys pass to curl over stdin and
are absent from evidence. No production flow, credentials, deployment, shared
service, commit or push was changed. This supports further evaluation of the
proposed output contract, not a claim that the application is ready.
