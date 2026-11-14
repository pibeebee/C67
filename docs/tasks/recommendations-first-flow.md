# Task: Choose places before configuring a trip

Status: Ready for review; compilation and non-UI tests pass, UI verification excluded by user request
Owner: Codex
Branch: gi/pocket-ui

## Outcome

Preferences → recommendations → main spot → optional duration → trip configuration. Selecting a main spot or duration does not start itinerary processing.

## Scope and dependencies

- Reuse the existing SwiftUI/VIPER creation, recommendation, selection-sheet and survey screens.
- Remove selection count limits from recommendations and manual place search. Keep selections and metadata through refresh, back navigation and failed searches.
- Use session-only native MapKit search before trip configuration, with loading/empty/partial-failure/retry/cancellation states and an Apple map. Explicit mock mode uses clearly synthetic places, including enough candidates to select more than six.
- Bridge expanded preferences with deterministic English queries (up to four per refresh, rotating terms). This is not E5 ranking, facility verification, exhaustive Jakarta collection or a matching benchmark.
- Preserve the existing six-place planning contract. Larger selections remain intact in the session; the later configuration explains why itinerary submission is unavailable. Routing/solver changes, E5 integration, server work and TestFlight are deferred.
- Commit and push to `gi/pocket-ui` were authorized on 14 November 2026. Deployment and shared-environment runtime changes are outside this publication step.

## References

- [ADR 0010](../decisions/0010-pocket-native-ui-integration.md)
- [Integration guide](../pocket-engine-integration.md)
- [Design system](../design-system.md)

## Acceptance criteria and verification

The source implements the requested screen order, unlimited selection, selection retention, main-spot invalidation when removed, optional duration, refresh cancellation and a deferred planning handoff. Presenter tests exercise the new flow without rendering screens or automating interactions.

The initial implementation was intentionally untested. On 14 November the user authorized compilation, non-UI checks and fixes, explicitly excluding UI testing. The follow-up used Xcode 27.2 (27B52), Swift 6.4.2, and the iPhone 18 Pro Max / iOS 27.2 runtime for hosted model tests. No C67UITests cases, screen-render tests, manual UI walkthrough, live MapKit requests or latency/quality benchmark ran.

| Check | Result |
| --- | --- |
| Generic iOS Simulator Debug compilation | Passed, including arm64 and x86_64 during the initial successful build |
| iOS device Release compilation | Passed, signing disabled; not an archive/export/upload or physical-device run |
| Hosted presenter/preferences unit tests | 36 tests in 3 suites passed: `TripCreationTests`, `PreferenceAnswersTests`, `PreferenceFlowTests` |
| Device-backend package | 47 tests passed, rerun after the compiler-warning fix |
| Pocket Engine package | 12 XCTest tests passed |
| Pinned SwiftFormat | All 660 Swift files pass |
| Plist/entitlements and whitespace | `plutil -lint` and `git diff --check` pass |

The hosted unit command selected only the three suites with `-only-testing:C67AppTests/<suite>` and explicitly used `-skip-testing:C67UITests`, `-parallel-testing-enabled NO`, `C67_DATA_MODE=mock`, and ad-hoc Simulator signing. The selected suites contain no screen-render or interaction tests. The local result bundle is `/tmp/c67-flow-unit-tests.xcresult`; build and test logs use `/tmp/c67-flow-*.log`, `/tmp/c67-backend-tests-final.log` and `/tmp/c67-engine-tests.log`.

The compiler failure was an older `PlanningEditorView` call to the replaced recommendation initializer, surfaced as a SwiftUI type-check timeout. Its caller now supplies selection/loading/refresh actions, with the older editor's planning cap explicitly opt-in; the new creation flow leaves that cap unset. Four changed Swift files needed formatting. A split `return`/`switch` in `PocketAppleServices` caused a compiler warning and is now a single return expression. An obsolete recommendation-selection API was removed, and stale search failures are ignored after preference/route/session changes. Existing creation unit expectations now follow the revised navigation.

Successful builds retain Xcode's nonblocking App Intents metadata warning because this app has no AppIntents framework dependency; no dependency or suppression setting was added just to hide it. Before claiming device/UI readiness, separately verify navigation/back/skip, My Places removal, refresh gestures, larger text, main-spot screens and the later handoff. UI suites were not executed or updated during this follow-up.

## Result and handoff

Core changes are in `TripCreationPresenter`, `TripCreationInteractor`, `TripCreationView`, `PlacesRecommendationsView`, the MapKit/mock search implementations, and the existing confirmation/add-place views. Recommendation values are Sendable to support an owned, cancellable search task. Trip configuration and planner execution remain a later explicit action.

Selection is retained in memory for the creation session; it is not durable across app termination. Search-region hints are not an administrative Jakarta geofence. Query results do not establish preference accuracy, opening hours, access, photos, or other missing venue facts. Main-spot duration is applied to the planning draft without overwriting the original candidate duration.
