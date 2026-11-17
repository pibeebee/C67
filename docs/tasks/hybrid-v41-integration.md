# Hybrid v4.1 local integration

Status: Ready for review. Local implementation verified with synthetic providers.

Date: 17 November 2026. Baseline application commit `9725792` and implementation plan commit `24e1e44`, on `gi/ui-audit-improvements`.

## User behavior

Hybrid v4.1 is selectable as **Hybrid v4.1: flexible schedules** in the Pocket itinerary-method settings. The persisted method is `hybrid_v4_1`. Existing Luna, Hybrid v2, and Hybrid v4 selections and saved trips retain their existing meanings.

The first-itinerary flow shows a date or finite comparison range beside Next. The schedule sheet offers automatic date selection, today, tomorrow, a two-to-three-day range, a three-day comparison starting today, and a selected explicit date. It also provides a preferred visit period, optional Luna assistance, visit durations, accepted duration minima, and trip-scoped access or activity-session details.

When user durations or booked-session durations suffice, v4.1 can run through review, editing, reordering, renaming, saving, and reopening without an ordering service or a model response. Missing duration estimates can use optional Luna assistance. A failed optional suggestion retains a schedule when the user-supplied durations suffice.

## Six implemented workstreams

| Workstream | Implementation | Observable behavior |
| --- | --- | --- |
| Structured timing | [Timing preferences](../../packages/C67Backend/Sources/Domain/Planning/PlanningPreferences.swift), [date resolver](../../packages/C67Backend/Sources/Domain/Planning/PlanningDayWindow.swift), [presenter](../../apps/ios/Features/TripCreation/Presenter/TripCreationPresenter.swift) | Timing answers reach the scheduler as typed values. A manually selected date wins over an earlier relative timing answer. Relative dates use a stable anchor and the trip time zone. |
| Diagnostics and recovery | [Assessment types](../../packages/C67Backend/Sources/Domain/Planning/PlanningScheduleAssessment.swift), [repository](../../packages/C67Backend/Sources/Data/Planning/PocketPlanningRepository.swift), [error actions](../../apps/ios/Features/TripCreation/View/TripCreationView.swift) | Jobs and proposals retain conflicts, missing evidence, search coverage, route use, dates considered, and evaluated duration alternatives. The UI offers relevant schedule, duration, and access actions. |
| Adaptive search | [V41Planner](../../packages/C67Backend/Sources/Data/Planning/V41Planner.swift), [route session](../../packages/C67Backend/Sources/Data/Planning/V41RouteSession.swift) | Validation expands beyond the first five schedules, explores different first and last visits, adds opening/target boundary seeds and permitted preferred-time waiting, and checks promising alternatives. |
| Duration review | [V41ItineraryPlanner](../../packages/C67Backend/Sources/Data/Planning/V41ItineraryPlanner.swift), [schedule controls](../../apps/ios/Features/TripCreation/View/PocketTripOptionsView.swift) | The target duration remains the baseline. Up to two consequential shorter-visit scenarios are checked. A successful alternative is offered with its source and date. Accepting it creates a new request with the chosen override. |
| Access and activity sessions | [Domain values](../../packages/C67Backend/Sources/Domain/Planning/PlanningModels.swift), [access controls](../../apps/ios/Features/TripCreation/View/PocketTripOptionsView.swift), [availability view](../../apps/ios/Features/TripCreation/View/PocketVisitAvailabilityView.swift) | Confirmed access, last entry, booked activity start/end, and session check-in are distinct. The availability form starts on the effective trip date. Unknown hours allow a provisional route schedule. |
| Optional Luna | [Planner and semantic reuse](../../packages/C67Backend/Sources/Data/Planning/V41ItineraryPlanner.swift), [normal trip capability](../../packages/C67Backend/Sources/Domain/Planning/PlanningScheduleAssessment.swift) | A complete supplied input uses zero semantic requests. When needed and allowed, a validated response supplies estimates and soft activity day parts. Applicable responses survive schedule edits and restart in the same account store. |

## Search policy and accounting

The native planner retains the v4 forward evaluator. V4's existing replay implementation remains available for its original policy. V4.1 starts with the finite order/departure domain, a 30-minute departure grid when flexible, and an earliest-necessary-wait policy. Quotes are validated at the actual minute produced by each candidate's forward simulation, including the endpoint.

Screening reuses directed estimates already obtained during candidate validation, keeping acquisition and validation in one request budget. In addition to a coarse grid, the search builds departure seeds from known opening times and user or model targets using available route estimates. These seeds receive normal forward validation. Optional waiting seeds can improve soft targets within the traveller's explicit allowance while preserving a usable alternative when waiting would exceed the deadline.

Candidate batches contain up to five schedules. After initial validation, selection diversifies the first and last visits and prefers routes that avoid previously unavailable directed pairs. With a complete candidate available, refinement continues for incomplete first/last coverage, unmet preferences, or a promising screening estimate, for at most three batches. With no complete candidate, expansion continues to the finite-domain or budget stop. A failed quote at one departure does not exclude the pair at every time.

The initial experimental allowance is 72 reserved route attempts per planning command, 500 candidate evaluations per active attempt, and a 90-second limit starting with the first candidate search. The active-attempt limits also bound work when every leg has the same coordinates and requires zero provider calls. The request allowance covers all candidate dates, fallback, and shorter-duration scenarios. These are application experiment settings, with no established provider allowance or live latency guarantee.

Before provider dispatch, the repository persists the next route reservation. Resume consumes the remaining command allowance. An interruption between reservation and dispatch may conservatively count an attempt whose dispatch is uncertain. Exact-time quotes stay in memory and are scoped to the immutable coordinates and transport mode of the command. Provider throttling stops new requests immediately. Completed candidates remain usable, with a warning when further comparison stops.

## Dates, preferences, and duration choices

- Automatic date selection retains the existing sufficient-condition fallback from the remaining day to tomorrow. Missing routes, throttling, and partial search cannot independently establish a time conflict. Explicit today offers tomorrow only when no dated visit is pinned.
- Tomorrow uses the next local calendar day. Future default availability is 09:00 through the local end of day. Date edits apply to both window endpoints. Source metadata distinguishes automatic resolution, timing answers, manual edits, and an already resolved proposal.
- The three-day comparison covers today and local day +1/+2. The two-to-three-day answer compares local day +2/+3. The visible date range and recorded attempted dates identify the scope. This implements the latter answer as a flexible range, while the Selected date control provides an explicit choice.
- Individual user timing preferences rank before the general preferred period. The general preference measures visit minutes outside its displayed period at fixed target durations. Model day parts remain separate soft start preferences, ahead of the compact-day objective and total waiting. These comparison policies remain product hypotheses for user evaluation.
- A model's range remains an estimate, and its midpoint supplies the target. A shorter estimate or an accepted minimum generates a reviewable alternative. The current implementation asks the traveller to apply a successful shorter scenario before changing the effective input. Exact overrides and booked-session durations remain fixed otherwise.
- Last entry is evaluated against entry on arrival or opening, while an activity can start later after permitted waiting. Session check-in compares against actual arrival. Bookings and access confirmations keep their dates and produce a conflict if a new trip date is incompatible.

## Semantic reuse and server compatibility

The native `hybrid_v4_1` method uses the existing Pocket `hybrid_v4` request contract for optional experience enrichment. Returned activity suggestions and estimated durations are validated before use. The device owns the v4.1 schedule and presents its native method independently of the provider's enrichment method.

The versioned semantic applicability key includes the selected place identity/details, preferences, main spot, date, and time zone. Order, departure, waiting, and duration overrides can change without invalidating the same semantic input. The original validated response retains its date and provenance in the account-scoped job store. Multiple date contexts can be retained by one job.

Model responses are reused only on their matching date/context. A cross-date route edit discards incompatible semantic input. User-provided or explicitly accepted durations can be carried to another date. A new date needing model estimates obtains its own stable semantic request identity. No date-independence metadata or new Pocket response shape is assumed. Raw provider hours remain session-only.

The repository's configuration revision and task cancellation checks reject late model or route results after suspension or account change, including asynchronous route edits and saved-trip refresh. Refresh preserves the user's availability window and flexibility, while an explicit departure edit updates the selected departure constraint. New optional persisted properties preserve decoding of earlier jobs and trips. Existing receipt fingerprints remain stable when the new optional input values are absent.

V4.1 sends the effective date through the existing structured provider planning context. It keeps date-source phrasing out of the generated preference prose so changing between a relative answer and the same explicit date preserves the semantic applicability key. Activity and day-part preference changes still invalidate their affected context.

## Verification

The package suite passes 111 tests, including 20 v4.1 tests, using synthetic providers. [V41PlanningTests](../../packages/C67Backend/Tests/Starter/V41PlanningTests.swift) covers typed date resolution and edit precedence, zero-model save/reopen/rename/reorder, semantic reuse and date invalidation, independent session and entry constraints, fallback protections and next-date route requests, shared request limits, throttling, reviewed duration changes, boundary departures, expansion beyond the first five candidates, preflight conflicts, optional model failure, cancellation/resume identity, durable route accounting, soft-target waiting, confirmed overnight access, saved-trip refresh consistency, model day-part priority, and candidate limits with zero provider calls. Overlapping booked sessions are rejected before requesting routes.

An independent four-stop reference enumerates all 24 orders for each of six synthetic directed static networks. Each case has four fixed 60-minute visits, a fixed departure, and a return to origin. The audit recomputes the selected schedule's full time independently. After adding first/last coverage to the stopping policy, all six selected schedules match that reference's compact-day optimum.

| Synthetic seed | Reference minutes | Selected minutes | Route attempts |
| --- | --- | --- | --- |
| 0 | 288 | 288 | 33 |
| 1 | 277 | 277 | 36 |
| 2 | 266 | 266 | 38 |
| 3 | 293 | 293 | 38 |
| 4 | 263 | 263 | 36 |
| 5 | 271 | 271 | 37 |

The earlier stop-after-success version matched four of six references with 17–19 attempts. Two schedules were 19 minutes above the reference. The refinement increases provider work to 33–38 attempts on these fixtures within the same total cap. This comparison establishes a small synthetic regression target, with human preferences and time-dependent live traffic left for evaluation.

The iPhone 18 Pro Max / iOS 27.2 Simulator has passed the complete 51-test `TripCreationTests` suite and four targeted UI flows. The UI cases cover v4.1 tomorrow selection with supplied durations and missing-duration recovery, plus the retained v4 schedule and fallback flows. Focused app/UI rechecks followed the native search refinements, and the final unit-only run includes the semantic-payload stability regression.

- Package log — `/private/tmp/c67-v41-package.log`.
- Combined app/UI run — `/private/tmp/c67-v41-ios-final.xcresult`, 54 passed.
- Targeted v4.1 app/UI recheck — `/private/tmp/c67-v41-ios-release-check.xcresult`, six passed.
- Latest targeted app/UI recheck — `/private/tmp/c67-v41-ios-complete.xcresult`, four passed.
- Final unit-only run — `/private/tmp/c67-v41-ios-unit-final.xcresult`, 51 passed.
- OpenAPI, fixture schemas, bundled copies, and synthetic SQL seed validation passed using the existing interpreter at `/Users/giovan/Programming/software/ios/C67/.venv/bin/python` against this checkout's `scripts/check_contracts.py`. Log — `/private/tmp/c67-v41-contracts.log`.
- Pinned SwiftFormat passed for all 672 Swift files. Local document references and `git diff --check` passed.

Live Luna/MapKit behavior for this revision, the original four real venues, physical-device behavior, and user preference quality remain unverified. The exact search domain is bounded, and the six reference cases establish no global optimality guarantee for arbitrary trips. The runtime requires the existing selected provider capabilities and preserves missing evidence explicitly.

## Handoff

Select the new method in Account to exercise v4.1. The implementation stays within the existing iOS and on-device package boundaries and uses the established Pocket API. Further provider and human evaluation should record route/semantic request counts and Next-to-review latency on the same real inputs, alongside failures and judged experience quality.
