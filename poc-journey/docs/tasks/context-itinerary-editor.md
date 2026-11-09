# Context itinerary editor implementation plan

Status: Ready for review
Branch: codex/context-itinerary-editor

## Goal and approved design

Extend the Context Lab personal screen with pre-departure replace, reorder, delete and add. Edit a separate draft, calculate a fixed-order preview, compare, and explicitly apply a local revision. Keep the previous version. Use automobile or TransJakarta plus walking for the whole trip. Recommendations and manual place search remain separate provenance paths. Jakarta, one day, return to origin, one to six unique stops, direct TJ or one transfer.

## Tasks and verification

- [x] Add fixed-order planning and transit waiting evidence; prove fixed subsequences, hard constraints, return waiting and old JSON compatibility in PlaceContextEngineTests.
- [x] Add a shared public TJ routing facade and REST walking adapter; test direct/transfer/walking, unavailable service, provenance and budgets. Connect DynamicTripService and add revision preview contracts/endpoint.
- [x] Add locally persisted draft/preview/applied revision state and input identity checks. Preserve state on cancellation, expiry, relaunch and failure.
- [x] Add Context Lab edit/picker/compare UI and transit map segments. Exercise replace/add/delete/reorder/apply/cancel/relaunch with deterministic fixtures.
- [x] Update maintained-source evidence with explicit manifest ownership, preserve immutable import records, run package/Python/format/build/UI checks and write a new result report.

## Review focus

Stale asynchronous results; server restart/prepared identity expiry; deleted mandatory visits; final return transit waiting; historic map/draft identity mismatch. Failures must retain the accepted itinerary and expose recovery.

## Boundaries

No production API or database changes. The original implementation scope excluded commit, push, new PR, deployment and GTFS refresh; commit and push were subsequently authorized. Raw results stay in ignored .verification. Live acceptance requires locally available provider credentials and is reported separately.

## Execution ledger

- Start: clean consolidation HEAD 3995a6a includes current main 72a8c95; created local feature branch. Native execution uses the executing-plans skill; the approved user plan is the binding design.

- Planner milestone: new fixed-order/default-compatibility and transit-wait accounting tests passed. Context package suite and Trip Integration regression passed before final UI/map changes; final reruns pending.
- UI milestone: initial draft/relaunch/cancel case passed. The first combined edit test reached/appplied the revision but checked a lazy offscreen preview too early; scrolling was corrected and the two-case rerun passed.

- Fresh review: three important findings (stale initial response, rain capture, failed save divergence) and the total-wait display were fixed and covered by focused model tests.
- Fixture automation correction: no-op bindings retain request identity, lazy-list controls must be brought into a safe visible region, and the editor map has its own identifier so the underlying accepted map cannot satisfy the assertion. Combined editor model/UI run passed 10/10. Fixture-only traces stay in the app test container.
- HTTP boundary: ephemeral loopback replay service returned health 200, missing bearer 401, and authenticated preview without providers 503. The process was stopped and no real credentials were loaded.
- Final review limitations: the supported inherited reviewer model was used after an optional model override was unavailable; no independent re-review followed the fixes. Live/provider/field acceptance remains open.

- Shared app regression: full Journey Showcase Simulator suite passed 26/26 (18 app/model + 8 UI); unsigned Showcase and ContextHarness builds passed locally on Xcode 27.2.
- Final package regression: 125 XCTest cases completed (124 passed, one explicitly gated historical benchmark skipped) plus 35 Swift Testing cases passed. The standalone Trip Integration suite passed 81 cases. These suites overlap and are not summed as independent coverage.

- Delivery acceptance: latest ContextHarness build and combined tests passed 10/10; Showcase regression passed 26/26. Final static checks passed, including 55 Python tests, 3,415 immutable imports with 33 ledger entries, portability and formatter/whitespace checks. Evidence summary is `.verification/editor-20261109/summary.json`.
- At the verification checkpoint, delivery was a local diff without commit/push/PR/deployment. Original checkout was not edited. Live provider and physical-device checks require operator configuration and remain unverified.
