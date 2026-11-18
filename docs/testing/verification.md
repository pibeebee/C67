# Starter verification

## Traveller account deletion — 18 November 2026

The Swift package passed 135 tests, including resuming deletion after relaunch and removing only the correct account's legacy drafts. The iPhone 18 Pro Max Simulator (iOS 27.2) passed 10 focused Account app tests and mock UI checks in total. The Pocket suite passed 63 tests, including rejecting a different Apple identity, waiting for active work, removing only the target account's jobs and retaining the receipt across a restart. OpenAPI validation passed.

An embedded PostgreSQL 18.6 check with simulated Auth/Storage tables verified the migration, the service-only object manifest, the wait for an active media lease, the rejection of new uploads and account-owned row cascades. The actual Supabase Storage and Auth HTTP flow, live Apple revocation, the container image build and physical-device behavior remain unverified. The rollout prerequisites are documented in the [Pocket service guide](../../server/pocket/README.md#account-deletion).

## Itinerary drag reorder — 18 November 2026

Two UI tests and two app tests passed on iPhone 18 Pro Max Simulator (iOS 27.2). Synthetic Pocket review preserved the original order when the drag ended outside the list, then saved the next successful reorder. Timed mock review also saved the reordered stops. The app tests verified that a rejected Pocket order retains the previous proposal and that a timed order exceeding the deadline restores the previous proposal and draft. Simulator screenshots show the committed order. Auto-scroll on longer lists, VoiceOver traversal, and haptic feel on a physical iPhone remain unverified.

The final result bundle is `test_sim_2026-11-18T02-33-32-466Z_pid63276_563df1e0.xcresult`. SwiftFormat and the worktree diff check passed.

## Travelant error recovery — 18 November 2026

The Main Spot follow-up passed 136 package tests and 62 focused app and UI tests on iPhone 18 Pro Max Simulator (iOS 27.2). The app test verified that retrying an unconfirmed submission keeps the selected places, main spot, full input and request ID. The UI test simulated a timeout after a Pocket job existed and checked that the banner showed **Check status**, hid the duplicate **Next** action, and reached itinerary review with the selected place. The fixture succeeds only on a repeat of the same request ID. Package tests distinguish a URL transport timeout from lost connectivity and classify gateway timeouts separately. The timeout was injected at the transport boundary. The full ten-minute UI polling limit and live provider behavior were not exercised.

The local package passed 130 tests, including HTTP 429 versus 503 and recovery of an interrupted Pocket job under the same request ID. The focused iPhone application run passed 66 TripCreation and Account tests. A later focused test passed for an unconfirmed write with an invalid response, followed by a definitive failure and a new request identity.

The iPhone 18 Pro Max and iPad mini (iOS 27.2) ran the synthetic missing-duration scenario in Light at standard Dynamic Type and Dark at Accessibility Large. The final iPhone Dark and iPad Light runs open the diagnostic sheet, assert immediate access to the affected duration control and reach itinerary review with the selected place. The iPhone normal planning/save and trip-name validation flows also passed. The initial UI runs exposed two test assumptions: a hardcoded synthetic default name and a tap attempt before the processing cover finished dismissing. The corrected iPhone tests passed. Result bundles and implementation findings are in the [error-handling audit](../tasks/error-handling-ux-audit-2026-11-18.md#remediation-follow-up--18-november-2026).

VoiceOver traversal and spoken focus, a matching pre-change screenshot matrix, live providers, physical devices, injected startup/storage UI failures, and runtime map/weather retry fault injection remain unverified.

## Hybrid v4.1 engine experiment results — 18 November 2026

The first synthetic non-UI run of `V41EngineExperimentTests` passed 17 of 18 test methods (26 of 27 parameter-expanded invocations). The persistence method failed because its assertion compared the restored working input with the raw request input. The repository intentionally adds `reasonableOrdering` and `automaticFirstPlan` before saving the job and retains the original request in `command`.

The test now verifies those two expected flags, the unchanged original command, and equality of the working input, failure status, error code, and diagnostics across reopening. Only `failedAccessDiagnosticsSurvivePersistenceWithoutAnotherSearch` was rerun after the correction: **1 test passed**, zero issues, exit 0. Production code was unchanged. All 18 methods now have passing observations across the original run and targeted rerun; the complete suite was not rerun. SwiftFormat passed for all 674 Swift files. See the [cause, scenario results, commands, and limitations](../tasks/hybrid-v41-engine-experiment-results.md).

## Hybrid v4.1 engine test preparation — 18 November 2026

At preparation, the additional non-UI suite contained 18 test methods with 27 planned parameter-expanded invocations using synthetic planner/repository providers. Syntax validation and `swift build --build-tests` compile/link checks succeeded, with execution deferred at that stage. Execution was subsequently authorized and is recorded above. The earlier 111-test result below remains historical evidence for the previous revision. See the [preparation and scenario matrix](../tasks/hybrid-v41-engine-test-preparation.md).

## Hybrid v4.1 — 17 November 2026

The package suite passed 111 tests, including 20 v4.1 cases. On iPhone 18 Pro Max / iOS 27.2 Simulator, all 51 `TripCreationTests` passed and four targeted v4/v4.1 UI flows passed. Focused rechecks covered v4.1 after search refinements. The new cases cover structured timing, diagnostic recovery, adaptive search and budget persistence, duration review, access/session/entry constraints, zero-call scheduling, and semantic reuse. Six four-stop static synthetic cases matched an independent 24-order reference using 33–38 route attempts. OpenAPI/fixture validation, SwiftFormat, document references, and whitespace checks passed. Provider fixtures are synthetic; live Luna/MapKit, physical-device behavior, and human itinerary quality for this revision remain unverified. See [implementation details and result bundles](../tasks/hybrid-v41-integration.md).

## Hybrid v4 date fallback — 17 November 2026

Four targeted repository tests and four iPhone 18 Pro Max / iOS 27.2 Simulator tests passed with synthetic providers. The app checks cover automatic rescheduling in review, saving and restoring the new date, explicit confirmation through the presenter, and the schedule controls. See the [Hybrid v4 integration checkpoint](../tasks/hybrid-v4-integration.md#automatic-date-for-the-first-itinerary).

## Active-trip Liquid Glass — 15 November 2026

The moving/arrival panel uses native regular Liquid Glass on iOS 26+, with a regular material fallback on iOS 18–25. Mock Debug build succeeded and the moving preview was visually inspected on iPhone 18 Pro Max Simulator / iOS 27.2. The fallback and physical-device appearance were not verified.

## Active-trip Hi-Fi alignment — 15 November 2026

Mock iPhone 18 Pro Max / iOS 27.2 build and Hi-Fi preview UI checks completed. The moving and arrival previews were visually inspected; the route instruction and pause/end controls in the moving preview remain synthetic. Live moving-route behavior, physical-device arrival, and complete-screen visual acceptance were not verified.

## Recommendation search entry — 15 November 2026

In mock mode on iPhone 18 Pro Max / iOS 27.2, a focused UI test verified that the recommendation footer omits Search for a place, My Places provides the action, and opening search preserves the selected count.

## Itinerary map and weather display — 15 November 2026

[Verification and source audit](../tasks/itinerary-weather-map-adjustments.md) cover full-screen map interaction and historical forecast display. The local WeatherKit-first ordering adapter and Open-Meteo fallback are tested with synthetic responses; live credentials, provider attribution and deployment remain unverified.

The local WeatherKit-first change passed 41 Pocket server tests using synthetic responses, 68 C67Backend tests, OpenAPI/fixture validation, and the iPhone 18 Pro Max / iOS 27.2 mock itinerary and departure-fallback tests. The server tests verify signed test tokens, source selection, fallback and attribution propagation, not a live Apple or Open-Meteo response. No server deployment or physical-device test was performed.

## Full-page trip creation — 15 November 2026

[Full-page navigation verification](../tasks/trip-creation-full-page.md) covers the synthetic Simulator flows and remaining live recovery limit.

## Pocket UI handoff — 15 November 2026

Pocket-mode Debug build and launch succeeded on iPhone 18 Pro Max / iOS 27.2; the installed configuration was verified as Pocket. A synthetic Pocket integration UI test passed through itinerary generation, reordering, and saving. SwiftFormat passed for all 662 Swift files. The Simulator requested location permission but a successful device position was not observed. No live Luna order or physical-device GPS was validated in this handoff.

## Recommendation device distance — 15 November 2026

[Verification and GPS limits](../tasks/recommendation-device-distance.md) cover simulated Core Location, device-distance display, and the remaining physical-device verification.

## Preference quick-pick selection — 15 November 2026

[Verification](../tasks/preference-quick-pick-selection.md) covers selection and removal in the mock Simulator.

## Itinerary time display — 15 November 2026

[Verification](../tasks/itinerary-24-hour-time.md) covers fixed 24-hour formatting and a synthetic Simulator preview.

## Trip processing Hi-Fi — 15 November 2026

[Task and verification notes](../tasks/trip-processing-hifi.md) cover the two processing states, mock Simulator walkthrough, and remaining live-recovery checks.

## Runtime visit research and Luna — 14 November 2026

[Current implementation and evidence](../tasks/pocket-runtime-visit-resolution.md): native catalog fallback and geographic allowlists removed; selected places are researched by the server with actual Luna. Backend 53, core 14 and Python resolver 24 checks pass. Targeted Simulator fixtures pass 36 checks; the live five-place UI path also passes, but schedules only 1/5 places. Six HTTP 524 responses, conflicting hours and ambiguous branch identity remain material coverage limits. A focused fresh-source/batched-Luna park test passes. The smaller-batch Perpusnas experiment also returned unresolved after HTTP 524. A real native Responses extraction completed, but final server/advice acceptance failed with URLError and work stopped at the user’s requested boundary. No shared server deployment or physical-iPhone/TestFlight acceptance is implied.


[Live Pocket and TestFlight handoff](../tasks/pocket-live-testflight-handoff.md) records the later iPhone 18 Pro Max Simulator results with real venues, Apple ETA, Luna, the server container smoke check, and the remaining signing/HTTPS gates.

## First Pocket itinerary — 14 November 2026

The [implementation and verification record](../tasks/pocket-first-itinerary.md) covers direct planning from selected destinations, conditional availability confirmation, editable timing and endpoints, and retaining omitted destinations with reasons. Package suites passed 14 solver tests and 51 backend tests. The final focused run passed 33 presenter and 3 UI tests on iPhone 18 Pro Max Simulator. A preceding broader run passed 12 additional recommendation and trip-creation UI tests. One opt-in live MapKit test passed after choosing the origin and destination through search. The first itinerary used live automobile ETA and bundled venue evidence.

## Jakarta discovery boundary and direct processing — 14 November 2026

The [follow-up evidence](../tasks/jakarta-discovery-direct-processing.md) records 42 passing hosted model/presenter tests and a successful unsigned iOS device Release build using Xcode 27.2 / Swift 6.4.2. All 659 remaining Swift files pass pinned formatting; whitespace and plist checks pass. The Australian-bookstore regression is covered with stubbed mixed local/foreign responses plus coordinate/country/radius checks, not a live provider run. Unrelated preferences remain separate queries, and completing the main-spot/duration survey directly attempts planning without Confirm trip. Missing origin, personal availability/consent, larger selections and the unchanged narrower planner areas still have explicit gates. No UI/render/manual tests, live provider queries, physical-device test, deployment or TestFlight action ran. Earlier counts below belong to their respective checkpoints.

The subsequent Simulator walkthrough verified selection recovery, a one-hour main spot in the mock itinerary, and the direct handoff to availability review with live destinations. A live partial result kept the selected place after Refresh. The exact independent-bookstore query remained empty within Jakarta's search radius. The latest Release build and 44 selected unit tests passed after fixing the planning banner and reporting MapKit's no-result case separately. Details and remaining quality gaps are in the same task record.

## Recommendations before trip configuration — 14 November 2026

The [flow-change evidence](../tasks/recommendations-first-flow.md) records passing Debug Simulator and unsigned iOS device Release compilation with Xcode 27.2 / Swift 6.4.2. Focused hosted model tests pass 36 tests across creation/preference suites on iPhone 18 Pro Max / iOS 27.2; backend tests pass 47 and Pocket Engine tests pass 12. All 660 Swift files pass pinned formatting; plist/entitlements and whitespace checks pass. Fixed the old recommendation initializer call that caused a SwiftUI type-check failure, a compiler warning, and stale recommendation-error handling. Selections above six reach the later configuration intact; the existing planner still rejects unsupported counts. UI/render tests, manual interaction, live MapKit quality, physical devices, signing and TestFlight were excluded. A nonblocking Xcode App Intents metadata warning remains; this app does not depend on AppIntents.

## Travelant TestFlight preparation — 13 November 2026

Travelant 0.1.0 (build 1) archived for a generic iOS device with Xcode 27.2, exported with App Store distribution signing, and passed Xcode’s App Store Connect validation. Apple initially rejected the missing iPad orientation declarations. XcodeGen now declares all four iPad orientations and portrait on iPhone. The exported bundle was verified to include the Pocket HTTPS URL and WeatherKit entitlement. The app record exists in App Store Connect. Build upload, physical device testing, and a live WeatherKit request from this build remain pending.

## Native Pocket Engine integration — 12 November 2026

[UI integration evidence](../tasks/pocket-ui-integration.md) records the freshly pulled dev base, 62-label inputs, independent discovery, availability review, constrained Luna advice, real solver and local trip persistence. Local checks passed: shared-client/adapter package 47, extracted core 12, and focused app/Simulator selection 29 (zero failures/skips, 83.5 seconds), including both Pocket UI tests. Primary-checkout Release Simulator compilation and normal Debug build/install/launch passed without diagnostics; compiled Debug mode is pocket. Contract, pinned formatting and whitespace checks passed. End-to-end UI transport/venues/ETA/model responses were explicitly synthetic; the local core and adapter were real. Server deployment/live providers, WeatherKit provisioning, oldest-runtime/device/accessibility acceptance and signed TestFlight archive remain separate. No cloud CI was started.

## Native ITINERARY LIST — 11 November 2026

[Itinerary evidence](../tasks/itinerary-list-swiftui.md) records the HI-FI review screen, supplied thumbnail exports, native map/disclosures and real proposal integration. XcodeGen and Simulator builds passed with Xcode 27.2, retaining the iOS 18 minimum. The final iPhone 18 Pro / iOS 27.2 Light run passes 2 UI tests (sample preview and generated edit/regenerate/add-place-search/save/detail); Dark accessibility XXXL passes 1 preview/scroll/interaction test. Home's save/detail/back regression passed with the new review flow. Standard Light/Dark and iPad renders were inspected. All 18 touched Swift files pass formatting; the repository-wide check still finds the two unrelated existing issues. Sketch sample content stays in the DEBUG preview; generated proposals do not invent missing per-stop weather, categories, photos or distances. Device, manual VoiceOver, iOS 18 runtime and live providers remain separate acceptance.

## Native HOME EMPTY — 11 November 2026

[Home implementation evidence](../tasks/home-empty-swiftui.md) records the Sketch HI-FI slice and native Trip/History entry into the existing planning flow. XcodeGen generation and iOS Simulator build passed with Xcode 27.2, retaining the iOS 18 minimum. On iPhone 18 Pro / iOS 27.2 in mock mode, the final Dark run passed 3 Home tests, including accessibility XXXL and proposal/save/detail/back; the final Light run passed Home navigation plus Account and Discovery regression checks (3 tests). Light, Dark, large-text and iPad Pro 11-inch Simulator screenshots were visually checked. Changed Swift files pass the pinned formatter; the full repository check still reports two unrelated existing formatting problems. Device, VoiceOver, iOS 18 runtime and live-provider acceptance remain separate.

## Foundation Models focused English experiment — 5 November 2026

[The focused experiment](../../research/evaluations/foundation-models-2026-11-04/focused-english/REPORT.md) tested smaller task-specific schemas and context on the on-device M5 Mac model. A provisional single-review assessment found five of 12 matched cases correct in both repetitions, while ambiguity, negation, deadlines and stale proposals remained problematic. Three synthetic read-only tool cases each made the expected call; one response inaccurately reported 70% as 69.99%. Experimental harness guard tests passed, but the guard still permitted an incorrect interpretation of an ambiguous request. These are not tests of the app's production validator, automatic task router, physical iPhone, live providers, or independent human review.

## TripSense repeated-search recovery — 4 November 2026

[Search-limit recovery](../tasks/tripsense-search-budget-recovery.md) reproduced the iPhone-reported wrapped search-budget error at the production orchestration seam. One tool-free local finishing request now uses already retrieved matching candidates when enough exist; the five-search cap and native validation remain enforced. Safe UI error mapping avoids tool-state/coordinate dumps. The package suite passed 52 deterministic tests with one opt-in live test skipped; the standalone app built and passed three fixture tests on Simulator. Live iPhone model/MapKit recovery and visual acceptance remain unverified.

## Foundation Models language-assistant evaluation — 4 November 2026

[The isolated evaluation](../../research/evaluations/foundation-models-2026-11-04/REPORT.md) used Apple's on-device `SystemLanguageModel.default` on an M5 Mac with synthetic cases and process-level network denial. An additional English M1 and Indonesian diagnostic M2 sample returned while Wi-Fi and Ethernet were disabled and no active network interface was reported; neither exercised a tool call. Runtime locale support for `id_ID` was false, so Indonesian observations are diagnostic rather than eligible product results. The supported English control returned nine contract-valid responses in ten attempts, but none had an exact action-field match; one attempt timed out. Two-human semantic review, target-iPhone inference, offline fixture-tool execution and real application validator/fallback checks remain unverified. The corrected nullable schema was tested in a follow-up after the initial evaluator results had been seen; it is not a fresh holdout.

## TripSense optimization and OSM — 3 November 2026

The standalone POC now compares up to 720 candidate orders using a directed ETA matrix, validates up to five schedules at actual segment departure times, and has an OSM hours adapter with conservative matching. [Live evidence](../../research/tripsense-poc/FEASIBILITY.md) shows lower travel estimates than revalidated baselines in three Mac scenarios. The six-place OSM audit could not establish coverage: the provider timed out in this environment, and a separate direct endpoint probe returned HTTP 406. Test, Simulator and formatting outcomes are recorded in [task evidence](../tasks/tripsense-poc.md). Physical-device and accessibility acceptance remain separate.

## TripSense standalone native experiment — 3 November 2026

[TripSense feasibility](../../research/tripsense-poc/FEASIBILITY.md) records actual on-device Mac Foundation Models → Tool → MapKit execution, real Jakarta directions/schedules, 17 deterministic package tests, a separate passing opt-in live integration test, and 2 iOS 27.2 Simulator application unit tests. The separate iOS 26+ project builds with Xcode 27.2. This does not change the C67 iOS 18 deployment target or establish phone execution, UI/accessibility acceptance, venue hours or optimal routing. The measured four-stop geographic heuristic was 1,096 seconds slower than its baseline. See [task/evidence](../tasks/tripsense-poc.md).

## Personal planning repository implementation — 30 October 2026

See [the current task](../tasks/ai-trip-planning-implementation.md) for exact commands, cases and exclusions. The new default planning flow, API/worker/provider adapters, additive SQL and OpenAPI 0.6 are implemented locally. Backend TypeScript/style checks and 21 synthetic Node tests/subtests pass, including migration execution on disposable PostgreSQL 18.6 with simulated roles/claims. Contract/resource/legacy compatibility, configuration and local documentation checks pass.

The Swift package and generic iOS Simulator target compile successfully; **no iOS/package/UI tests or Simulator interaction were run**, as explicitly requested for this batch. Real Apple/model calls, matching-image PostgreSQL 17/full Supabase acceptance, new container runtime, GitHub CI results and new shared deployment are not established. The prepared Compose configuration validates without starting services. Existing migration/fixture/seed bytes and legacy contract entries remain intact.

The sections below retain earlier dated evidence; their counts and deployment results do not apply to the new planning slice.

**23 October 2026.** Evidence below distinguishes starter/mock, disposable CI and shared homelab checks; it does not establish product validation.

| Check | Result / boundary |
|---|---|
| Swift package | 4 tests pass: snapshot/retry behavior, missing-session boundary, configuration validation, RPC headers/error/date decoding |
| iOS Simulator build | Pass with Xcode 27.1 / Swift 6.4; deployment target iOS 18 |
| Mock UI smoke test | 1 test passes on iPhone 18 Pro Simulator, iOS 27.0: discovery → detail → save |
| Configuration | Dummy live mode/client key and local URL confirmed in the built Info.plist; no live server request implied |
| API contract | OpenAPI 3.1 validates; all three JSON fixtures validate; bundled catalog and SQL seed match the authoritative fixture |
| Configuration formats | XcodeGen/workflow YAML and local Supabase TOML parse |
| Project generator | XcodeGen 2.45.4 |
| Supabase CLI | 2.121.0 pinned with npm lockfile; config and migration name generated through CLI |
| Database runtime | Verified locally on 23 October: clean startup and guarded local rebuild apply the migration/seed; 14/14 pgTAP checks pass and public-schema lint reports no errors. See local foundation evidence below. |
| GitHub Actions | Baseline commit `640f035` passed `ios`, `contracts` and `database`; new conventions/formatter PR is checked separately |
| Auth / homelab | Local tests and shared homelab integration verified; shared suite passes 28 checks and preserves the existing account. Native iOS login and real-person app sessions remain untested. See homelab evidence below. |
| Physical device / offline / field use | Not tested; mock trips are memory-only |

Before future shared backend changes, rerun database/API checks for the proposed revision, review the homelab database version and existing schema, and prepare a separate operational deployment plan. Verify the native traveller session path before connecting the app to shared data. The local development stack is not an export of homelab credentials or data.

## Team-conventions setup

- The checksum-verified SwiftFormat 0.64.1 runner successfully downloaded its pinned macOS release, formatted two Swift files for layout only, and passed `--check` for all 15 Swift files.
- The shared package still passes all 4 tests after formatting. Contract/fixture checks, Markdown links/fences, Python syntax and workflow YAML checks pass.
- GitHub protection/merge settings are documented in [Repository settings](../operations/repository-settings.md) and verified by reading back the GitHub API.
- Main requires an eligible human approval. Ownership, CODEOWNERS and collaborator roles were explicitly skipped; the setup PR is not automatically merged.

## Local backend foundation — 23 October 2026

Scope: [foundation task](../tasks/server-local-foundation.md), branch `gi/server-local-foundation`, based on main commit `1dd5eeb`. No domain migration, wire contract, native app feature or shared-server configuration was changed.

Environment: macOS arm64, Docker Desktop engine 29.6.1, Node.js 24.14.0, Python 3.14.6, pinned Supabase CLI 2.121.0, local PostgreSQL 17.11. Docker had no pre-existing containers or volumes before the C67 stack was started. The existing migration and synthetic seed applied successfully at first startup.

| Check | Actual result |
|---|---|
| Reproducible local rebuild | Before reset, confirmed `c67-starter` had zero Auth users, zero trips and exactly the authoritative catalog fixture. `npm run db:reset` targeted only local data and reapplied schema/migration/seed successfully. |
| Database | `npm run db:test`: 14/14 pgTAP checks pass after the rebuild. |
| SQL lint | `npm run db:lint`: no public-schema errors. |
| HTTP/Auth | `npm run api:test`: 27/27 checks pass, including two signup/password sessions, token refresh, invalid-token rejection and missing-session denial. |
| Ownership and writes | Account A/B isolation works in both directions through direct Data API reads; anonymous reads and direct insert/update/delete are rejected; unpublished content is hidden through both RPC and direct reads. |
| Copy/retry | Response matches the source snapshot, timezone offsets preserve the same instant, identical retries return one trip, changed input returns 409, and four concurrent same-command requests return one persisted trip identity. |
| Cleanup | Temporary users, their cascading trips and the temporary draft are removed and their absence verified. |
| Contract/fixtures | `.venv/bin/python scripts/check_contracts.py` passes OpenAPI, fixture schema, package copy and SQL seed consistency checks. |
| CI configuration | The existing database job now includes pinned Python 3.12, SQL lint and local HTTP tests. Updated GitHub Actions have not been run remotely for this branch. |

The local gateway permits reading the public synthetic catalog without an API-key header. This is not evidence of API-key enforcement at the homelab gateway. Private trip commands are still rejected without a valid traveller session; ownership enforcement was tested independently of client-key presence.

The HTTP suite uses Python's standard library and obtains local credentials in memory; keys, passwords, sessions and response bodies are not recorded in the repository. No test user or private trip is part of the seed. The database stack is stopped after verification, with its fixture-only local volume retained for the next start.

Unverified: native iOS login/session storage, Simulator/live wiring, physical devices, expired-token behavior, deployed homelab/API compatibility, storage/media, database load, backup/restore and product policy. No commit, push or deployment was performed. The work intentionally ends at foundation step 1.

## Shared homelab foundation — 23 October 2026

The approved deployment is complete. See [Homelab verification](../history/homelab-verification.md) for exact evidence and recovery limits: private backups verified, both databases restored in isolation on PostgreSQL 17.6, 14/14 isolated pgTAP checks and 28/28 shared HTTP checks passed, official migration history recorded, all 11 services healthy, existing Auth account preserved and temporary records/container removed. These results supersede the earlier local-only homelab boundary for the starter foundation. Native iOS integration and step 2 APIs remain separate work.

## Private trip reads — CI and shared homelab verified

Implementation commit `fa274b1` passed the database and contract jobs in [CI run 39937332257](https://github.com/pibeebee/C67/actions/runs/39937332257). The disposable GitHub Linux stack applied both migrations and the synthetic seed after a clean rebuild. Both pgTAP files passed: 40/40 assertions (14 foundation plus 26 private-read assertions). Public-schema lint reported no errors. The HTTP suite passed 39/39 checks through real local Auth sessions, then removed its temporary data and stopped the stack.

New evidence covers empty/default owner lists, start-time/UUID ordering across page boundaries, account-bound/invalid cursors, persisted detail, uniform missing/foreign 404s and non-finite-date rejection. Existing copy/retry/isolation checks also pass. OpenAPI 0.2 and all three fixtures validate, generated catalog copies remain consistent, and local Python syntax/whitespace checks pass.

This CI stack uses PostgreSQL 17.11; shared homelab remains PostgreSQL 17.6. All four CI jobs passed at documentation checkpoint `4a425bb`. The [approved homelab plan](../history/homelab-trip-reads-plan.md) has also been executed: both databases restored on the exact shared image, 40/40 isolated pgTAP assertions and 40/40 shared HTTP checks passed, the new migration is recorded by the official runner, all 11 services are healthy and the original account/catalog remain with zero trips. Temporary users/data/container were removed. See [actual shared results](../history/homelab-trip-reads-verification.md). Both private RPCs are deployed; native Swift repository/UI integration is separate work. See the [task](../tasks/private-trip-reads.md).

## Trip model foundation (stage 3A) — CI and shared homelab verified

Implementation `d9d90f3`, [CI run 39988491177](https://github.com/pibeebee/C67/actions/runs/39988491177): three SQL test files pass 79/79 pgTAP assertions, public-schema lint reports no errors, and real-session HTTP acceptance passes 54/54 checks on the disposable CI stack. OpenAPI 0.3 and five fixture files validate; original catalog copies/seed remain consistent. Existing API tests are retained and pass alongside new identity, destination-time and revision checks. No Swift source changed; all four CI jobs passed at c9164b4, including the Simulator check.

This verifies a clean migrated stack, V1/V2 compatibility, two-account privacy, source version attribution, legacy null-zone behavior, changed-zone/API-generation conflicts, concurrent retries and UTC/date/DST boundaries. The [approved homelab execution](../history/homelab-trip-model-verification.md) additionally restored both databases on PostgreSQL 17.6, proved an upgrade over a persisted synthetic legacy trip without changing its snapshot/owner/request/retry behavior, and passed 79/79 isolated pgTAP assertions before shared application.

Stage 3A is deployed: official history has all three migrations, and 55/55 shared HTTP checks passed. Final state: 11 healthy unchanged containers, one original Auth account, one catalog version/root and zero trips; temporary accounts/trips/draft/root/container were removed. Private backups and exact source hashes are recorded in the [plan](../history/homelab-trip-model-plan.md) and results. Revision alone does not demonstrate optimistic concurrency or retry-after-edit support; see [ADR-0003](../architecture/decisions/0003-trip-model-foundation.md).

## Normalized trip graph (stage 3B) — backend CI verified

Implementation dd94b14, [CI run 40046041636](https://github.com/pibeebee/C67/actions/runs/40046041636): four SQL files pass **141/141** assertions (79 existing + 62 new), public-schema lint reports no errors, and the expanded real-session HTTP suite passes **66/66** checks. OpenAPI 0.4 and nine fixtures validate, including known/unknown graph and both landing templates; generated catalog/seed copies are unchanged. Python syntax, documentation links and whitespace checks pass. All four implementation CI jobs passed, including Simulator; no native source changed.

Evidence includes distinct origin/landing/first-stop segments, first-stop landing with/without an origin, null unknowns, integral/fractional JSON duration boundaries, stable whole-graph retries, four concurrent retries, separate occurrence identities, source-change independence, owner RLS on every child table, composite cross-trip/day/source rejection and guarded parent cleanup. The seven earlier API payloads remain compatible through the retained suite.

This CI verifies clean migration and all creation paths. Existing persisted V1/V2 backfill still requires the [prepared homelab procedure](../history/homelab-trip-graph-plan.md) in a restored isolated clone before shared deployment. Read-only preflight found 11 healthy services, one user/catalog/root, zero trips and exactly three prior migrations; existing stop arrays satisfy the normalization contract. No stage 3B shared mutation is claimed. The graph is one initial source/day 0, with no scheduler/provider, public edits, lifecycle transition or native integration.

## Consolidated backend stages 3B–7 — source/CI complete, shared gate pending

Giovan closed PR #4 and requested one PR after the complete backend batch. PR #4 is closed and no replacement is open. Source checkpoint c55aef6 passed all four [CI jobs](https://github.com/pibeebee/C67/actions/runs/40255936842) on 26 October: **167/167 SQL assertions**, clean SQL lint, **66 retained HTTP checks**, **16 complete-backend acceptance checks**, **2 image-decoder tests**, read-only API health and the restricted production Docker image smoke. OpenAPI 0.5/10 fixtures validate. The worker's pinned npm runtime dependencies report zero known vulnerabilities. No Mac Docker was started.

Acceptance actually exercised real password/refresh sessions, query-bound discovery pagination, CAS edit races, permanent creation/apply receipts, root/day/date reschedule, explicit source append and retained-occurrence overlap choices, private Storage byte upload/download denial, reported-location session checks, delayed lease recovery/stale finalization, decoded JPEG publication without input EXIF, accepted journal/album, invalid bytes rejection, protected documented topology and exact synthetic account/row/object cleanup. Service-role credentials were confined to setup/worker/cleanup; traveller JWTs established privacy. No real person's media/location was used.

Read-only shared preflight still found 11 healthy services, one original account/catalog/root, no trips/buckets/objects, three migrations and no media worker. The four pending migrations and one new worker are **not deployed**. The [consolidated plan](../history/homelab-backend-completion-plan.md) supersedes the earlier graph-only plan and pins input hashes and exact backup/restore/backfill/Storage/runtime writes. Existing postgres is not the storage.objects owner/member; the existing supabase_admin migration login was verified read-only and will be used only within the approved plan, without granting new rights.

The agreed scope is curated catalog, private albums, session-start reported-location policy, planned-only edits/merge, no completed/skip/ended_early or public authoring. See [ADR-0005](../architecture/decisions/0005-backend-mvp.md), [completion task](../tasks/backend-completion.md) and [operations](../operations/backend-operations.md). Source/CI completion is not shared runtime, physical-device, field GPS, media authenticity, off-host recovery or load certification. The review PR remains deferred until operational verification is complete.

## Consolidated backend stages 3B–7 — shared execution complete

The separately approved [combined plan](../history/homelab-backend-completion-plan.md) is executed. [Full shared evidence](../history/homelab-backend-completion-verification.md): two-database restore on exact PostgreSQL17.6, V1/V2 persisted backfill/receipts after edits, **167/167 isolated SQL assertions**, four official migrations (seven total), **67 retained + 17 completion = 84 shared HTTP checks**, private Storage/actual image validation/journal/album and exact cleanup. A diagnosed Cloudflare1010 denial affected Python-urllib; the binary suite now uses its existing C67 client identity. No gateway/Cloudflare policy changed.

Original Auth account/catalog/root fingerprints remain; final test rows and Storage objects are zero, two buckets are private/empty. The new restricted image worker is healthy; all 11 existing Supabase containers are unchanged/healthy, database ports stay unpublished, and the isolated test container/tunnel were removed. Private backup checksums/permissions pass. Physical-device, field-GPS, production capacity and off-host/scheduled/full-object-service disaster recovery remain unverified as documented; native integration is a handoff, not claimed by server acceptance.

## Design-system reference — 27 October 2026

Scope: documentation only, on `gi/design-system-guide` from `origin/main` at `53732bc`. The [design-system guide](../product/design-system.md) transcribes the user-supplied visual reference and is linked from root/UI instructions, the UI README and the reserved implementation folder. See the [task handoff](../tasks/design-system-guide.md).

All seven affected Markdown files passed local path/link, fence and whitespace checks; 48 relative links resolve. The documented 11 text styles, three brand HEX values and spacing/radius/touch values were checked for transcription consistency. Source filename, dimensions and SHA-256 are recorded in the guide. The original backend checkout remained clean; no Swift, font, project, API or server file changed. At this documentation-validation checkpoint, publication had not yet been requested; commit, push and PR were subsequently authorized in the task handoff.

No Simulator/build/database test was run for this documentation-only change. Runtime Gabarito rendering, Dynamic Type behavior, color contrast, Light/Dark visuals, accessibility and formal HIG conformance remain unverified. The source's HIG label is not treated as audit evidence.


## Native traveller sessions and API queries — 28 October 2026

[Auth/API task](../tasks/ios-auth-api.md), branch `gi/ios-auth-api` from main `5e2d943`:
**21 package tests passed**, plus **6 C67 Simulator tests passed** on iPhone 18 Pro / iOS 27.0
(4 native Account/Keychain and 2 mock UI tests). Tests ran after code changes. Native Keychain
create/update/read/delete and backend isolation require an ad hoc signed Simulator test host;
an initial unsigned failure was corrected by using `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`.
CI uses those flags with explicit `C67_DATA_MODE=mock`; no signing team or storage downgrade added.

The live Account form/navigation/dismiss test passed separately at standard and accessibility XXXL
text sizes, with screenshots inspected. A temporary external Swift probe using the changed adapter
read a real HTTPS `search_rundowns` page from the configured homelab (one published synthetic item).
No shared Auth account, trip or database object was created. Live catalog loading also ran in the app.
Pinned formatting, contract/fixture/seed validation and whitespace checks passed.

This establishes native session logic against synthetic Auth responses, real Simulator Keychain,
mock UI, live form rendering and a real public query. Successful homelab traveller login/refresh/logout,
owner trip/graph reads, physical devices, iOS 18 runtime and a full accessibility audit remain
unverified. Search/My Trips/graph UI and remaining server RPC adoption are separate slices.
No commit, push, PR or server deployment occurred in this batch.


## Expanded native Auth/session — 28 October 2026

[Current Auth task and verification](../tasks/ios-auth-api.md) supersede the earlier existing-account-only
checkpoint. Package tests: **29 passed**. Final native unit/integration run: **9 passed, 1 skipped**
(shared cohort already cleaned), on iPhone 18 Pro / iOS 27.0. The matching isolated GoTrue v2.197.0
and real SMTP sink exercised registration/resend/PKCE/relaunch/refresh/recovery/password update/
logout with actual Simulator Keychain. A prior combined run passed all 9 then-existing tests,
including real shared native two-account owner privacy and both mock UI smoke paths.

Shared Auth callback/password/refresh settings were deployed with private config backup and rollback;
only Auth restarted, its 10 Supabase siblings retained IDs/start times, confirmation remains required,
and final shared counts are one original user/zero trips. The exact temporary shared accounts,
owned trips, isolated fixture containers/volume/networks/files and SSH tunnel were cleaned.
SMTP verified TLS/authentication; external inbox delivery was not tested. Release Simulator build passed.

Interactive signup form typing now passes. The native strong-password suggestion intercepted
XCTest input; the test closes that suggestion before entering synthetic text, preserving native
SecureField/AutoFill behavior. Passive Account restore also no longer clears callback error feedback.
A regression test checks preservation until an explicit successful retry.

Final targeted verification on iPhone 18 Pro / iOS 27.0, Xcode 27.1: **9 passed, 0 skipped** (six
Account/Keychain/state tests plus three live UI scenarios). Account and registration/recovery
passed with Accessibility XXXL text and scrolling. A system-opened synthetic callback from Home
reopened Account and displayed the missing pending-flow error. Screenshots were inspected. This
is OS-routing/rejection evidence; real PKCE exchange was exercised by the isolated test above.
A final standard-text run also passed all three live UI cases.
The attempted Dark launch argument did not change screenshot appearance and was removed;
Dark appearance, physical-device/iOS 18 evidence and external inbox delivery remain unverified.

Final clean mock scheme run: **11 passed, 4 skipped** with all live opt-ins disabled; no failures.
The skips cover the isolated provider, shared cohort, live form and system callback tests. No
commit/push/PR occurred. All 99 affected local Markdown links resolved; private configuration
values were absent from unignored source, pinned formatting passed for all 36 Swift files, and
whitespace checks passed. Release contains no inherited Debug endpoint/key.


## Native Sign in with Apple — 28 October 2026

[Apple task](../tasks/apple-auth.md): native button, nonce/state, Supabase ID-token exchange, existing
Keychain/refresh/logout isolation and matching Apple credential-revocation checks are implemented.
Shared Apple provider activation subsequently passed as recorded below; Apple Developer provisioning/real authorization remain pending.

Package: **34/34 passed** (HTTP stubs, including five Apple transport/session cases). Full mock
Simulator scheme: **15 passed, 4 intentionally skipped**, including Apple nonce/state/expiry and
revoked-vs-transient credential-state tests. Final live UI: **3/3 passed**, iPhone 18 Pro / iOS 27.0,
Xcode 27.1, Accessibility XXXL. Exported screenshots confirm the official button and scrollable
forms. The synthetic email/recovery and system-callback regressions pass without sending email
or completing Apple authorization. The test helper loads lazy Form rows before XCTest taps;
it does not mistake a large row's isHittable snapshot for a failed action. No Dark/device claim.

Before activation, homelab preflight and TLS-verified `/auth/v1/settings` HTTP 200 confirmed Apple disabled.
The guarded deployment helper passes compilation and preservation/overwrite/drift-layout checks;
its read-only plan pins only three Apple environment keys and an Auth-only restart with backup,
rollback and sibling lifecycle verification. No live Auth configuration or database write occurred during that implementation checkpoint.
The exact [plan](../history/homelab-apple-auth-plan.md) was subsequently approved and applied as recorded below. No matching local signing profile was
found; an entitlement in source/ad-hoc Simulator signature does not establish Developer capability.

OpenAPI/fixtures/bundled copy/seed validate. All 119 affected local Markdown links resolved,
private configuration values were absent from unignored source, formatting passed for 41 Swift
files and whitespace checks passed. No commit, push or PR occurred for this extension.

Unsigned Release build for generic iOS also passed. Its bundle remains live with empty production
client credentials and no inherited homelab endpoint; the Apple entitlement is present in the
source configuration. Xcode reports the existing interface-orientation warning and AppIntents
metadata-skip message; no device provisioning or real Apple authorization is implied.


## Shared Apple provider activation — 28 October 2026

Giovan explicitly approved the reviewed native-only Apple provider activation. Rechecked fingerprint
matched the approved plan; only the three Apple settings in Auth changed, with nonce checks enabled
and audience `io.pibeebee.c67.starter`. The same GoTrue v2.197.0 image was recreated for Auth only.

Auth is healthy. Ten other Supabase service IDs/start times are unchanged. Private backup
`/home/giovan/backups/c67/before-apple-auth-2026-10-28T061902Z` passes checksum and permission checks;
`.env` and tunnel Compose are unchanged. TLS-verified public settings HTTP 200 reports Apple=true
and email=true. No rollback was needed, no database operation was issued, and no real Apple login
was attempted. Apple Developer capability/provisioning and user authorization remain the final
acceptance gates. See [deployment and rollback record](../history/homelab-apple-auth-plan.md).

## Primary checkout consolidation — 28 October 2026

At Giovan's request, the native Auth/API work and merged design-system guide were consolidated
into the primary C67 checkout on `gi/trip-graph`, matching the project opened in Xcode. The existing
Apple signing team was retained in `project.yml`; the Apple entitlement uses the existing
`apps/ios/C67.entitlements` file. The generated project and callback configuration were checked.
Ignored development/server configuration and the previously staged entitlement were preserved.

Verification from the consolidated checkout: Simulator build/install/launch passed; the Swift
package passed **34/34** tests; `C67UITests/StarterUITests/testAccountUsesConfiguredMode` passed
**1/1** in live mode on iPhone 18 Pro / iOS 27.0. It opened Account and verified the native Apple
button plus email/password controls without submitting credentials. SwiftFormat and whitespace
checks passed. Xcode's visible project path, `gi/trip-graph` branch, selected signing team and
Sign In with Apple capability were observed. No real Apple authorization was performed.

Private archives include tracked/untracked files, meaningful ignored configuration, original Git
indexes and patches; archived bytes were verified with SHA-256. A verified Git bundle and local
branch refs retain history. After destination-file comparison, the unused `C67-ios-auth-api` and
`C67-design-system-guide` worktrees were removed. Only the primary checkout remains.
At the consolidation checkpoint the changes were local and uncommitted; Giovan subsequently
authorized commit, push and a review PR.

## Auth PR preparation — 28 October 2026

The consolidated checkout passed the full mock C67 scheme on iPhone 18 Pro / iOS 27.0:
**15 passed, 0 failed, 4 intentionally skipped** (isolated/shared integration and live UI opt-ins).
The previously recorded 34/34 package tests and 1/1 live Account UI check remain applicable;
no Swift implementation changed after those checks. OpenAPI/fixtures/seed validation, SwiftFormat,
Python source parsing, ignored-config checks and whitespace checks passed before commit.

After the user reported signing in, a read-only database transaction confirmed an Apple identity
with a recent sign-in, a session and an owned trip. This establishes live backend sign-in acceptance;
Hide My Email, relaunch/refresh/logout/revocation and device-specific acceptance are not inferred.
No new shared data/configuration write or deployment was performed during PR preparation.

## Journey POC custom origins and destination preferences — 6 November 2026

The standalone C67 Journey app supports selectable origins, multiple Jakarta target areas and required sourced spots. All 265 package test functions and 26 Showcase unit/UI cases passed. A bounded Mac MapKit probe returned address/POI results for three non-Bundaran-HI origins. The final signed app was installed on the iPhone; automatic launch was blocked by its locked screen. Simulator Demo evidence does not establish physical-device routing, live WeatherKit or field acceptance. See the [task and evidence record](../../research/poc-journey/docs/tasks/journey-custom-origins-and-areas.md).

## Recommendations Sketch slice — 11 November 2026

The generic Simulator build and relevant mock UI interactions passed on iPhone 18 Pro / iOS 27.2, including an accessibility text-size check. The shared `packages/C67Backend` package passed 34 tests on macOS. Xcode Canvas rendered the Home, processing and recommendation list previews; the native Home menu was separately exercised by UI test. Targeted SwiftFormat lint passed for 17 files. The repository-wide check reports formatting in 13 other files, including existing Preferences, Splash, evaluation and TripSense changes; those unrelated edits were preserved. Live provider, physical-device, VoiceOver and iOS 18 runtime acceptance remain unverified. See the [task record](../tasks/recommendations-swiftui.md).


## Connected Hi-Fi UI completion — 11 November 2026

The new Add Places, saved itinerary, save-name alert, populated Home and per-stop arrival screens are connected to the existing planner and trip events. Final generic Simulator build passed. Fourteen creation unit tests and two recommendation UI checks passed together (16/16); the focused regression run passed 17/17 after fixing the three failures in the broader run. Latest results cover all 15 affected iPhone UI cases on iPhone 18 Pro / iOS 27.2. The iPad Pro 11-inch (M5) / iOS 27.2 rendered eight screen states and separately passed a reading-width check plus an accessibility audit for descriptions, traits and text clipping. This does not establish a full VoiceOver or contrast audit.

The shared package passed 34 tests; targeted formatting passed 47 files and whitespace checks passed. The full formatter still reports 16 unrelated existing files. Add Places was observed in Xcode Canvas after clearing a stale initializer-link cache. Live provider/search, physical-device, full VoiceOver/Reduce Motion and iOS 18 runtime acceptance remain unverified; iPad retains its existing orientation warning. See the [task and result record](../tasks/hi-fi-ui-completion.md) and [Canvas guide](../../apps/ios/README.md).


## Journey POC consolidation — 9 November 2026

A separate `codex/poc-journey-consolidation` worktree starts at main `48d7139` and carries the existing local Journey POC changes. Showcase is the user entry point; Trip Integration remains the shared engine. The original publication manifest and dated reports are preserved, with 20 reviewed maintained-source changes in a separate development ledger.

Local checks passed 265 shared package test functions, 51 Python tests, 55 CLI tests, 126 native harness tests and four native Simulator builds. App/UI coverage is 39 unique cases: six unaffected Foundation Lab cases from full runs, three corrected Quality cases from a targeted rerun, four Trip Integration cases and 26 Showcase cases. TJ offline checks matched all 64 expected outcomes, covered 1,000 departure/access inputs and audited 5,552 pinned-source observations without invariant failures. These include expected conflicts and unsupported/missing-data cases; source coverage is distinct from runtime routing.

The original checkout's pre-existing content and index were preserved. Unrelated icon archives added during execution were retained and excluded from the worktree. No source commit, push, deployment, remote CI run or new live-provider/device acceptance is claimed. See the [consolidation report](../../research/poc-journey/docs/consolidation-report-2026-11-09.md) for bundle provenance, corrected failures and preservation evidence.

## PR 17 compatibility and CI repair — 12 November 2026

Policy update: PR 17 now targets `dev` under the [local-first workflow](../tasks/dev-main-ci-policy.md). Feature review uses local evidence; only dev/main promotions require the compact cloud gate. The earlier full-cloud runs were cancelled, not passed. Reconciliation preserved application/client/server/contract sources from `3f03dd1`; local quick verification passed 22 planning tests, 36 Swift package tests, four policy tests, contracts and formatting. Prior targeted Simulator results below remain dated evidence rather than a new full run.

The focused itinerary drag, recalculation and saved-order test passed on GitHub's iOS 18.5 / Xcode 16.4 runner. Related creation unit tests and Home/creation UI suites passed 26/26 locally in mock mode on iPhone 17e / iOS 27.2. The earlier full iOS 18.5 run passed Home sizing after correcting native fallback padding but failed the drag scenario; that failure remains recorded rather than treated as a successful full run.

The temporary diagnostic workflow was removed. Starter checks retain all existing suites, cancel superseded PR runs, avoid a duplicate successful menu wait and preserve failure logs/result bundles. A subsequent ARM style job was cancelled without running any steps because GitHub could not allocate a hosted runner; production style/iOS checks now select standard Intel runners, with Xcode 16.4 explicit for the compatibility suite. Final approval is gated on all checks for the final PR head. See the [repair evidence and acceptance gate](../tasks/pr17-ci-repair.md); physical-device, manual VoiceOver and live planning-service acceptance remain separate.

## Reasonable Luna ordering integration — 15 November 2026

The new untimed Pocket path passed 39 Python service tests, 63 shared Swift tests,
44 creation/preference app unit cases and three synthetic UI cases on iPhone 18
Pro Max / iOS 27.2, Xcode 27.2. Contract fixtures and the pinned 662-file formatting
check passed. Review/save retains unknown places, nullable duration, source context
and request identity without ETA/hours prerequisites. One actual five-place
request fetched five Open-Meteo records and ten calculated light windows, then
failed at Luna with HTTP 524 after about 125 seconds. Selection/error handling was
observed; successful live generation/review/save is not claimed. No automatic
provider retry or substitute answer was used. See [full evidence](../evidence/pocket-order-integration-2026-11-15/README.md)
and [scope](../tasks/pocket-reasonable-order-integration.md). Shared deployment,
physical-device/TestFlight and later Hi-Fi work remain separate.

## Pocket ordering save diagnosis — 15 November 2026

The live retest reached a saved trip detail titled `Live order acceptanceacceptance`; the test expected `Live order acceptance`. The test's cursor-relative deletion left a suffix. The replacement helper now selects the entire value and verifies exact text before Save. The untimed save dialog now describes retaining the recommendation. App unit suite: 34 passed; repository rename/save/reload/start regression: 1 passed; formatting and whitespace checks passed. No new UI interaction test or provider call was run. The native selection menu and final exact-title UI assertion remain pending the next acceptance run. See [diagnosis, changes and logs](../tasks/pocket-order-save-debug.md).

## Second save-name correction — 15 November 2026

The next live UI acceptance failed on the Select All menu's semantic tap. The helper now taps the menu center coordinate and retains exact text assertions. Adjacent review also fixed the presenter's rename busy-state and stale-session response gaps. 37 app unit tests and all 63 package tests passed; app/UI test targets compiled; formatting and whitespace checks passed. No UI interaction tests or provider calls were executed in this correction. Menu interaction and complete UI save remain pending. See [full diagnosis and logs](../tasks/pocket-order-save-debug.md#second-correction-after-the-0844-live-ui-run).


## Connected trip-flow repair and live acceptance — 15 November 2026

The unstable rename test interaction was replaced with trailing-edge taps and verified clearing, retaining exact-name assertions. The itinerary retry path now retries the requested name instead of applying an old title after a rename failure. The full connected UI run passed 16/16, and a separate actual server/Luna five-place UI acceptance passed 1/1 through exact rename/save, all five saved stops, trip start and manual first arrival on iPhone 18 Pro Max / iOS 27.2. The live run logged one Luna request, 104.884 seconds, reported `gpt-6-luna` / `max` / Responses; saving and starting did not regenerate the recommendation.

App unit definitions: 110 passed, 4 external opt-ins skipped, 0 failed. Client package: 63 passed. Pocket synthetic server: 39 passed. Contracts, all 662 Swift files' pinned formatting check and whitespace check passed. The earlier failed UI attempts are retained and distinguished from the final passing run. Live input pins are fixed public test data; actual server/model processing uses in-memory trip storage, while package tests separately exercise persistence. No physical-device, full VoiceOver, iOS 18 runtime, provider dashboard or deployment acceptance is implied. See [the task](../tasks/pocket-order-save-debug.md) and [complete logs, request/result and screenshots](../evidence/pocket-flow-repair-2026-11-15/README.md).


## Pocket ordering recovery on the normal app — 15 November 2026

The normal Pocket app reported the missing development read token and opened settings on the existing five-place draft. A separate live test used the app’s Keychain and local Pocket server, left processing with Continue later, relaunched the app and recovered all five places with one server job and one Luna call (136.155 seconds). Both focused UI tests passed on iPhone 18 Pro Max Simulator with iOS 27.2. The Swift package passed 64 tests. See [the repair and evidence](../tasks/pocket-order-recovery.md).


## Homelab Pocket ordering and itinerary update — 15 November 2026

Pocket Beta v3 runs in the existing homelab Compose project behind `https://pocket.giovanc.com`. The existing volume and connection credential were preserved. A live authenticated order returned all three selected public test places in 78.8 seconds, and a repeated submission reused the job. Three focused synthetic Simulator UI tests, 65 Swift package tests and 39 Python server tests passed. See [deployment, rollback and UI evidence](../tasks/pocket-homelab-itinerary-hifi.md).


## Pocket driving ETAs and local reorder — 15 November 2026

The device now quotes actual automobile ETA and road distance from MapKit. Manual reorder preserves the original Luna response and reroutes without a new ordering request. 67 package tests and two focused synthetic Simulator UI cases passed. The production MapKit adapter separately returned real Jakarta quotes before and after reorder on macOS with a synthetic order fixture. See [checks and evidence](../tasks/pocket-mapkit-driving-eta.md).

## Home and recommendation Hi-Fi refresh — 15 November 2026

The empty Home screen now presents a plan action wired to the existing recommendation flow, and the recommendations list heading follows the supplied Hi-Fi. The map symbol is a system placeholder for the reference illustration. Preference selection limits, departure date editing and active navigation behavior were not changed.

On iPhone 18 Pro Max Simulator (iOS 27.2), eight mock UI tests for Home and recommendations passed, including large text, selection removal and saving. A final targeted Home test passed after correcting the button label color. Results: `/tmp/c67-hifi-update-tests.xcresult` and `/tmp/c67-hifi-home-final.xcresult`. SwiftFormat and `git diff --check` passed. This does not establish physical-device or live-provider behavior.

## Preference and POI presentation — 15 November 2026

Preference search and quick picks use their parent group symbols. MapKit POI categories are mapped to display labels and SF Symbols in recommendations, selected places and main spot; unknown categories use a generic pin. On iPhone 18 Pro Max Simulator (iOS 27.2), six synthetic recommendation UI tests passed, including search, selection and removal. After a symbol availability test found an unsupported symbol, it was replaced; eight preference/catalog tests and two focused UI tests passed on rerun. Results: `/tmp/c67-hifi-poi-20261115.xcresult` and `/tmp/c67-hifi-poi-verified.xcresult`; the failed diagnostic remains in `/tmp/c67-hifi-poi-final-20261115.xcresult`. Live MapKit discovery and physical-device display were not checked in this pass.

## Itinerary departure date — 15 November 2026

Experience itineraries support selecting a departure date and time and recalculate driving estimates while preserving the Luna order. POI icons and labels use the same MapKit category mapping as recommendations. The 67 Swift package tests passed, including date persistence and no additional order request; the focused synthetic iPhone 18 Pro Max Simulator UI test passed for opening/cancelling the editor, reordering and saving. The first UI attempt failed because the test matched two Cancel buttons, and the corrected rerun passed. UI interaction with a different date, live MapKit after a date change and physical-device validation remain untested. Result: `/tmp/c67-itinerary-date-final-20261115.xcresult`.

## Foreground route and completion UI — 15 November 2026

Itinerary maps request MapKit road geometry, and active trips show a MapKit route and route steps in-app. Foreground GPS arrival requires two distinct recent fixes with accuracy at most 50 m and distance plus uncertainty at most 100 m. Completion shows recorded stop names without invented visit timestamps. Pocket Simulator build passed, as did seven location/splash unit tests and a synthetic completion-preview UI test (`/tmp/c67-route-validation-20261115.xcresult`). Real route rendering, GPS arrival, denied/reduced permission, rerouting, movement and end-to-end completion have not been verified on device or with simulated movement. Existing UI tests that tap the former manual arrival button require updating for the GPS flow. This is not verified live turn-by-turn navigation.
