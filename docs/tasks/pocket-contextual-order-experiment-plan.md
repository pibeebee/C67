# Plan: Contextual ordering, visit duration, rain and golden hour

Date: 2026-11-14. Status: Bounded run finished; ten calls executed, real-weather phase unverified.
Owner: Codex. Reviewer: Giovan.
The user subsequently authorized the complete bounded test plan. The original
planning turn made no model calls or tests. Execution retains the guardrails
below; UI changes and application-flow implementation remain out of scope.

## Intended result

Starting from the traveller's selected places and existing preferences, Luna
suggests an experience sequence, activities, estimated visit-duration ranges,
dayparts, stop roles and contextual advice. Numerical weather/solar data comes
from external evidence or deterministic code. ETA and operational hours remain
outside the ordering prerequisite. This is not a verified arrival schedule.

Retain every selected ID exactly once. Do not restore a bundled catalog,
geographic allowlist, stop-count restriction or mandatory public-facts form.
Unknown activity, setting, availability or context may remain unknown. Do not
invent an indoor alternative, rooftop, viewpoint, reservation rule or maximum
stay merely to fill fields. No Google API is proposed.

## Responsibilities and current code

The maintained [Apple adapter](../../ios-backend/Sources/Data/Planning/PocketAppleServices.swift)
currently queries hourly WeatherKit data and returns the maximum hourly
precipitation probability during an already supplied visit interval. It is not
yet a day-context adapter for the new untimed ordering experiment. This is source
inspection, not verification of a current live WeatherKit session.

Proposed data responsibilities:

| Component | Responsibility |
|---|---|
| iPhone in the later product | Existing selection/preference metadata, origin/endpoint; obtain Apple weather context when available |
| Headless test harness | Controlled fixtures, provenance, weather acquisition check and deterministic solar calculations |
| External Luna through server | Experience interpretation, order, estimated duration, suggested activity/daypart, rationale and tradeoffs |
| Independent code | Validate IDs/schema/ranges, source references, dates, zones, units and coverage; display source numbers without model arithmetic |
| Human reviewers | Judge whether the experience and duration ranges are useful and reasonable |

The headless live-source stage may use WeatherKit REST rather than rendering an
iPhone UI. Authentication and current entitlement availability are unverified;
inspect configuration without printing credentials. Missing credentials are a
reported dependency, not grounds to pass a synthetic response off as live.

## Data contexts and the date issue

Two modes prevent a new mandatory date input:

1. Generic weekday/weekend context: offer activity/daypart suggestions. Actual
   weather probabilities and exact solar times remain unavailable.
2. Concrete candidate date: the app/harness provides a labelled candidate date,
   coordinates and IANA time zone. The user need not enter the date, but it must
   not be silently presented as a user choice. Selecting the best date over many
   days is a separate product decision, not proven by this experiment.

For testing, fix a concrete case date in the harness. For live data, use a date
covered by the actual retrieved forecast. Do not transfer one day's weather to
all weekdays/weekends. A future date can have a computed solar window even when
no weather forecast covers it; keep those availability states separate.

Weather source records should retain location, date/zone, forecast periods,
retrieval/issue metadata where provided, hourly precipitation probabilities,
precipitation type/amount or intensity when available, cloud cover and source ID.
Do not interpret a maximum hourly probability as the probability of rain over an
entire multi-hour period. Do not sum hourly probabilities or translate 80% into
80% of the visit being wet. For rain advice, do not mistake other precipitation
types for rain. Stale, out-of-period or wrong-location inputs are rejected or
marked unavailable before reasoning.

Solar source records should retain date/zone, place ID/pin, morning/evening
calculated windows, calculation method and immutable reference IDs. For the
headless lab, propose Astral's documented PhotoPills convention (-4 to +6 degrees
solar elevation). This is a chosen reproducible convention, not a universal
definition. No dependency is being installed by this plan. Verify the chosen
implementation, zone/date boundaries and reference comparisons before live use.
Do not approximate every location as exactly one hour before sunset.

Rain probability and solar geometry measure different things. A calculated light
window is not a prediction of unobstructed golden light, a suitable viewpoint,
public access, clear sky or the ability to arrive there. Cloud cover informs
qualitative uncertainty; it must not become an invented numeric probability of
beautiful light. Low rain probability does not by itself establish clear sky.

## Proposed output contract

Trip-level output: exact ordered IDs, overall rationale, tradeoffs, uncertainties
and at most one alternative order when a material conflict merits it. Do not
generate alternatives automatically for every request.

Per-place output:

| Field concept | Meaning and boundary |
|---|---|
| Suggested activity | What the traveller might do, with basis: preference, supplied fact, name inference or unknown |
| Visit role | Opening activity, main activity, break or closing activity; not a venue fact |
| Estimated duration range | Positive min/max minutes plus rationale; estimate, not operator maximum stay; null with reason if insufficient context |
| Preferred daypart | Qualitative experience preference, not a promised arrival or verified opening time |
| Weather advice | Relevance of the supplied forecast, possible adjustment and uncertainty; source-reference IDs |
| Light advice | Relevance to the user's activity and selected solar-window reference, or not relevant/unknown |
| Assumptions and gaps | Explicit distinction between supplied facts, estimated experiences and unknowns |

Do not ask Luna to reproduce forecast percentages or solar timestamps freely.
Return immutable weather/window references; code binds the original source values
to display. This responds to the earlier arithmetic error in model explanations.
Estimated duration is intentionally model-generated, so mark its basis separately.

No arrival/departure time, travel duration, claim of reaching every light window
or guarantee of finishing all visits in a day is requested. Exact solar times
are environmental opportunities, not arrival calculations. Likewise, a source
forecast is a prediction, not an observed future event.

## Phase A: Six bounded synthetic-context calls

Use one fixed prompt and the same original selected IDs/pins where appropriate.
All weather fixtures are explicitly synthetic and not presented as real forecasts.
Do not fill actual unknown venue attributes with invented operator facts.
Each pair changes only the factor under investigation.

| Call | Case | What should be assessed |
|---|---|---|
| 1 | Rich output, weather/solar unavailable | Still produce order and qualified activity/duration suggestions; no invented context |
| 2 | Same as 1, shorter versus immersive activity wish | Duration recommendation responds to the changed intent; no operator-limit claim |
| 3 | Photography preference, low rain/low cloud, supplied computed solar window | Explain a potentially suitable opportunity without guaranteeing visibility or arrival |
| 4 | Same as 3, rainy/cloudy afternoon | Change contextual advice or preferred period where justified; preserve places and discuss the conflict |
| 5 | Same as 3, high cloud but still low rain | Distinguish dry conditions from certainty of golden light; keep the solar window unchanged |
| 6 | Same as 3, photography deprioritized | Avoid forcing the trip around golden hour when it does not serve the preference |

Use supplied interval references for actual fixture numbers. A changed forecast
does not require a changed exact order: an unchanged order with a relevant change
in advice can be reasonable. Conversely, merely repeating generic weather text
does not establish sensitivity to the input.

## Phase B: Four robustness calls, gated on Phase A

| Call | Case | What should be assessed |
|---|---|---|
| 7 | Weather unavailable, solar window available | Preserve calculated opportunity, retain unknown weather; no false clear-weather claim |
| 8 | Ambiguous names/setting with rainy context | No assumed indoor seating, rooftop, shelter or invented replacement destination |
| 9 | Two competing light opportunities and one main spot | Prioritize the experience or offer one alternative; do not assert both can be reached without travel data |
| 10 | Exact repeat of case 3 | Review variation in order, duration ranges and advice; do not demand unique order where multiple choices are reasonable |

For case 9, use explicitly fictional fixture places if controlled outdoor/photo
attributes are needed. Never attribute synthetic facilities to a real business.
These are reasoning fixtures, not source-grounded venue coverage claims.

## Phase C: At most two headless live-source calls

Only after structure/factuality checks pass and real WeatherKit access is verified:

1. Retrieve current forecast context for selected pins and one concrete date,
   calculate solar windows independently, then request a contextual recommendation.
2. Keep the same real context but change activity priority to reading/food rather
   than photography, checking that the advice remains preference-driven.

These test data plumbing and actual model input fidelity. They do not establish
forecast accuracy, observed visit duration or whether golden light occurred.
Do not invent a second live weather regime if only one is available. Controlled
weather sensitivity comes from Phases A/B, explicitly labelled as synthetic.

## Independent checks and decision gates

Offline checks require no Luna requests: exact ID membership, field/range schema,
null handling, valid references, units, date/zone alignment, forecast coverage,
stale/out-of-location rejection, immutable numeric-source values and solar
calculation comparisons. Test invalid source records before sending them to Luna.

Manual review, separately labelled from code checks: preference fit, activity
flow, contextual relevance, duration plausibility, geographic tradeoffs and
factual restraint. A plausible duration range is not empirically validated dwell
time. Prepare a packet for Giovan/mentor review; do not treat the implementing
agent's score as stakeholder acceptance.

Every selected place must remain. Any invented critical venue/weather fact,
unsupported guaranteed arrival, fabricated source, hidden substitution or loss of
selection blocks acceptance even when the JSON parses. Smaller quality issues
remain explicit findings. After the initial six calls, proceed only if the
critical checks pass. On failure, retain the evidence and stop the extension;
do not silently repair the answer and call the original successful.

Maximum: 12 Luna calls (6 initial + 4 robustness + 2 real-source), at most two
concurrent, no automatic retry/fallback or unbounded prompt tuning. Report every
failed request, actual model/completion, latency and provider-reported usage.
Unavailable live data leaves Phase C explicitly unverified. Do not launch UI.

## Delivery and scope limits

Deliver exact payloads/responses, independent-check results, manual findings,
paired comparisons, sources and missing dependencies. Separate synthetic model
reasoning, real-source integration, and unperformed human/field validation.
Do not modify the product flow, deploy or claim production readiness in this lab.

Execution result: 68 offline checks passed; ten live Luna calls completed with
ten structural/source-reference passes. Six Phase A outputs were manually
reviewed before the four Phase B calls. Duration-intent, context sensitivity,
unknown-setting and repeat behavior were recorded without output repair.

The two Phase C calls were not run because complete WeatherKit REST credentials
were not found in inspected local configuration. No actual Apple Weather request
or alternate provider was used. Do not claim live-weather integration passed.

Audit found daypart/forecast-wording issues, variation in some duration estimates,
and a main-spot/priority tension. No human/field acceptance was collected. No UI,
app-flow, deployment, commit or push changes were made.

[Full results, raw evidence and limits](../evidence/pocket-contextual-order-2026-11-14/README.md).

Authorized follow-up, 2026-11-15: the user requested Open-Meteo as the present
WeatherKit fallback. The [separate real-source run](pocket-open-meteo-fallback-test.md)
used the two remaining calls: forecast retrieval succeeded, one model response
completed and one timed out. Earlier raw evidence remains unchanged; WeatherKit
itself and a complete real-weather preference pair remain unverified.

## Primary references

- [WeatherKit overview](https://developer.apple.com/weatherkit/): Swift/REST APIs,
  current conditions and ten-day hourly forecasts; availability is not an access test.
- [HourWeatherConditions](https://developer.apple.com/documentation/weatherkitrestapi/hourweatherconditions):
  hourly forecast properties, including precipitation probability and cloud cover.
- [SunEvents](https://developer.apple.com/documentation/weatherkit/sunevents):
  sunrise, sunset and twilight events; no direct golden-hour property is listed.
- [Astral golden_hour](https://astral.readthedocs.io/en/latest/package.html#astral.sun.golden_hour):
  reproducible date/location/zone-based calculation and the chosen angular convention.
- [Previous untimed experiment](../evidence/pocket-reasonable-order-2026-11-14/README.md).
