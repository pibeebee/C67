# Hybrid v4.2 planning latency

Status: Local implementation and compile-only verification. Owner and reviewer to be assigned by the project team.

Hybrid v4.2 is opt-in in the itinerary method picker. The iPhone uses the same
schedule search, ordering rules, time-specific travel validation, and quote limits
as v4.1. It prepares up to two regular-hours lookups at a time while Luna runs
and reuses the weekly evidence for the dates in the same job. User-confirmed
access and booked visits retain their existing meaning.

The Pocket contract adds a compact Luna request. One request accepts up to three
candidate dates and asks for shared activity/duration estimates plus per-date hints
and overrides. Each returned plan binds only evidence from its own date.
Malformed batch responses can fall back to individual compact requests. The
same Luna model and completion validation apply. Supplying all durations still
allows itinerary generation without Luna. Luna assistance in v4.2 requires the
updated Pocket server.

Use the iOS unified-log category PlanningTiming and Pocket order_timing and
order_complete events. Join the app's request_id to its order_id through the
luna_round_trip event and then look up the order_id on Pocket. itinerary_visible
measures the successful first-itinerary flow through the review screen appearing.
The logs include elapsed time and counters. They omit selections and user text.
Compare median and p95 for matched routes, dates, and user inputs alongside
feasibility, user constraints, and quality of duration and activity advice.

The supplied Swift and Python cases use synthetic responses. Run them in a later
authorized test session, then measure latency and itinerary quality with live
providers on an iPhone. Keep the recorded v4.1 behavior as the comparison.

Local checks passed with Xcode 27.2 and Python 3.12. The C67 scheme built for
testing against the generic iOS Simulator destination, and SwiftPM built the
package and its tests with `swift build --build-tests`. Python byte compilation
covered `server/pocket/src` and `server/pocket/tests`. The OpenAPI and fixture
contract check, pinned SwiftFormat check, and `git diff --check` passed. No test
case, app, simulator, or provider was run for this checkpoint.

## Luna and Foundation Models comparison

Account → Itinerary method offers **Hybrid v4.2 · Luna** and
**Hybrid v4.2 · Foundation Models**. Both use the v4.2 scheduler, hours lookup,
and travel validation. Foundation Models generates activity, estimated duration,
and preferred daypart on the device in English. This branch requires iOS 26
or later and an available Apple Intelligence model. The user can supply
durations to proceed when suggestions are unavailable. The selected method
stays attached to the job and proposal.

- `V42ExperienceProviderTests` compares the scheduler with matched advice,
  checks provider isolation and tests recovery with traveller-supplied durations.
  `V42FoundationResponseTests` checks date and place binding and invalid estimates.
- The app logs `luna_round_trip` for the Pocket request and
  `foundation_models_inference` for the on-device phase in `PlanningTiming`.
  Join Luna's order ID to `order_timing` on Pocket to see context, queue and model
  time separately.

Compile-only verification passed with Xcode 27.2. SwiftPM built the C67Backend
package and test target. Xcode built the C67 scheme for testing for both generic
iOS and iOS Simulator with signing disabled. Swift syntax, the pinned formatter,
and the diff whitespace check passed. No tests or model requests ran.

### Controlled Simulator comparison

The [18 November results](hybrid-v42-foundation-comparison-2026-11-18.md) used
the app's different provider contexts. The replacement benchmark
`V42LiveExperienceComparisonTests/lunaAndFoundationModelsWithIdenticalTask`
passes the same English instructions and canonical JSON context to both live
models. The test records the prompt SHA-256 and checks that the scheduler
requests that exact context before each generation. Both models return plain
JSON and share the same decoder, duration bounds, place/date binding and
domain validation. Each arm gets one batch attempt. An unavailable Apple model
stops setup before any Luna requests. The test records generation and
validation failures during the experiment.

Both arms use the real v4.2 planner with the same synthetic directed ETA
matrix, unknown opening hours, absent weather and light context, identical
locked 45-minute first visit and a return leg. The fixtures cover one fixed
day and a two-day comparison with a Thursday-specific wish. The clock and
trip dates are fixed. The runner executes serially and alternates which
provider starts each pair. The planner timings end when scheduling returns
and exclude app job polling, storage and UI. Luna runs remotely at max effort
and its provider time includes transport. The relay separately reports the
upstream round trip. Foundation Models uses the Simulator's Apple model. The
provider token limits follow the respective adapters (5,000 Luna and 1,800
Foundation Models). These limits cover different work.

After the run is authorized, execute from the repository root with the Pocket
Python dependencies installed. Use a unique `.xcresult` path and the UUID of
an iPhone Simulator with an available English Foundation Model.

```sh
python scripts/run_v42_simulator_comparison.py \
  --simulator "SIMULATOR_UUID" --repetitions 2 \
  --env-file /path/to/private-luna.env \
  --derived-data /tmp/c67-v42-matched-build \
  --result-bundle /tmp/c67-v42-matched-run.xcresult
```

The runner accepts the existing Pocket provider configuration or the local
`AI_GIOVANC_*` configuration from the provider-comparison lab. The upstream
key stays on the Mac. This workspace's prior run used
`../poc/llm-provider-comparison/.env` from the checkout root.
The Simulator reaches a temporary authenticated relay
on loopback. The runner shuts it down when Xcode exits. This requires only
the Simulator, local Xcode and the configured Luna provider.

Use the `V42_MATCHED` lines to pair results by scenario and repetition. Record
completion and validation rates before comparing successful latencies. Compare
model call, validation and total planner durations. Inspect activities,
duration ranges, dayparts and the Thursday override for preference fit,
unsupported venue claims and appropriate uncertainty. Review the proposed
day, order and schedule independently. Use all attempted pairs when reporting
failure counts and only pairs with two successes for paired latency deltas.
Two repetitions per fixture are exploratory. This benchmark uses plain JSON
generation for both providers. Apple output therefore reflects the common
prompt rather than production's guided generation.

The revised Simulator test target compiled with Xcode 27.2 using
`build-for-testing`. Pinned SwiftFormat, Python byte compilation of
the launcher, and Git whitespace checks passed. The controlled test was later
run; its results and limitations are recorded in the [matched Simulator report](hybrid-v42-matched-simulator-results-2026-11-18.md).
