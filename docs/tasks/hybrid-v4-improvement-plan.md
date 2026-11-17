# Hybrid v4 implementation plan

Status: Proposed, implementation pending

Prepared on 17 November 2026 for the engineers implementing Travelant's first-itinerary flow.

Application baseline: `97257924bc2c9e332d79b531b646469eb698401e` on `gi/ui-audit-improvements`.

Research workspace baseline: `cde1f1e4490296775c2989938ae79d17fd90fafb` on its separate `main` branch.

Owner and reviewers: to be assigned by the team across iOS, Domain/Data, and Pocket API.

## Outcome

Improve the first Hybrid v4 itinerary using the sources already available. A traveller's selected date and preferences reach the scheduler as structured input, failures lead to relevant recovery actions, and bounded route search finds more usable schedules for a measured request cost. Travellers can review duration compromises and uncertain access. Scheduling can complete without Luna when the supplied input is sufficient.

This document proposes six implementation workstreams. The baseline commits preserve the existing implementation. The proposed types, policies, acceptance cases, and experiments below have not been implemented or executed by this planning task.

## Baseline and available inputs

| Area | Owning source | Current behavior relevant to this plan |
| --- | --- | --- |
| Preference answers | [PreferenceAnswers](../../apps/ios/Features/Preferences/Presenter/PreferenceAnswers.swift), [TripTiming](../../apps/ios/Features/Preferences/Presenter/TripTiming.swift), [DayPart](../../apps/ios/Features/Preferences/Presenter/DayPart.swift) | Typed answers exist in presentation. Timing and day-part answers are included in prose by `TripCreationPresenter.preferenceText`. |
| Trip input and persistence | [PlanningModels](../../packages/C67Backend/Sources/Domain/Planning/PlanningModels.swift), [PlanningPreferences](../../packages/C67Backend/Sources/Domain/Planning/PlanningPreferences.swift) | Requests, effective job inputs, proposals, and saved trips carry dates, overrides, targets, and request identity. |
| Date fallback | [PlanningDayWindow](../../packages/C67Backend/Sources/Domain/Planning/PlanningDayWindow.swift), [PocketPlanningRepository](../../packages/C67Backend/Sources/Data/Planning/PocketPlanningRepository.swift) | Automatic drafts try the remaining day, then tomorrow after the implemented time-conflict checks. Explicit dates and dated visit constraints are protected. |
| Experience estimates | [PlanningExperience](../../packages/C67Backend/Sources/Domain/Planning/PlanningExperience.swift), [PocketOrdering](../../packages/C67Backend/Sources/Data/Planning/PocketOrdering.swift) | Luna provides activities, duration ranges, and day-part suggestions. Response validation binds the recommendation to a date, time zone, IDs, and model metadata. |
| Venue hours | [PlanningHours](../../packages/C67Backend/Sources/Domain/Planning/PlanningHours.swift), [Pocket hours service](../../server/pocket/src/hours.py) | Weekly provider hours, absence, and service errors are distinguishable. Raw provider hours are session-only. |
| Search | [V4Planner](../../packages/C67Backend/Sources/Data/Planning/V4Planner.swift) | Finite order/departure/wait search, five shortlisted validations by default, and a 72-call validation cap. The static proxy requests its own MapKit estimates before validation. |
| App entry and review | [TripCreationPresenter](../../apps/ios/Features/TripCreation/Presenter/TripCreationPresenter.swift), [schedule sheet](../../apps/ios/Features/TripCreation/View/PocketTripOptionsView.swift), [review](../../apps/ios/Features/Itinerary/View/ItineraryReviewView.swift) | Schedule controls and tomorrow fallback are integrated. Several downstream behaviors use `experiencePlan != nil` to select the trip flow. |

The integration checkpoint records targeted package, presenter, persistence, and Simulator evidence for date fallback with synthetic services. The original four-place failure still has no captured provider trace establishing its cause. See [integration evidence](hybrid-v4-integration.md) and [verification](../testing/verification.md).

## Shared behavior and implementation boundaries

- Preserve every selected place exactly once, all explicit order constraints, the selected endpoint, and user duration overrides. Main spot expresses importance and creates no implicit first-stop constraint.
- Keep dates and wall-clock choices in the trip's IANA time zone. Anchor relative-day resolution to the stored job creation time for retry stability.
- Keep hard constraints, soft preferences, source facts, model estimates, and missing evidence distinguishable. A known conflict and a missing ETA can coexist.
- Use MapKit for road estimates. A static screening estimate supplies candidate seeds and priorities. It cannot establish later traffic or prove a whole date impossible.
- Treat regular weekly hours as provisional for the selected date. Preserve the current session-only handling of raw provider hours and account-scoped trip storage.
- Retain the current six-stop application limit while testing search improvements within it. Any new search thresholds are experimental configuration with recorded values.
- Implement inside the existing VIPER, `C67Domain`, `C67Data`, and Pocket service boundaries. Domain values remain Foundation-only and `Sendable`.
- Make new persisted properties optional or provide explicit backward-compatible decoding. Keep old request fingerprints and stored receipts usable when absent fields decode. A retry of the same command retains its identity, and changed input creates a new command.

## 1. Feed structured timing preferences into scheduling

### Input and date resolution

Add optional structured timing values to `PlanningPreferences`. Map the existing presentation enums into Domain-owned values at the trip handoff. Retain `startsAt` and `finishBy` as the effective scheduling window. Record whether the window came from a schedule edit, an explicit timing answer, or automatic selection so reopening a draft preserves the traveller's choice.

| Existing answer | Proposed interpretation |
| --- | --- |
| Now | Explicitly choose today, with the existing departure lead time. Offer tomorrow if the selected policy cannot fit. |
| Tomorrow | Resolve the next local calendar day directly. The first attempt uses that date. |
| In 2–3 days | Offer the two dates at local day +2 and +3, then persist the chosen date. |
| Find the best day automatically | Show a proposed finite horizon of today through local day +2 before searching. Compare days with equivalent duration and preference policies, and report each day's incomplete evidence. |
| Skipped | Preserve the current automatic today-to-tomorrow behavior. |

The three-day horizon is a proposed initial experiment setting. The UI states the dates actually considered. A manually edited schedule takes precedence over an earlier relative timing answer. Dated visit confirmations and required targets remain pinned. A conflict between them and a new date produces a reviewable conflict before any provider request.

The date resolver should be a pure function near `PlanningDayWindow`, using the existing injected clock. Use the current tomorrow default of 09:00 through the local end of day when no explicit time overrides it. Apply resolution before job creation to show the date, then store the resolution anchor with the command. Reopening or polling an existing job uses its stored date rather than resolving the word tomorrow again. A new explicit planning action may resolve relative dates against its new job time.

### Day-part meaning and presentation

Preserve the existing user vocabulary and displayed ranges. The trip-level answer expresses a preferred exploration period. Represent it as a soft trip preference and measure scheduled visit minutes outside that period while holding visit durations constant. Display the resulting compromise when visits extend outside it. It must not become an identical mandatory start time for every stop.

This overlap policy is a proposed interpretation to evaluate with users. Keep an individual visit's explicit timing more specific than the general trip preference. Model-suggested day parts enter workstream 6 as separate, lower-priority soft preferences. Do not sum these different preferences into an unexplained weighted score. Record their deviations separately and propose the comparison order as explicit visit preferences, general trip period, model suggestions, then the existing compact-day objective.

Show the resolved date or search range near `Next`, with the existing Schedule action. The schedule sheet edits the same state. A manual time or date edit fixes the choice. Updating preference answers reconciles their source with existing edits and shows a conflict where necessary.

### Acceptance and checks

- Tomorrow means the next trip-local date on the first request, including when device and trip dates differ.
- The same relative-date command resolves identically after retry, midnight, app restart, and reopening.
- Editing the date overrides the earlier timing answer. A pinned reservation conflict names the visit and retains both inputs for correction.
- The day-part preference changes candidate comparison on fixed-duration examples while hard targets and endpoint deadlines remain satisfied.
- An older saved trip without the new values loads with its existing effective dates. Unchanged old receipts still match their original requests.
- Cover date resolution and comparison in package tests, handoff precedence in `TripCreationTests`, and date summary/edit/reopen in XCUITest.

## 2. Preserve diagnostics and offer relevant recovery

### Data and decision flow

Reuse `V4Issue`, candidate conflicts, unresolved evidence, quote outcomes, and search counters. Map them into a proposed Domain value, `PlanningScheduleAssessment`, with optional snapshots on `PlanningJob` and `PlanProposal`. A failed job needs this assessment even when it has no proposal. A saved trip retains its accepted proposal's assessment summary.

Record known conflicts, regular-hours conflicts, missing evidence, duration policy, candidates generated/evaluated/completed, calls by phase, search completion, and stop reason independently. Include affected place IDs and directed leg references where relevant. Store derived diagnostics and traveller confirmations without persisting raw provider-hour responses.

Introduce a typed failure carrying the existing error code and assessment. Catch it at the existing repository job boundary, persist both fields atomically, and continue presenting older string-only errors when no assessment exists. Generate explanations from the recorded evaluation. This avoids another Luna call for failure explanations.

### Recovery behavior

| Recorded finding | UI action and repository behavior |
| --- | --- |
| Visit targets exceed the available window | Offer a wider window, duration review, or the existing eligible tomorrow action. State whether durations were user choices or estimates. |
| Regular hours conflict | Name the venue and source limitation. Offer a different departure or explicit waiting allowance when an evaluated alternative supports it. |
| Directed ETA unavailable | Try a candidate using a different leg within the remaining budget. Explain any unresolved leg if search ends. |
| Search domain only partly evaluated | Report that a schedule has not been found among checked candidates and allow a bounded continuation. |
| Provider throttling | Stop further route calls for this attempt, preserve the draft, and provide an explicit retry action. |
| Unknown duration | Ask for the affected visit's duration or offer optional Luna assistance. |
| Unknown access with a complete route | Present a provisional schedule and the unresolved access confirmation. |

Keep automatic tomorrow eligibility tied to the existing sufficient time-conflict checks and the declared duration policy. A budget stop, missing ETA, or shortlist miss preserves uncertainty about today. A complete finite-domain failure only describes that domain and its assumptions.

### Acceptance and checks

- A known closure remains visible when another leg has no ETA.
- A shortlist miss and an exhausted budget never become a universal impossibility message or independently trigger tomorrow.
- Failure details survive job polling, persistence, and reopen. Old string-only failures still display a usable message.
- Each offered recovery uses the affected input. Changed input produces a new request, while status polling keeps the same request and creates no extra model calls.
- Package tests cover mixed conflicts and missing evidence. Presenter and UI checks cover the recovery action and preserved selections.

## 3. Search additional candidates within a measured total budget

### Preflight and candidate construction

Run route-independent checks once before requesting the static proxy. Examples include user-fixed duration totals exceeding the window, incompatible required visits, and an explicitly confirmed closure. Record regular-hours conflicts with their date applicability unresolved.

Keep the existing local candidate generator and ranking as the baseline. Add candidate departures around supplied opening boundaries and required or preferred targets, while retaining the coarse grid. Preserve these critical boundary seeds when coarsening optional grid points to meet the finite-domain cap, and record the domain actually checked. A backward calculation using the proxy proposes a seed. Validate that seed forward with departure-specific quotes, waiting, full visit duration, and the endpoint leg.

### Adaptive validation

Validate the current first batch, then consider another batch if a complete eligible schedule has not been found or an unresolved explicit user preference warrants further comparison. Deduplicate by order, departure, waits, and duration policy. Prefer candidates with different failing directed legs, orders, or departures based on the accumulated diagnostics. A failed quote at one departure does not eliminate the pair at every departure.

Keep successful complete candidates while expanding. Stop on cancellation, configuration/session invalidation, provider throttling, declared elapsed-time or request budget, or exhaustion of the declared finite domain. Persist a summary of why expansion stopped. A user-requested continuation creates a new operation with fresh estimates and an explicit budget.

Replace separate unaccounted phases with a per-command budget shared by proxy acquisition, validation, retries, sensitivity scenarios, candidate dates, and automatic tomorrow fallback. A later date cannot silently reset the command's allowance. Reserve capacity to try a complete baseline schedule, including its endpoint, before spending the entire allowance on proxy coverage. Record all actual `services.travel` calls, including unsuccessful calls and return legs. Experiment with limits against the checkpoint at matched total request budgets. The existing 72 validation calls are a historical experimental setting and establish no provider allowance.

Reuse exact matching quotes within the attempt using direction, coordinates, transport mode, and departure. Share the exact cache across candidate batches. Keep proxy-only values distinguishable from validated quotes. A temporary failure stays local to the attempt and cannot poison future user retries. Evaluate the value and cost of acquiring proxy pairs lazily before choosing that change.

### Acceptance and checks

- Recover the synthetic case where the first five candidates share an unavailable leg and a later order succeeds within budget.
- Recover a supplied target that needs a departure absent from the original coarse grid.
- Count proxy, final validation, failure, and endpoint requests in the reported total. No new calls occur after throttling or budget stop.
- Deduplicate candidates and exact-time quotes across batches. A quote for the opposite direction, different mode, or different departure cannot be reused as an exact result.
- Compare bounded search with an independently audited exhaustive reference on declared small synthetic domains. Record missed feasible cases, objective differences, and evaluation coverage.
- Exercise logout/configuration change and cancellation during expansion, and reject late results through the repository's existing revision checks.

## 4. Evaluate duration ranges and review compromises

### Duration semantics

Continue using the existing user override as an exact duration. Keep model `minMinutes` and `maxMinutes` as labelled estimates. Make the target policy explicit because `suggestedSeconds` currently uses the range midpoint.

Add an optional user-accepted minimum for a visit only when the traveller chooses flexibility. Preserve the existing target seconds and provenance. An absent accepted minimum leaves the current override exact. An estimate's minimum becomes an offer for review before it changes the accepted plan.

### Evaluation and UI

Start from the same target-duration schedule. When it fails, identify a consequential visit and evaluate a limited shorter-duration alternative within the shared search budget. Retain all places and explicit targets. If the range of estimated durations changes the feasibility or selected departure, attach that sensitivity to the assessment.

Show the affected visit, original target, proposed duration, source, and scheduling consequence. Accepting a compromise updates the structured input, creates a new command, and reruns the final schedule with the chosen durations and fresh affected ETAs. Saving remains attached to the accepted proposal and its effective input. The review can show an unaccepted alternative without replacing that proposal.

Use lower/target/upper scenarios in the synthetic experiment to expose fragile schedules. Report available time before a deadline in minutes when calculable. Avoid inventing a probability of arriving on time from these scenarios.

### Acceptance and checks

- A user-set exact duration never changes during search or fallback.
- A model-minimum alternative remains labelled and pending until accepted. Rejecting it retains the original target and selections.
- A duration edit recomputes downstream departure-specific ETAs, waiting, hours, and return time.
- The accepted durations, policy, date, and explanation survive save/reopen.
- Cover target-fails/minimum-fits, all scenarios fail, maximum-duration overrun, and fixed reservations. Hold duration policy constant when comparing search algorithms.

## 5. Ask targeted access and session questions

### Evidence representation

Reuse `PlanningVisitConfirmation` for traveller-confirmed access on one date and keep provider lookup status distinctions. Extend confirmed access with an optional last-entry cutoff where supplied. Represent an activity session separately with its explicit start/end and optional arrival requirement. Opening access, activity start, and last entry retain their separate meanings.

Map a user-supplied session into the existing hard visit-target machinery and activity duration. The internal `V4Window.last_entry` can receive a known cutoff. Overlapping regular windows do not establish activity availability. A traveller's all-day access confirmation applies only to that visit/date and is labelled with its source.

### Question selection and date handling

Keep unknown hours compatible with a provisional schedule. Ask a question when the missing answer determines whether a useful candidate can satisfy the request, such as a booked activity start or an access window for a pinned visit. Show affected visits first and provide a way to retain the uncertainty where scheduling can continue.

Reuse `PocketVisitAvailabilityView`, initializing it from the effective trip date and time zone. Replace its independent tomorrow default. Prefilled example hours remain editable form values until the traveller explicitly confirms them. Date changes invalidate confirmations or sessions for the old date and request review. Never shift a dated booking automatically to make another date fit.

### Acceptance and checks

- Unknown provider hours retain the stop and a provisional access warning.
- Provider unavailable, temporary error, confirmed closure, and traveller-confirmed access remain distinct after mapping.
- A venue's regular opening window cannot establish an activity session. A supplied session and last-entry cutoff affect the schedule independently.
- Confirmation uses the effective trip date, remains trip-scoped after saving, and requires review after a date change.
- Category-hour display hints remain labelled estimates and never enter the scheduler as confirmed venue hours.
- Cover the access view, date invalidation, overnight and split windows, all-day confirmed access, and a session within building hours that is unreachable by its cutoff.

## 6. Make Luna optional and reuse applicable semantic estimates

### Native scheduling entry and normal app flow

Separate construction of scheduling input from `PlanningExperiencePlan`. Build V4 stops from selected IDs, user durations/targets, available hours, and optional semantic estimates. Use the same scheduler, diagnostics, identity, and persistence path for both input sources.

Change the current `requestPlan` ordering branch so Hybrid v4 can start its persisted asynchronous job without requiring `services.order`. It currently sets `usesLuna` and AI-processing flags when an ordering service exists. Preserve the user's processing choice and keep the job lifecycle available for local-only scheduling and recovery after restart.

Select the scheduling path from the requested method and actual capabilities. Review, edits, reorder, save, reopen, route refresh, start-trip eligibility, and proposal expiry need a V4-aware check instead of relying solely on `experiencePlan != nil`. Reuse a focused proposal capability computed from the existing method/first-itinerary metadata. Keep optional model metadata truthful when no model supplied the plan. Update the pre-request disclosure to describe the selected processing path and the data sent to each service. Optional semantic assistance follows the traveller's existing AI-processing choice.

### Zero and one-call behavior

- With sufficient user durations and timing input, run the deterministic path and generate explanations from the assessment. An unknown activity description can remain unknown while timing is computed.
- Offer one semantic call for unresolved activities, estimated duration ranges, or suggested day parts when the traveller chooses assistance. Validate every selected ID, range, source reference, and returned vocabulary through the existing boundaries.
- Map valid model day parts to soft visit-start preferences in the trip time zone, below explicit user preferences. Flexible/unknown values create no target. Keep the inference label in the review.
- If assistance fails, preserve the selected places, user input, and any usable deterministic or provisional result. Identify the remaining missing duration where a complete schedule cannot be formed.

### Reuse and wire compatibility

Within the same applicable context, reuse estimates while order, waiting, or departure candidates change. Invalidate on semantic input changes such as selected place identity, activity intent, and relevant preferences. User overrides take precedence over retained estimates.

The existing response validator binds a full Luna recommendation to `candidateDate`. Extract reusable activity/duration estimates into a separate provenance-bearing value. Keep the original response date and references intact. Default old responses to date/context-dependent. Reuse across dates only for user-accepted estimates or an explicitly supported independence scope. Date-specific weather, light, access, and session facts need their own refresh or an unresolved status.

The initial zero-call path requires no new model endpoint. Use the existing hours and weather service capabilities where applicable, and attach light context only when valid for the effective date. Do not call the model merely to refresh context. If explicit dependency metadata is added to `/v1/order`, negotiate an opt-in response version and update OpenAPI, Swift decoding, server validation, and fixtures together. Older clients receive their existing response shape. Missing server support retains a conservative current-date reuse policy.

The semantic artifact's fingerprint is separate from the full planning command fingerprint. Editing the schedule still creates a new planning command. A repeated semantic request reuses its stable request identity. Persistent reuse, if needed for resume, stays in the existing account-scoped store with a versioned applicability fingerprint. Session changes clear in-memory reuse and reject in-flight results.

### Acceptance and checks

- All supplied durations plus sufficient timing input complete normal Next → review → edit/reorder → save → reopen with exactly zero model calls.
- The zero-call path works when `services.order` is absent and respects the existing Pocket account/session boundary.
- One unresolved duration uses at most one semantic request for the context. Polling and additional candidate batches create no extra model calls.
- A failed optional call preserves a usable deterministic result or identifies exactly what remains unresolved.
- A model day-part suggestion remains soft and cannot displace an explicit user time or create venue-opening facts.
- Cross-date reuse retains source provenance, rejects old date-dependent advice, and refreshes affected routes and access. Old responses never acquire an invented independence claim.
- Resume after restart preserves the zero/one-call path and request identity. Logout or account switch prevents a late result from changing the new session.
- Include server compatibility checks only when the opt-in metadata shape is introduced. Retain existing Luna and Hybrid v2 contract behavior.

## Delivery order and checkpoints

| Batch | Deliverable | Dependencies | Reviewable completion |
| --- | --- | --- | --- |
| A | Structured timing and visible resolved date, workstream 1 | Baseline date fallback | Date resolution and user-edit precedence pass package, presenter, and UI checks. |
| B | Structured diagnostics and recovery, workstream 2 | Baseline evaluator | Failed jobs retain actionable assessments through persistence and reopen. |
| C | Adaptive search, workstream 3 | B; structured timing from A for boundary seeds | At matched budgets, report reference misses, recovered cases, calls, and elapsed time. |
| D | Reviewed duration compromises, workstream 4 | B and C | Shorter alternatives remain pending until accepted and preserve fixed durations. |
| E | Targeted access/session confirmation, workstream 5 | A and B | Confirmation matches the effective date, with distinct session and entry constraints. |
| F1 | Zero-call V4 through save/reopen, workstream 6 | A and B | End-to-end synthetic tests record zero model calls and preserve the normal trip flow. |
| F2 | Optional semantic call, soft day parts, and scoped reuse, workstream 6 | F1; C/D/E for complete integration | Model failure recovery, applicability, opt-in contract changes if used, and account/retry checks pass. |

Keep a local commit for each completed batch. F1 can follow B when reducing model use is the immediate priority. The initial implementation can otherwise follow the table. New policy values and comparison order remain explicit experiment settings until their outcomes are reviewed.

## Verification and evaluation

### Regression and comparison cases

Extend the existing package and app test helpers. Freeze complete synthetic inputs, including local date/time zone, all selected IDs, durations with sources, hours, targets, origin/endpoint, departure choices, waiting, directed travel profiles, and budgets. Reuse the isolated [v4 lab](../../../poc/hybrid-v4-lab/README.md) and independent auditor for algorithm comparisons. Version the new behavior so the existing Swift/Python replay fixtures continue to identify their original planner policy.

| Case | Required evidence |
| --- | --- |
| Explicit tomorrow or schedule edit | First request and saved/reopened trip use the chosen local date. |
| Today fits, today too short, tomorrow also fails | Correct date behavior and explanation under the declared duration policy. |
| Pinned booking and conflicting date | Both inputs survive and the affected visit is identified. |
| Unknown hours with complete ETA | Provisional schedule with all selected stops. |
| Known closure plus unavailable ETA | Both the conflict and missing leg remain visible. |
| Initial five candidates fail, later candidate works | Bounded recovery with measured total calls. |
| Useful departure outside coarse grid | Boundary seed validated with time-specific quotes. |
| User duration fixed; estimate range changes fit | Fixed input preserved and compromise awaits acceptance. |
| Building open, activity/session unavailable | Session or entry conflict remains explicit. |
| Fully supplied input, model absent or failing | Zero-call normal flow and useful failure recovery. |
| Date change after semantic estimate | Applicable estimates retained with provenance, date-bound evidence invalidated. |
| Retry, restart, duplicate tap, cancel, logout, account switch | Stable request identity, coherent persisted state, and no late cross-session mutation. |

Measure time from Next to review, phase timings, model calls, all ETA calls, completed candidate count, conflicts missed/reported, shortlist recovery, date correctness, and accepted compromises. Compare algorithms on identical duration inputs. Compare zero-call and semantic-assisted outputs on the same trip intent while recording differences in estimate source.

Use independent human review of fresh scenarios for activity plausibility, visit duration, sequence, waiting, preferred time, and explanations. Exact order equality and a model's self-assessment cannot establish human preference quality. Any four-place screenshot reproduction needs its actual selected date, constraints, provider outcomes, and rejection trace before assigning a cause.

### Commands and acceptance environments

Run commands from this application repository when the corresponding implementation batch exists. For individual Swift Testing filters in Xcode, include the trailing `()` and confirm the executed test count.

```sh
swift test --package-path packages/C67Backend
python3 scripts/swift_format.py --check
PYTHONPATH=server/pocket/src python3 -m unittest discover -s server/pocket/tests -p 'test_*.py'
.venv/bin/python scripts/check_contracts.py
python3 scripts/simulator_destination.py
git diff --check
```

Use the documented C67 scheme and an available iPhone Simulator for affected app unit/UI tests, with `C67_DATA_MODE=mock` and Simulator signing settings from [repository instructions](../../AGENTS.md). Record device/runtime, selected tests, actual test count, and result bundle. Contract and server checks apply when their payloads or behavior change. Local documentation checks for this plan do not constitute implementation acceptance.

After synthetic acceptance, compare live first-itinerary runs with identical input and capture phase timings and actual provider failures. Include a repeatable four-place case and varied time windows before expanding beta availability. Record real-provider observations separately from deterministic fixture expectations. Update [verification](../testing/verification.md) with the results of each implemented batch.

## Product choices to review during implementation

The proposed initial choices are the three-day automatic search horizon, visit-time overlap for a general day-part preference, comparison priority among soft preferences, and explicit acceptance of shorter durations. They are sufficiently specified for isolated implementation and testing. Record changes when user evaluation supports a different policy.

Request and elapsed-time budgets should be selected from matched-budget experiments and provider observations. Reuse metadata defaults conservatively when the response cannot establish applicability. Access and session questions are conditional on an actual unresolved scheduling decision.

## References

- [Current v4 integration checkpoint](hybrid-v4-integration.md) and [hours integration](hours-hybrid-integration.md).
- [Native architecture](../architecture/architecture.md), [Pocket integration guide](../guides/pocket-engine-integration.md), and [task workflow](../ai/workflow.md).
- [Shared API contract](../../contracts/api/openapi.json) and [Pocket service](../../server/pocket/README.md).
- Workspace-only research at the separately committed baseline, [scheduling synthesis](../../../docs/research/hybrid-v4-reasoning-synthesis-2026-11-17.md), [evidence and intent](../../../docs/research/hybrid-v4-evidence-primary-2026-11-17.md), and [chat guardrails](../../../RULES-optimasi-luna.md).
