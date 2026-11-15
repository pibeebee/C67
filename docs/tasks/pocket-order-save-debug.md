# Task: Diagnose the five-place ordering acceptance failure

Status: Completed for the connected trip-flow repair; local Simulator acceptance passed
Owner: Codex
Branch: gi/pocket-ui

## Outcome and scope

Diagnose the 15 November local retest, correct the failed save-name automation and misleading save dialog, and prepare the next UI acceptance. Preserve existing unrelated work. No provider call, UI interaction test, deployment, commit or push is authorized as part of this debugging pass. Unit tests on Simulator are allowed; UI acceptance is deferred at the user's request.

## Evidence and diagnosis

The [retest log](../evidence/pocket-order-retest-2026-11-15/ui-test.log) shows all five place assertions passing, followed by the save-name alert and Save tap. The failure hierarchy contains navigation title `Live order acceptanceacceptance` and the saved-detail `Go Trip` action. The failing assertion expected `Live order acceptance` exactly. The test deleted a number of characters from the current insertion position; it never selected the entire old value or checked the replacement before saving. The retained suffix was therefore saved as entered. This retest failure is in test text entry, not evidence of a failed Luna order or rejected save.

The [server log](../evidence/pocket-order-retest-2026-11-15/server-request.log) records request start 08:28:00.916 and completion 08:30:29.325 WIB (148.409 seconds), reported model `gpt-6-luna`, effort `max`, Responses transport. This is local server evidence; dashboard accounting has not been verified and is not diagnosed here. The earlier HTTP 524 remains a separate observed provider failure.

## Changes

- Shared UI test helper selects all text, deletes it, verifies the field is empty, types the new name and checks exact equality before Save. Both affected rename tests use the helper and abort before saving if the field differs.
- Save dialog accurately describes local rename for untimed experience orders; legacy timed plans retain their regeneration explanation.
- Presenter regression test generates a five-place synthetic order, renames/saves once, checks exact titles across trip/input/proposal, retains the same experience plan and opens the saved trip.
- Existing repository regression checks rename/save/reload/start without a second model call.

## Acceptance and verification

- [x] Root cause tied to the actual failure hierarchy.
- [x] Exact field value checked before the next UI Save.
- [x] App unit suite: 34 passed; repository rename/save/reload/start regression: 1 passed.
- [x] UI acceptance verifies name replacement and exact saved title; the menu-based implementation was superseded below.

No claim of UI interaction success is made from compilation or unit tests. The next run should exercise both synthetic rename and the five-place live acceptance, retaining logs and its result bundle.

## Executed checks

- `xcodebuild test` with `-only-testing:C67AppTests/TripCreationTests`: 34 passed on iPhone 18 Pro Max Simulator, iOS 27.2, Pocket mode with synthetic in-process repository; no Luna calls. Result bundle: `/private/tmp/c67-save-debug-unit-v2.xcresult`. The first run exposed an empty-place test setup; adding the five fixture places corrected the setup, and the final suite passed.
- `swift test --package-path ios-backend --filter untimedTripCanBeRenamedSavedReloadedAndStartedWithoutAnotherModelCall`: 1 passed.
- Pinned SwiftFormat check and `git diff --check`: passed.
- Logs: [evidence folder](../evidence/pocket-order-save-debug-2026-11-15/).
- UI tests and provider calls: not run in this debugging pass. Native menu selection remains pending UI acceptance. No deployment, commit or push.

## Second correction after the 08:44 live UI run

The next live UI run returned a Luna result, but the Select All `MenuItem.tap()` failed with an invalid activation point. XCUITest's trace shows the containing Save Itinerary alert being treated as an interruption before the menu disappeared. This failed run is preserved in [the UI log](../evidence/pocket-order-ui-retest-2026-11-15/live-ui.log).

The helper now uses the observed menu element's center coordinate rather than semantic `MenuItem.tap()`, avoiding that semantic hit-point/interruption path. Exact empty-field and replacement-name assertions remain; the helper never saves an unchecked value. The fallback button uses the same coordinate interaction. This is a proposed runtime correction compiled successfully; native menu interaction is still unverified until the next UI run.

The adjacent save flow review covered dialog binding, title validation, presenter rename/apply, repository persistence/idempotency, retry routing and saved-trip navigation. It found an additional presenter race: rename did not hold `isBusy` across its await, and its completion lacked the generation/cancellation checks used by apply. The whole rename/apply operation now holds the busy state, rejects duplicate save/apply actions, and ignores stale rename responses after session changes. Both public apply and rename use the same guarded internal apply routine; pending apply request identity remains intact for retry. No new issue was identified in the reviewed repository persistence or saved-trip navigation paths; this is scoped review, not a guarantee of no defects elsewhere.

### Final checks for the second correction

- App unit suite: **37 passed**, including new deterministic tests for duplicate save during suspended rename, session change during rename, and failed-save retry retaining the same recommendation and exact title.
- All on-device package tests: **63 passed**.
- App and UI test targets compiled during the unit-only Xcode run; no UI tests were executed.
- SwiftFormat and whitespace checks: passed.
- Simulator: iPhone 18 Pro Max, iOS 27.2; synthetic repository only, no Luna/provider requests.
- Result bundle: `/private/tmp/c67-save-fix2-unit.xcresult`.
- [Preserved logs](../evidence/pocket-order-save-fix2-2026-11-15/).
- Next run: verify synthetic name replacement/save first; then the live five-place flow with a healthy local server. Preserve logs, verify exact field value before Save, exact saved title and all five stops. No claim of UI acceptance is made here. No commit, push or deployment.


## Follow-up repair — 15 November 2026

The user now authorizes fixing the connected flow and executing UI tests. This supersedes the earlier unit-only boundary for this follow-up. Scope: trip creation, itinerary review/save/retry, repository persistence and their existing tests; preserve unrelated changes. No deployment, commit or push.

Review checklist:

- [x] Replace the unstable edit-menu interaction and verify the previously failing synthetic UI scenario.
- [x] Review the rename/apply retry path; keep the requested title when retrying a failed rename.
- [x] Add regression coverage for rename failure/retry and untimed UI name validation/cancel/rename.
- [x] Run all app unit tests, connected UI suites, on-device package tests and synthetic Pocket server tests.
- [x] Run the live five-place UI acceptance after synthetic checks pass, recording request/result evidence.
- [x] Preserve logs, review the scoped diff and report remaining limitations.

The first targeted UI check passed after using `typeKey("a", modifierFlags: .command)` instead of the contextual Select All menu. Result bundle: `/private/tmp/c67-save-command-a-20261115.xcresult` (1 passed, 0 failed). This is synthetic Simulator evidence only.


### Verified correction and broader checks

The edit-menu approach and the initial Command-A replacement were not reliable. The first Command-A test passed, but the broader run failed in both rename scenarios. A diagnostic rerun proved that ordinary backspace removed the prefix while a suffix (`test` / `afternoon`) remained at the cursor; synthesized Forward Delete did not remove it. Those failed logs are retained. The final helper taps the trailing edge, deletes the value, repeats if long text has scrolled, and verifies empty/replacement values before any Save. It does not use the edit menu, keyboard shortcuts, a model retry or a weaker saved-title assertion. The two affected cases passed together, followed by all 16 connected UI cases passing in one complete run.

The UI retry action now resubmits the requested name through `saveReviewedProposal(named:)` instead of applying the old proposal directly after a failed rename. A repository stub regression verifies no apply on rename failure, then one apply with the requested title and the original recommendation after retry. This supplements the existing duplicate-tap, session-change and save-retry tests. The opt-in discovery live UI test's old 100-second wait was aligned with the five-place test's 480-second allowance. The final live five-place test also checks all five saved stops, starts the trip and confirms the first arrival.

Reviewed boundaries: save dialog validation/binding, creation navigation and cancellation, presenter generation/busy/retry handling, repository rename/apply/persistence and idempotency, ordering transport/validation, local server job handling and composition-root configuration. No additional code defect was established in the reviewed transport/storage/server paths; this is a scoped review of the connected flow.

Confirmed checks:

- App unit definitions: 110 passed, 4 opt-in external Auth/Luna cases skipped (114 total); the initial broad result also contains the two subsequently corrected UI failures. Dynamic parameter executions are not added as extra test definitions.
- Final connected synthetic UI run: 16 passed, 0 failed, 0 skipped, iPhone 18 Pro Max / iOS 27.2; `/private/tmp/c67-flow-final-ui-20261115.xcresult`.
- Both corrected rename UI cases: 2 passed, 0 failed; `/private/tmp/c67-name-trailing-edge-20261115.xcresult`.
- `swift test --package-path ios-backend`: 63 passed.
- Pocket Python synthetic server tests: 39 passed; no provider calls.
- Contract validation, all 662 Swift files' pinned formatting check and whitespace check: passed.
- [Preserved logs and result summaries](../evidence/pocket-flow-repair-2026-11-15/).

The live five-place UI acceptance is running separately after the complete synthetic UI pass. No live success is claimed until its result is recorded below. Physical-device, full VoiceOver and iOS 18 runtime acceptance are outside this local Simulator evidence.


### Final live acceptance

After the complete 16/16 synthetic UI pass, the actual server/Luna five-place UI acceptance passed (1/1). All five selected stops remained in review and saved detail; the exact title `Live order acceptance` was saved; Go Trip opened active progress; manually confirming the first arrival showed `You’ve arrived` with the continue-visit action. The server's new job and actual request/result were preserved, and its log contains exactly one Luna request start/completion, 104.884 seconds apart, reported `gpt-6-luna`, effort `max`, Responses protocol. No second model call was made for rename/save/start/arrival. Screenshots were exported and inspected.

See the [complete result index](../evidence/pocket-flow-repair-2026-11-15/README.md), including retained failures and final passing bundles. The live harness uses fixed public test pins, actual Luna/optional forecast processing and in-memory trip state; package tests cover persistent storage separately. This establishes local Simulator connected-flow acceptance, not physical-device or field validation. No deployment, commit or push.
