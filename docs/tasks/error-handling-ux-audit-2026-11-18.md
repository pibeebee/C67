# Apple HIG Audit Summary: Travelant error handling

Status: Audit complete; remediation is proposed and has not been implemented.
Owner: C67 engineering / product design.
Date: 18 November 2026.
Branch: `gi/ui-audit-improvements`; application baseline `f865adf` plus the existing local test/evidence work.

The user requested screen/code mapping, an inventory of error-handling needs, a UX plan, and a report without code changes. This task adds only this report and its [source inventory](error-handling-source-inventory-2026-11-18.csv). It does not change application, engine, server, contract, configuration, or test code. No build, test, deployment, or Simulator interaction was performed for this audit.

## Project profile and evidence

- UI: SwiftUI, VIPER-style presenters/interactors, C67Domain values, and C67Data adapters around PocketEngine.
- Baseline: iOS 18 minimum, Swift 6 language mode, iPhone and iPad target families from [project.yml](../../apps/ios/project.yml). Installed Xcode is 27.2, build 27B52. No runtime/device configuration was exercised in this audit. Earlier iOS 27.2 Simulator evidence remains historical.
- Main entry: [C67App](../../apps/ios/App/C67App.swift) resolves dependencies and, in authenticated Pocket mode, restores an account and opens its local store. [PlanningAssembly](../../apps/ios/Features/Planning/Assembly/PlanningAssembly.swift) normally opens Home; `--planning-workspace` opens the earlier workspace. `--legacy-catalog` selects the preserved Discovery branch when its routing condition is reached. Its precedence differs from authenticated Pocket routing; it is not a normal Pocket tab.
- Main navigation: Trip / History; full-page creation; recommendation and place-selection sheets; itinerary review; saved trip; moving / arrived / completed trip states; Account and Pocket settings.
- Inventory: all **119 Swift files outside test and preview directories** in `apps/ios` were scanned for declarations and error/state signals. The CSV records each path, feature, role, and signal line. It finds 85 `View` declarations, including components, wrappers, embedded forms, and some previews inside `#if DEBUG`; **85 is not a screen count**. Critical operation paths were then traced manually through their views, presenters, domain errors, persistence, provider adapters, and selected Pocket server handlers.
- Further code evidence: existing app/package tests were inspected for preservation, retry identity, permission, cancellation, and v4.1 diagnostic intent. They were not executed here. Relevant references are [design system](../product/design-system.md), [v4.1 implementation](hybrid-v41-integration.md), and [prior Pocket request recovery](pocket-order-recovery.md).
- Overall confidence: **Confirmed** for cited static behavior; **Likely** for the active-arrival repeat consequence. There are no new runtime-verified findings.

## Apple sources checked

Official topic content was retrieved on **2026-11-18** through the Apple documentation connector. Apple web pages initially returned JavaScript shells; the connector supplied the topic content. The HIG root was opened but its content extraction was unavailable; findings use the accessible exact topics below. Apple page update dates were not consistently available; Loading lists a 9 June 2025 revision. Guidance is current as retrieved and is not a requirement to raise the deployment minimum or adopt a new visual material.

| Topic | Official source | Use in this audit |
| --- | --- | --- |
| iOS context | [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios) | Preserve task continuity on a mobile device. |
| Interruption and recovery copy | [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) | Reserve modal interruptions for consequential, actionable situations; use specific language and actions. |
| Contextual state | [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) | Match feedback prominence to the significance of the event and keep it near the affected content. |
| Waiting and partial content | [Loading](https://developer.apple.com/design/human-interface-guidelines/loading) | Retain useful content and communicate waiting truthfully. |
| Form validation | [Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data) | Explain required values and identify errors while editing. |
| Permissions | [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy) | Respect denied access and explain the capability being requested. |
| Accessible feedback | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Preserve information beyond color and verify assistive-technology tasks. |

Choices such as one primary recovery action, a detail sheet for multiple schedule conflicts, and the proposed issue model are **product/usability recommendations**, not Apple-mandated component designs.

## Findings, ordered by task impact

### E01 — Retry can perform a different operation, including saving a trip

- Severity: **Critical**. Confidence: **Confirmed**. Basis: **Usability**. Area: **State Handling**. Priority: **Now**.
- Evidence: [ItineraryReviewView](../../apps/ios/Features/Itinerary/View/ItineraryReviewView.swift), lines 29–35 and 49–50. `retryAction` recognizes pending departure/order edits, then defaults to `save()` for any other `presenter.error`. The independent refresh-estimates callback does not record an operation type. [PlanningPresenter](../../apps/ios/Features/Planning/Presenter/PlanningPresenter.swift), lines 260–270, puts route-refresh failure into the same error property.
- Current behavior: the callback for “Try again” after a route refresh can be the save callback. The default also covers errors not identified by the two pending edit fields.
- User impact: an action intended to retry estimates can persist a trip instead. The callback mismatch is established statically; an actual accidental save was not observed.
- Direction: carry the failed operation and its identity into presentation. Offer “Retry route update,” “Save trip again,” or “Generate a new plan” only for their corresponding operations. Never infer a save intention from the existence of an error.
- Relevant guidance: [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) and [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts). The specific callback correctness requirement is a usability conclusion.
- Validation: fail each review operation independently and assert that its recovery performs only that operation, with no unexpected apply, save, model call, or navigation.

### E02 — One shared error property gives unrelated screens the wrong context

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **State Handling**. Priority: **Now**.
- Evidence: [PlanningPresenter](../../apps/ios/Features/Planning/Presenter/PlanningPresenter.swift), line 29 and the `load`, `request`, `apply`, `event`, `deleteTrip`, and route-edit catches. [TripHomeContentView](../../apps/ios/Features/Home/View/TripHomeContentView.swift), lines 22–34, uses this property for “Trips couldn’t be loaded” whenever no first-itinerary job exists, even if trips are already present. Saved/active views consume the same property.
- User impact: an operation-specific error can replace the trip list or appear on another surface with a load-oriented retry. A list failure, a failed deletion, and a planning failure need different next actions.
- Direction: scope issues to operation, screen/resource identity, and session. Separate initial-load failure from refresh failure. Keep an already loaded list visible after a refresh or unrelated operation fails; clear only the issue resolved by a successful action.
- Relevant guidance: [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Loading](https://developer.apple.com/design/human-interface-guidelines/loading).

### E03 — Automatic arrival may repeatedly resend after an event failure

- Severity: **Moderate**. Confidence: **Likely**. Basis: **Usability**. Area: **State Handling**. Priority: **Now**.
- Evidence: [TripProgressView](../../apps/ios/Features/ActiveTrip/View/TripProgressView.swift), lines 35–45, sends `.arrive` both when arrival becomes ready and when busy becomes false while arrival remains ready. [TripNavigation.stop](../../apps/ios/Features/Planning/Platform/PlanningPlaces.swift), line 246, stops tracking without clearing `arrivalReady`. A failed [event](../../apps/ios/Features/Planning/Presenter/PlanningPresenter.swift), lines 347–361, leaves the current stop unchanged and eventually releases busy.
- Inference: the failure conditions can satisfy the busy-change handler again and repeatedly resend the event. The pending event ID reduces duplicate-write risk but does not provide a visible bounded recovery policy. A runtime loop has not been observed.
- Direction: one automatic submission per arrival attempt, followed by an explicit failed/uncertain state. Preserve manual arrival and navigation; allow a deliberate retry using the existing event identity. Keep event failure separate from GPS/route failure.
- Relevant guidance: [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback).
- Required validation: inject a persistent `.arrive` failure, count event calls while the view stays visible, and verify that recovery waits for user action rather than following every busy transition.

### E04 — v4.1 recovery is a dense banner without a clear first action

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **State Handling**. Priority: **Now**.
- Evidence: [TripCreationView](../../apps/ios/Features/TripCreation/View/TripCreationView.swift), `planningErrorBanner`, lines 139–185. It combines the broad error, up to four assessment messages, every duration alternative, availability review, tomorrow, schedule editing, and generic retry/status/settings controls in one top inset. [PlanningScheduleAssessment](../../packages/C67Backend/Sources/Domain/Planning/PlanningScheduleAssessment.swift) already contains place, date, reason, evidence, and search information.
- User impact: people must interpret several messages and determine which action can change the outcome. The four-message cap can hide additional places without a visible total. A repeated search is offered alongside fixes even when the input remains deterministically invalid.
- Direction: short issue summary at the failure location, one recommended next action, one secondary action, and “View details” for the complete assessment. A recovery sheet groups issues by affected place/date, links directly to the relevant field, and separates confirmed conflicts from incomplete evidence and limited search. Keep the selected places and dates visible.
- Relevant guidance: [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback). The exact action hierarchy is a design recommendation.

### E05 — Form errors do not consistently identify the field that needs correction

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **Forms**. Priority: **Now**.
- Evidence: [PocketScheduleOptionsSheet](../../apps/ios/Features/TripCreation/View/PocketTripOptionsView.swift), lines 62–72, rejects invalid access intervals, last-entry cutoffs, or session/check-in times. Line 121 always describes a finish/departure problem. [PocketVisitAvailabilityRow](../../apps/ios/Features/TripCreation/View/PocketVisitAvailabilityView.swift), lines 72–77, disables confirmation for an invalid interval without a field-specific explanation. Save-name and edit-name dialogs disable their actions for an empty or overlong name without explaining the 120-character maximum.
- User impact: a correct trip window can be blamed for a venue/session error elsewhere in a collapsed form. Disabled buttons can require guessing. The current form checks are useful and should be retained.
- Direction: per-field/per-place validation, an accurate section summary, a visible reason for unavailable continuation, and focus/scroll to the first invalid value. Keep booking dates explicit; validate in the trip time zone. Distinguish required confirmation from invalid data. Name fields need a clear length constraint. A draft/apply/cancel model for schedule edits is a proposed follow-up, not an implemented behavior.
- Relevant guidance: [Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data).

### E06 — More than six places is discovered late, with limited direct recovery

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **Forms**. Priority: **Now**.
- Evidence: [TripCreationPresenter](../../apps/ios/Features/TripCreation/Presenter/TripCreationPresenter.swift), lines 121–124, 150–155, and 278: selected places are retained without a selection cap, and the schedule-method limit is checked during planning. The banner suppresses generic retry for this handoff but does not add a dedicated “Review places” action.
- User impact: v4/v4.1 users learn the limit after selecting places and reaching the main-spot step. The places are preserved, but the path to resolving the limit is indirect.
- Direction: disclose the selected method's capability near the selection count. On failure, open My Places directly and let the user choose the subset for this trip or change to an applicable method. Preserve the full session selection and never silently remove places. Do not impose the v4.1 limit on every other method.
- Relevant guidance: [Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data).

### E07 — Search surfaces blur a failed search, old results, and a genuine empty result

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **State Handling**. Priority: **Next**.
- Evidence: [TripCreationPresenter.search](../../apps/ios/Features/TripCreation/Presenter/TripCreationPresenter.swift), lines 158–175, preserves earlier results on failure while replacing the error with a generic query suggestion. [AddPlacesView](../../apps/ios/Features/TripCreation/View/AddPlacesView.swift) still renders its results beneath the failure view. [PlanningSearchSheet](../../apps/ios/Features/Planning/View/PlanningRootView.swift), lines 305–332, shows a generic search instruction even for a submitted query with no results, and has no explicit retry action. Its [PlanningPlaceSearch](../../apps/ios/Features/Planning/Platform/PlanningPlaces.swift), lines 111–130, maps provider failures to one message.
- User impact: earlier-query results can look current; changing a query is not a remedy for a connection failure. Starting-point search and Add Places provide different recovery experiences.
- Direction: track the submitted query and the query associated with displayed results. Distinguish idle, loading, results, empty, interrupted, and failed states. Keep selections; label retained results if a refresh fails. Offer retry of the same query for transient failures and query/location refinement for true empty results.
- Existing strength: [MapKitTripPlaceSearch](../../apps/ios/Features/TripCreation/Platform/MapKitTripPlaceSearch.swift), lines 9–11 and 55–58, already treats `placemarkNotFound` as an empty result and retains usable first-search results when enrichment fails. Extend that distinction consistently rather than replacing it.
- Relevant guidance: [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Loading](https://developer.apple.com/design/human-interface-guidelines/loading).

### E08 — Recommendations can show failure and empty-state recovery simultaneously

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **State Handling**. Priority: **Next**.
- Evidence: [PlacesRecommendationsView](../../apps/ios/Features/Recommendations/View/PlacesRecommendationsView.swift), lines 95–112: an error gets a retry, then an empty batch independently gets “No recommendations yet” and another retry. Partial-query warnings render individually. [TripCreationInteractor](../../apps/ios/Features/TripCreation/Interactor/TripCreationInteractor.swift), lines 109–130, correctly preserves successful query groups.
- User impact: an unavailable service can appear to have returned no matches, with repeated actions and a long warning stack.
- Direction: make first-load failure and a successful empty result mutually exclusive. For partial success, retain the results and summarize missing searches in one contextual notice with expandable details. A failed refresh keeps current results and selections with one refresh action.
- Relevant guidance: [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Loading](https://developer.apple.com/design/human-interface-guidelines/loading).

### E09 — Startup and missing-trip states have no direct recovery action

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **State Handling**. Priority: **Now** for storage/session entry, **Next** for missing-trip destinations.
- Evidence: [C67App](../../apps/ios/App/C67App.swift), configuration failure and `PocketAuthenticatedWorkspace`, uses `ContentUnavailableView` with a description but no retry/account action. [SavedTripView](../../apps/ios/Features/SavedTrip/View/SavedTripView.swift), lines 50–52, and [TripProgressView](../../apps/ios/Features/ActiveTrip/View/TripProgressView.swift), lines 49–51, ask users to return/refresh without a direct action. A compile-time configuration problem is distinct from a retryable store-read failure.
- User impact: instructions alone require people to infer navigation or restart the app; a storage failure occurs before the normal workspace is usable.
- Direction: tailored entry states: retry a transient store read, offer account access where available, and provide a safe diagnostic/support path for unrecoverable configuration or decoding failure. A missing trip offers “Back to trips” and refresh/sign-in only when applicable. Preserve the store; never propose automatic deletion/reset as recovery.
- Relevant guidance: [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback).

### E10 — Important provisional-plan information is buried with general details

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **State Handling**. Priority: **Now** for information affecting plan interpretation.
- Evidence: [ItineraryMapView](../../apps/ios/Features/Itinerary/View/ItineraryMapView.swift), lines 40–68, puts v4/v4.1 warnings under a collapsed “Trip details” disclosure. [ItineraryListView](../../apps/ios/Features/Itinerary/View/ItineraryListView.swift) displays regular-hours comparison but does not directly render the structured `scheduleAssessment`. That assessment can distinguish incomplete access evidence, limited search, and optional Luna failure.
- User impact: a usable provisional plan can appear fully verified unless details are expanded. Conversely, optional missing data should not be presented as a fatal trip failure.
- Direction: a concise visible plan-status summary: ready, ready with checks, or unable to complete. Name the affected visits and show the complete evidence in details. Missing regular hours is an uncertainty, not proof of closure. Unknown weather or optional Luna suggestions should remain nonblocking when the schedule is otherwise usable. Preserve existing provenance and attribution.
- Relevant guidance: [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback).

### E11 — Map, hours, and weather failures lack component-specific recovery

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **State Handling**. Priority: **Next**.
- Evidence: [ItineraryMapView](../../apps/ios/Features/Itinerary/View/ItineraryMapView.swift), lines 25–27 and 102–115: partial route failure has a text note but no reload; the expanded map omits that note. [ItineraryListView](../../apps/ios/Features/Itinerary/View/ItineraryListView.swift), lines 180–190 and 253–267: temporary hours errors are cached for that view without a targeted retry. [DepartureWeatherLoader](../../apps/ios/Features/Planning/Platform/PlanningPlaces.swift), lines 26–49, tries a fallback but exposes no failure category; the departure card has a useful generic unavailable state.
- User impact: people cannot tell whether retry is useful or whether a forecast is outside the supported horizon. They may regenerate the entire plan to fix one optional component. A missing polyline is different from an unverified travel estimate used by the scheduler.
- Direction: local loading/partial/unavailable states and local retries for polylines, hours, and forecast. Label retained information and affected segments. Preserve the itinerary; do not rerun Luna or the scheduler just to redraw a map or refetch optional content. Retry temporary lookup errors; explain permanent lack of data without a futile retry.
- Relevant guidance: [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Loading](https://developer.apple.com/design/human-interface-guidelines/loading).

### E12 — Account recovery actions are not matched to the failed account operation

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **Forms**. Priority: **Next**.
- Evidence: [AccountView](../../apps/ios/Features/Account/View/AccountView.swift), lines 39–42, always offers “Check session again” for its error. [AuthenticationError](../../packages/C67Backend/Sources/Domain/Auth/TravellerAuthentication.swift), lines 53–84, distinguishes invalid credentials/email, weak password, delivery failure, expired link, rate limit, expired session, and partial sign-out. Only some cases are helped by session refresh. A server status number is included in user-facing auth copy.
- User impact: people can repeat the wrong action after a bad password, expired email link, or failed delivery. HTTP/configuration terminology asks them to interpret implementation details.
- Direction: email/password field validation, a sign-in-specific retry, resend/request-new-link actions, wait guidance for limits, and session restoration only for session failures. Keep clear partial sign-out messaging and privacy-preserving email notices. Clear secure input deliberately; do not persist passwords to improve recovery convenience.
- Relevant guidance: [Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts).

### E13 — Waiting, interrupted work, and confirmed failure need distinct presentation

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **State Handling**. Priority: **Now** for request identity, **Next** for loading presentation.
- Evidence: [PlanningPresenter.receive](../../apps/ios/Features/Planning/Presenter/PlanningPresenter.swift), lines 221–254, intentionally has no overall UI polling deadline for reasonable-order jobs. [TripCreationView](../../apps/ios/Features/TripCreation/View/TripCreationView.swift), lines 24–39, provides “Continue later,” but the processing cover passes no current `presenter.progress` or elapsed/slow state. The [draft row](../../apps/ios/Features/Home/View/TripHomeContentView.swift), lines 97–102, labels every failed draft “Tap to retry,” even when input correction is required.
- User impact: slow work, an unreachable server, and a job that has definitively failed can feel similar, yet they require checking an existing request, waiting, or creating a new one.
- Direction: explicit working / taking longer / status unknown / failed states. Use actual operation context; do not invent percentages, completion times, or model/weather stages. “Check status” keeps the existing identity; “Start a new attempt” follows confirmed failure or a changed input. Continue later preserves the draft, without promising arbitrary execution while iOS suspends or terminates the app.
- Relevant guidance: [Loading](https://developer.apple.com/design/human-interface-guidelines/loading), [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback).

### E14 — Provider distinctions are lost before the UI can choose a good recovery

- Severity: **Moderate**. Confidence: **Confirmed**. Basis: **Usability**. Area: **Other**. Priority: **Next**.
- Evidence: [PocketResearchClient.fetch](../../packages/C67Backend/Sources/Data/Planning/PocketServices.swift), lines 203–213, collapses HTTP 408, 429, and 5xx into `.unavailable`. Its hours lookup catches all errors as `temporary_error`. [PocketOrdering](../../packages/C67Backend/Sources/Data/Planning/PocketOrdering.swift), lines 112–147, reduces a failed order job to `ORDER_GENERATION_FAILED`. The [Pocket server job handler](../../server/pocket/src/server.py), lines 195–214, retains coarse `error`/`errorKind` values rather than a stable user-recovery contract.
- User impact: presentation cannot reliably distinguish throttling from outage, lack of permission from a failed optional lookup, or a failed model result from other failed jobs.
- Direction: preserve distinctions already available in HTTP status and local errors in the client adapter first, including server-provided retry timing when present. Do not invent countdowns. A future stable server error-code/retryability contract could improve diagnosis; it is optional later work, not a prerequisite for fixing E01–E13. Do not expose raw exception names, provider payloads, tokens, or endpoints as the default message.
- Relevant guidance: [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts); the adapter/model proposal is an engineering recommendation.

## Screen and state map

Rows group actual navigation surfaces, forms, and embedded states; shared components are not counted as separate product screens. The CSV maps the remaining supporting declarations. “Needs handling” includes existing behavior to preserve, not only defects.

| Surface / flow | Code owner | Needs handling | Proposed presentation / recovery | Findings |
| --- | --- | --- | --- | --- |
| Launch configuration | `C67App.StarterRootView` | Dependency/configuration failure | Dedicated unavailable state, accurate next step, safe diagnostics; do not promise retry repairs a build setting | E09 |
| Account restore / Apple welcome | `C67App.PocketAuthenticatedRoot` | Restoring, expired session, sign-in failure, cancellation | Restore state; contextual sign-in action; cancellation stays silent; preserve account separation | E09, E12 |
| Per-account storage entry | `C67App.PocketAuthenticatedWorkspace` | Decode/read/protection failure | Retry when meaningful; account/support access; preserve stored file | E09 |
| Splash | `SplashView`, `SplashOverlay`, `SplashTimeline` | Transition/interruption | No standalone network-error alert; reveal the root's meaningful entry state | Preserve |
| Home Trip tab | `TripHomeRootView`, `TripHomeContentView` | Initial load, refresh, offline, location denied/unavailable | First-load state versus retained-list notice; manual start-point choice and Settings access | E02, E09 |
| History tab | Same Home content, `isHistory` | Empty versus failed load, stale list | Real empty state only after successful load; keep prior items on refresh failure | E02 |
| Draft row / resume | `TripDraftRow`, `openFirstItinerary` | Running, interrupted, failed, ready | Open draft details; distinguish check status, fix inputs, and new attempt | E04, E13 |
| Starting point / end point / Add a place search sheet | `PlanningSearchSheet`, `PlanningPlaceSearch` | Blank query, loading, no matches, failed query, stale result | Shared search state pattern; retry same query or refine only as appropriate | E07 |
| Q1 Interests / refinements | `TripInterestQuestionView` | No selection, no local vocabulary match | Local helper/empty state, valid Next/Skip semantics; no network-error UI | Preserve |
| Q2 Popularity | `PlacePopularityQuestionView` | Unselected/skipped answer | Local selection/Skip; no service dependency | Preserve |
| Q3 Pace | `ExplorationPaceQuestionView` | Unselected/skipped answer | Local selection/Skip; pace remains stop-count preference | Preserve |
| Q4 Trip timing | `TripTimingQuestionView` | Unselected/skipped; downstream date incompatibility | Keep the selected timing; show effective date during scheduling, correct downstream conflicts there | E04, E05 |
| Q5 Day part | `DayPartQuestionView` | Unselected/skipped; soft preference cannot be met | Local Skip; nonblocking plan notice for an unmet soft preference | E10 |
| Q6 Budget | `BudgetQuestionView` | Local unset/range state | Local helper/Skip; do not manufacture a network failure | Preserve |
| Q7 Transport | `TransportModeQuestionView` | Local selection; unavailable downstream route | Keep selection; show route failure at the operation, not as a survey error | E04, E11 |
| Standalone preference navigation | `PreferencesFlowView`, `PreferenceFlow` | Back/Skip/cancel continuity | Preserve local answers; no remote recovery layer | Preserve |
| Recommendations loading | `RecommendationsProcessingView` | Initial wait, slow query, leaving the view | Truthful activity, cancellation on leaving; preserve selections | E08, E13 |
| Recommendations results | `PlacesRecommendationsView` | Complete/partial failure, no matches, location access | One state hierarchy; keep usable results; manual origin; one meaningful retry | E08 |
| Add Specific Place | `AddPlacesView`, `TripCreationPresenter.search` | Failure, no matches, changed query, method capacity | Retain selected places; label old results; expose applicable capacity | E06, E07 |
| My Places / selected list | `PlacesSelectionSheet`, `SelectedPlacesView` | Empty list, removal, choosing a supported subset | Honest empty state, accessible removal, direct return to search; no deletion of unrelated saved data | E06 |
| Main spot | `MainSpotQuestionView`, `TripCreationView` | Missing origin/duration, unsupported count, planning failure | Contextual recovery summary, direct schedule/places/availability action | E04, E06 |
| Main-spot stay | `StayDurationQuestionView` | Skipped duration or downstream failure | Preserve answer; duration correction when needed; no generic reset | E04 |
| Trip schedule sheet | `PocketScheduleOptionsSheet` | Date window, visit/session/cutoff validation, Luna choice | Inline field feedback, effective date, clear Apply/Done validity | E05 |
| Access/session subsection | `V41VisitAccessFields` | Access interval, dated booking/check-in/entry conflict | Per-place/date messages; direct correction; no silent booking shift | E05 |
| Visit availability screen | `PocketVisitAvailabilityView` | Unknown access, invalid confirmation, date conflict | Distinguish missing evidence from invalid input; preserve trip-scoped confirmation | E04, E05, E10 |
| Itinerary processing | `TripCreationView`, `TripProcessingView` | Working, slow, interrupted, terminal failure | Check same request, continue later, or failure recovery; no fabricated progress | E13 |
| Itinerary review | `ItineraryReviewView`, `ItineraryListView` | Save, regenerate, route edit, stale/expired proposal | Operation-specific issue and retry; keep review readable; prevent stale apply | E01, E02 |
| Save-name / edit-name dialog | `ItinerarySaveNameDialog`, review name alert | Empty/overlong name; failed rename/apply | Show constraints before submission, keep safe draft text, retry only the failed save stage | E01, E05 |
| Visit editor | `ItineraryVisitEditor`, `PlanningPlaceEditor` | Invalid required interval, failed regeneration | Field validation plus an operation notice in review; retain the edited values and prior proposal status | E05 |
| Departure editor | `ExperienceDepartureEditor` | Date incompatibility, failed route update | Focus date/booking conflict; retry the same departure update | E01, E05 |
| Trip time editor | `ItineraryTripTimeEditor` | End before start; domain-invalid input | Inline validation and correct continuation availability | E05 |
| Opening-hours disclosure | `ItineraryListView.hoursLabel` | Unknown, temporary lookup failure, outside regular hours | Different labels and useful local retry; retain source/date caveat | E10, E11 |
| Departure weather | `ItineraryDepartureCard`, `DepartureWeatherLoader` | Loading, provider failure, unavailable forecast period | Compact nonblocking state; local retry only when useful; keep attribution | E11 |
| Embedded and expanded itinerary map | `ItineraryMapView` | Partial/missing polylines, refresh failure | Same missing-route context in both sizes; keep pins/list; retry drawing only | E11 |
| Saved trip | `SavedTripView`, `SavedItineraryContent` | Missing trip, failed refresh/start/delete | Resource-scoped notice; explicit operation retry; back/refresh as appropriate | E02, E09 |
| Delete confirmation | Saved trip confirmation dialog | Cancel, revision conflict, failed deletion | Keep current confirmation; do not dismiss on failure; retry/delete action stays scoped | E02 |
| Start / continue trip | `SavedTripView.primary`, `PlanningPresenter.event` | Failed or uncertain start, stale revision | Keep planned state until confirmation; status check/retry matching the command | E02, E13 |
| Moving / directions | `TripProgressView`, `TripNavigation` | Denied GPS, poor/stale position, route failure | Manual arrival, Settings, retry directions, and open Maps remain separate from trip-event errors | E03, E11 |
| Arrived / complete visit | `TripProgressContent`, `PlanningPresenter.event` | Failed arrival/complete; uncertain write | Persistent action-specific notice; bounded automatic attempt; explicit retry | E03 |
| Completed trip | `TripCompletedContent`, History | Missing trip or refresh failure | Saved completion remains readable; separate refresh notice | E02, E09 |
| Account: sign-in, sign-up, recovery, confirmation, reset, sign-out | `AccountView`, `AccountPresenter`, `AccountFormState` | Invalid fields, credentials, link, delivery, expired session, limits, partial sign-out | Match action to error; secure input remains ephemeral; privacy-safe notices | E12 |
| Pocket settings / method selection | `PocketConnectionView`, `ItineraryMethodSection` | Invalid URL/token, save failure, unsupported method, unchecked connectivity | Field-specific helper and Save state; keep “connectivity not checked”; do not imply a local save verified the server | E05, E12, E14 |
| Earlier planning workspace/editor | `PlanningRootView`, `PlanningEditorView`, `PlanningFeedback` | Load/generate/apply/auth/location/input failures | Reuse the same operation-aware policy; preserve existing navigation and explicit live/mock mode | E02, E05, E07, E13 |
| Earlier My Trips and trip options/replan form | `journeyTrips`, `ActivePlanningTripView` | Empty/error overlap, revision conflict, failed events/replan | Retained data, correct action, fresh proposal when required | E02, E09, E13 |
| Legacy catalog list/detail | `DiscoveryView`, `RundownDetailView`, `DiscoveryPresenter` | Load versus save error, expired session, retry | Separate list/save issue context; preserve current request-ID reuse and mock labeling | E02 pattern |
| Discover/Search/Bookmark workspace slices | `ExploreSliceView`, `PlanningRootView` | Local filtering and intentional placeholder/empty content | Keep explicit example/placeholder states; no fabricated offline/backend handling | No remote handling needed |
| DEBUG design previews | `Preview/` directories and inline previews | Synthetic presentation only | Useful future failure-state previews; no acceptance claim for live recovery | Out of runtime findings |
| Shared rows, thumbnails, scaffolds, map markers | `Shared/`, subordinate View declarations in CSV | Missing optional imagery/metadata, disabled controls | Preserve placeholders; surface actionable failures at the owning screen/operation | Preserve / E05 |

## Error presentation and recovery policy to implement later

### State classification

| Situation | Presentation | Primary action | Preserve / constraints |
| --- | --- | --- | --- |
| Field is invalid | Message beside the field; section summary when needed | Correct that value | Keep other values and selections. |
| Valid search returns no matches | Contextual empty state | Refine query/location | Keep query and selections; do not call it offline. |
| First load fails with no usable content | Unavailable state with a specific title | Retry the same read | Keep navigation and account access. |
| Refresh fails with usable content | Inline notice on the retained content | Retry refresh | Label freshness where known; do not replace the entire list. |
| Missing required duration | Planning recovery summary plus highlighted affected places | Set durations | Offer optional Luna only when enabled and permitted. |
| Confirmed access/date/session conflict | Place/date-specific recovery sheet | Review the affected visit | Do not shift a booking or edit a hard constraint silently. |
| Schedule search did not find a complete result | Explain checked scope without claiming impossibility | Review constraints/details | Distinguish missing ETA and bounded search from proven insufficient time. |
| Search budget reached | Explain that comparison stopped | Review options or deliberately start a new attempt | Retain a completed candidate if one exists; do not describe a new command as continuing an exhausted budget. |
| Route/provider throttle | Contextual temporary-unavailable notice | Retry later | Do not repeatedly dispatch. Show retry timing only if actually supplied. |
| Job may still be running / response lost | Persistent status-unknown notice | Check status | Preserve request ID and selected places. Do not automatically create a replacement job. |
| Confirmed terminal job failure | Failure summary with specific available cause | Start a new attempt or correct input | New input/new attempt gets the appropriate new identity. |
| Optional weather/hours/Luna data missing | Component notice or plan-status caveat | Retry component / inspect evidence, when useful | Keep a usable schedule; do not imply confirmed opening or weather. |
| Save/event/delete failed or uncertain | Notice near that action; modal only if consequence requires interruption | Retry/check that exact operation | Preserve the existing command identity; do not repeat unrelated operations. |
| Proposal expired / trip revision changed | Explicit stale-result notice | Refresh and review a new proposal | Disable stale apply; do not silently replace the accepted trip. |
| Permission denied / restricted | Contextual capability explanation | Choose manually or open Settings, as applicable | Respect the choice; no recurring permission alert loop. |
| Signed out / account expired | Scoped sign-in state | Sign in again | Maintain account isolation; do not expose another account's cached trips. |
| Local storage/configuration fault | Dedicated recovery state with safe diagnostics | Retry only when meaningful / account or support path | No automatic file deletion, token disclosure, or unapproved reset. |
| User cancels or navigates away | Normal navigation | None | Suppress cancellation-as-error; distinguish leaving from guaranteed cancellation of a server job. |

### Proposed issue model and component responsibilities

This is an implementation plan, not a new public contract or code patch. Preserve VIPER ownership and the current engine results.

1. **Classify at the boundary.** C67Data retains typed transport, storage, permission, and provider distinctions. Domain keeps stable failure/assessment semantics. Raw provider/localized exception text is not the default product copy.
2. **Present by failed operation.** Presenters retain an issue with its category/code, operation, target trip/job/place, request/session identity, severity/blocking scope, uncertainty state, and allowed recovery. Map this to a short title, relevant explanation, primary/secondary actions, and optional details. Use an issue identifier so dismissing an old issue cannot clear a newer one.
3. **Use a small presentation family.** Field validation for forms; contextual notice for partial/read refresh failures; unavailable state for first-load failure; recovery sheet for multiple itinerary conflicts; native alert/confirmation only for a consequential immediate decision. One reusable component should not decide business recovery or call a provider.
4. **Treat recovery as a command.** Checking status, retrying a read, retrying a write, editing a field, regenerating a proposal, and starting a new attempt are separate actions. Preserve the existing fingerprint/idempotency rules. Guard double taps and stale async results. Use bounded retries/backoff only where safe; never run a write-retry loop from a presentation busy change.
5. **Keep evidence accessible.** Default copy explains the problem, its consequence for the current task, and the next useful action. Optional technical details may show a safe reference ID and diagnostic category. Never copy credentials, request payloads, filesystem contents, or unfiltered model/exception output into user-visible diagnostics.
6. **Make notices usable with assistive technology.** Keep icon and text meaning, Dynamic Type wrapping, keyboard access, and explicit action labels. Plan focus/announcement behavior for a newly blocking error without repeatedly interrupting a working user. Actual VoiceOver and contrast behavior must be evaluated before declaring compliance.

### Example copy proposals

These are proposed English strings matching the current product language. Adapt them to actual facts; do not display a duration, date, or affected count that was not established by the input/assessment.

| Context | Proposed title / explanation | Actions |
| --- | --- | --- |
| Confirmed visit conflict | “This visit doesn’t fit its available hours.” Name the affected place, trip date, visit duration, and confirmed window. | **Review visit**; Adjust trip time; View details |
| Missing duration with Luna off | “Choose a visit length.” Identify the affected places; explain that planning can continue after their durations are supplied. | **Set visit lengths**; optional assistance settings |
| Search stopped at its limit | “We couldn’t finish checking this schedule.” Explain that the search stopped, without claiming no feasible schedule exists. | **Review options**; Start a new attempt |
| Connection lost during planning | “We can’t check your itinerary yet.” Explain that the request may still be running and selected places are kept. | **Check status**; Continue later |
| Route update failed in review | “We couldn’t update the route.” Explain which accepted itinerary remains displayed. | **Retry route update**; Keep current itinerary |
| Save failed | “Your trip hasn’t been saved.” Use this only after a confirmed failure; an uncertain response instead says confirmation is unavailable. | **Save again** or **Check save status**, according to known state |
| Failed trip-list refresh | “Trips couldn’t be refreshed.” Retain already loaded trips; describe last update only when known. | **Refresh trips** |
| GPS denied | “Location access is off.” Explain which feature is affected. | **Choose starting point** on creation, or **Open Settings** during navigation; manual arrival remains available |

## Prioritized next steps

| Phase | Scope and files | Acceptance before moving on |
| --- | --- | --- |
| 1 — Correct recovery semantics | E01–E03, E13; `PlanningPresenter`, `ItineraryReviewView`, `TripProgressView`, `TripNavigation`, Home | Each failure action retries only its operation; loaded trips survive unrelated errors; persistent arrival failure does not resubmit in a loop; uncertain work retains identity. |
| 2 — Planning recovery and validation | E04–E06, E10; `TripCreationPresenter/View`, schedule/access forms, review status | A user can identify the affected place/date/value and reach its correction directly; all conflicts remain discoverable; provisional access and search limits are visible; selected places remain intact. |
| 3 — Search, component states, entry and account | E07–E09, E11–E12; search/recommendation, maps/hours/weather, entry/account/settings | Empty, failed, partial, and stale states are distinct; optional content retries do not rerun planning; account actions match their failure; entry has a safe recovery path. |
| 4 — Adapter detail and consistent accessibility | E14; C67Data mappings and shared presentation; VoiceOver/Dynamic Type/localization evaluation | Existing status distinctions reach presentation; no fabricated retry timing; readable, reachable actions and announced blocking errors; no leakage of implementation/secret data. |

Phases are proposed for review, not scheduled or authorized implementation. Most work is in the iOS presentation and its existing on-device Data adapters. No server migration/deployment is needed to start. Richer stable server failure metadata is a separate optional improvement after client fixes and a reviewed contract decision.

## Verification plan for a later implementation

No tests below were run as part of this audit. Existing engine test success does not establish the UX behaviors here.

- Behavior tests: operation-to-action mapping for load, refresh, route edit, rename, apply, start, arrive, complete, and delete; unchanged retry identities for uncertain responses; new identities only when justified; session changes and late results; persistent arrival failure; retained content/input.
- Error-state UI tests: initial failure, failed refresh with retained data, empty search, failed search with earlier-query results, partial recommendations, invalid schedule/session field, missing duration with Luna off, confirmed visit conflict, budget reached, throttle, expired proposal, store failure, and expired account.
- Navigation continuity: edit and correct the actual invalid field; cancel/dismiss without unexpected input loss; continue later and reopen the same draft; return from Settings with permission still denied or newly granted; missing trip returns to the appropriate list.
- Component isolation: fail map polylines, hours, or forecast independently. Their retry must not invoke save, a model request, or a full itinerary search.
- Accessibility/runtime: VoiceOver focus and error discovery, largest supported Dynamic Type, Light/Dark, Increase Contrast, Reduce Motion, keyboard, and iPhone/iPad layouts. Inspect safe-area banners and long lists of place-specific conflicts. Do not infer success from text identifiers alone.
- Provider acceptance: distinguish offline, timeout, throttling, authentication rejection, terminal model failure, and unsupported capability against the selected environment. Synthetic faults establish deterministic app behavior; controlled live checks establish actual transport behavior.

## Coverage gaps

- No new runtime, screenshots, UI interactions, accessibility inspection, contrast measurement, or user study. The earlier screenshot concerns an older v4 state and is not proof of the current v4.1 layout.
- No claim that every underlying server/database implementation was audited. Server inspection was limited to the Pocket error/status paths implicated by the app; legacy HTTP adapters and domain errors were inventoried by their consumers. The 119-file CSV is a static source inventory, not a declaration that every line or conditional build was exercised.
- No live auth, Luna, MapKit, WeatherKit/Open-Meteo, filesystem protection, exhausted device storage, or corrupt-store scenario was reproduced.
- No dedicated error-focus or announcement hooks were found in the app scan, but actual VoiceOver discovery is **unassessed**. Absence of such hooks alone is not classified as an accessibility failure.
- Placeholder Discover/Search/Bookmark content and DEBUG previews do not justify adding a backend, permissions, or new remote behavior. Their future error designs should follow only if those features are separately implemented.
- iOS 18 compatibility and current iPad behavior need explicit runtime validation when remediation changes shared UI. No deployment-target change is proposed.

## Platform-aligned strengths to preserve

- Location denial already offers manual selection and Settings on the primary Home flow; navigation offers manual arrival and external Maps.
- Search/recommendation failures preserve selected places, and partial recommendation queries can retain successful results.
- The model already tracks pending request/apply/event identities, session generations, stale-result guards, and fresh-proposal requirements. Improve their presentation rather than replacing those safeguards.
- v4.1 has structured diagnostics, trip-scoped access, reviewed duration alternatives, and optional Luna. The UI can use existing information before requesting new data sources.
- Cancellation is generally suppressed as a user-facing failure. Secure fields are ephemeral. Delete has an explicit irreversible-action confirmation; failed deletion does not automatically dismiss the trip.
- Optional forecast failure has a truthful unavailable state; source/uncertainty disclosures and synthetic-mode labels already exist.

## Handoff

The original audit was read-only. Remediation is now in progress; this audit's earlier findings and coverage gaps describe the pre-remediation state.

## Remediation progress — 18 November 2026

- Review retry now records the specific route, departure, reorder, or save operation. The overall presenter still exposes a shared string error, so complete operation-scoped presentation is outstanding.
- A controlled unit scenario sends an automatic arrival into a repeatedly failing repository, verifies that the same trip/stop/revision is not automatically claimed again, and checks that explicit retry retains the event identity. This is not a GPS or physical-device test.
- Home and History retain loaded trips on trip-list refresh failure. Recommendations no longer shows failure and empty state together. Search labels retained results after failure.
- The v4.1 failure banner links to a native details sheet with conflicts, missing information, dates and duration alternatives. Some field-specific navigation and first-error focus remain outstanding.
- Local retries were added for route geometry, departure weather, and temporary hours lookup failures. Isolation from planning calls has not yet been independently fault-injected in a test.
- HTTP 429 is mapped to rate limiting, with a synthetic HTTP regression; server configuration and contracts were unchanged. Account session retry is shown only for session-check failures. Missing-trip screens offer a way back, and storage opening can be retried without deleting data.
- Verification so far: 130 package tests passed; 53 focused TripCreation app tests passed on iPhone 18 Pro Max Simulator iOS 27.2; one synthetic v4.1 missing-duration UI test passed. These test runs precede the final storage UI change. A subsequent Simulator build, SwiftFormat and diff checks passed. No physical device, iPad, VoiceOver, dynamic-type matrix, live providers or full UI suite has been validated.

Remaining work includes the shared typed issue model and consistent operation scoping across all screens; complete field-specific recovery and validation; startup configuration recovery and storage failure tests; account-specific recovery actions; tests for each retry and stale/session case; and the requested iPhone/iPad accessibility and appearance matrix. Do not interpret the passing subsets as completion of the approved plan. No commit, push, deployment, or live-state change was performed.


## Remediation follow-up — 18 November 2026

The table below records the follow-up to the initial implementation checkpoint above. The changes use the existing SwiftUI surfaces, in-memory presentation state, and local Swift adapters.

| Finding | Implemented behavior | Verification |
| --- | --- | --- |
| E01 | The review issue carries the original route update, departure, order or save operation. The Retry button dispatches that operation. An expired proposal requests a new plan. | App regression records calls and proves that a route retry neither requests nor applies an itinerary. |
| E02 | Trip list, creation/replanning, review, saved-trip mutations and activity use distinct issue scopes. The list keeps its existing items when refresh fails. | App regressions cover list continuity, issue isolation and a failed deletion. |
| E03 | The automatic arrival claim is bounded by trip, stop and revision. An explicit retry keeps an unconfirmed event's request identity. | App regression injects persistent event failure. GPS-driven Simulator and device interaction remain unverified. |
| E04 | One primary recovery plus schedule details. The detail list distinguishes conflicts, incomplete evidence and budget-limited searches. Editable diagnoses carry a specific field into the sheet and prioritize the affected visit above the rest of the form. | Synthetic UI cases on iPhone and iPad assert that the duration control is tappable immediately after opening its diagnosis, with no scroll gesture before the tap. |
| E05 | Schedule, access, last entry, session and check-in errors identify the affected values. Review error scrolls to the first invalid control and requests accessibility focus. Name dialogs explain empty and overlong names. | Focused form and rename UI tests. VoiceOver focus needs a separate observation. |
| E06 | Add Places and Recommendations disclose the schedule-method limit. A blocked planning handoff opens My Places directly and keeps all selections until the user changes them. | Existing selection-limit and preservation regressions run with the app suite. |
| E07 | Add Places and the legacy place sheet distinguish idle, loading, empty, failed and retained prior results. Late results are guarded by input identity and, for trip creation, session generation. | App search regression covers late responses and retained selection. |
| E08 | Recommendations keep usable results, show one refresh recovery and collapse partial-provider warnings into a disclosure. | App recommendations tests use synthetic search; partial failure UI was reviewed in source. |
| E09 | Startup offers retry for reopenable failures and shareable support copy for invalid configuration. Storage retry does not remove data. Missing-trip screens have a back action. | App compiles; startup and storage failures were reviewed in source. |
| E10 | Review shows readiness or a short notice with visit-specific checks. Optional missing information stays in the plan context. | Synthetic v4.1 review flows; provisional states are exercised through the existing package scenarios. |
| E11 | Map geometry retries only missing segments and retains drawn routes. Weather distinguishes missing forecast coverage from temporary failure. Hours retry only transiently failed places. | App regression covers hours-only retry and forecast-hour decoding. Map and weather retry isolation was reviewed in source. |
| E12 | Account recovery matches credential errors, link requests, session checks and limits. The Pocket entry screen also exposes session retry and short copy. | App account tests and package authentication tests. Expired-link UI remains unverified. |
| E13 | Progress reports current work, draft rows distinguish status and final failure, and Check status resumes the same job after interruption. An unconfirmed request or write retains its identity. | Package tests cover interrupted Pocket work with the same ID. App tests count status reads, writes and replacements after a definitive failure or changed input. |
| E14 | Pocket preserves HTTP 429 as rate limiting in ordering and hours lookup. Schedule failures retain existing diagnostic codes, while UI copy omits raw HTTP and implementation details. | URLProtocol regression covers HTTP 429 and 503. This is synthetic adapter evidence. |


### Simulator evidence

| Device and settings | Exercised flow | Result |
| --- | --- | --- |
| iPhone 18 Pro Max, Light, standard text | Synthetic first itinerary and save, invalid name and cancel, v4.1 missing-duration recovery | [3 UI tests passed](/Users/giovan/Library/Developer/XcodeBuildMCP/workspaces/C6---Pisang-Besar-Balaraja-d752e434f295/result-bundles/test_sim_2026-11-18T01-02-49-565Z_pid63276_4a78f73e.xcresult) |
| iPad mini, Light, standard text | v4.1 missing-duration recovery | [1 UI test passed](/Users/giovan/Library/Developer/XcodeBuildMCP/workspaces/C6---Pisang-Besar-Balaraja-d752e434f295/result-bundles/test_sim_2026-11-18T01-13-33-652Z_pid63276_7580da34.xcresult) |
| iPad mini, Dark, Accessibility Large | Missing-duration recovery with corrected date copy, unconfirmed write identity | [1 UI test and 1 app regression passed](/Users/giovan/Library/Developer/XcodeBuildMCP/workspaces/C6---Pisang-Besar-Balaraja-d752e434f295/result-bundles/test_sim_2026-11-18T01-05-14-637Z_pid63276_5b4aedec.xcresult) |
| iPhone 18 Pro Max, Dark, Accessibility Large | Missing-duration recovery with corrected date copy and duration control immediately reachable | [1 UI test passed](/Users/giovan/Library/Developer/XcodeBuildMCP/workspaces/C6---Pisang-Besar-Balaraja-d752e434f295/result-bundles/test_sim_2026-11-18T01-12-53-048Z_pid63276_2af4a6fa.xcresult) |

The tests use iOS 27.2 and synthetic providers. The focused TripCreation and Account run passed all 66 app tests. A clean Simulator build for testing, SwiftFormat, and the worktree diff check passed. Screenshot attachments capture the notice, diagnosis and form. Visual verification covered these representative settings; the original v4 screenshot and the v4.1 synthetic fixture are different inputs, so the screenshots do not establish same-input before/after parity. VoiceOver, physical-device interaction, live providers, startup/storage error injection and the full recovery UI matrix remain open. Both Simulator devices were returned to Light with standard text after testing.
