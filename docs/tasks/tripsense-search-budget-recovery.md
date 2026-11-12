# Task: Recover from repeated search calls on iPhone

Status: Ready for review; physical iPhone retest pending
Owner: Hendra / coding assistant
Reviewers: Not assigned
Branch: hendra/poc-fm-mapkit

## Outcome

Prevent repeated model search calls from discarding a usable retrieved catalogue, and show a concise error without tool internals or coordinates when planning cannot finish.

## Scope and dependencies

- Standalone `tripsense-poc/` package/app, focused regression checks and documentation.
- Keep the five-search limit, requested stop count, native ID/category validation and routing/availability rules.
- Use one explicitly local, tool-free finishing attempt only when a wrapped search-budget failure follows sufficient retrieved candidates. Do not recover unrelated failures or fabricate places.
- Preserve unrelated evaluation changes. No commit, push, deployment or physical-device installation is authorized by this task.

## References

- User's iPhone 17 screenshot of `SearchPlacesTool` wrapping `PlanningError.toolBudget`.
- [POC guide](../../tripsense-poc/README.md) and existing CandidateSelector/MapServices implementation.

## Acceptance criteria

- [x] Reproduce the wrapped budget error at the selection orchestration seam.
- [x] Finish once without tools from already retrieved candidates, or fail clearly when insufficient.
- [x] Do not swallow cancellation, network, unrelated tool or invalid-ID errors.
- [x] User messages contain no tool dump, coordinates or underlying diagnostic payload.
- [x] Package regressions and relevant Simulator app validation run; physical iPhone retest remains separately reported.

## Verification plan

Use deterministic Swift Testing with the actual Foundation Models ToolCallError wrapper, existing synthetic places and injected generation closures at the production selection seam. Run the package suite, compile the standalone iOS app and run app tests on an available Simulator. Review whitespace and scoped formatting.

## Result and handoff

- Root cause: `MapServices.search` throws on the sixth search; the model's three-search prompt limit is not enforcement. Foundation Models wraps this in `ToolCallError`. Previously the entire selection failed and the ViewModel displayed the wrapper's localized description, including captured origin coordinates. The screenshot establishes the limit branch was reached, but does not establish why the model kept searching or how many suitable candidates were found on that phone.
- Added a production orchestration seam and reproduced the exact Foundation Models wrapped search-budget failure with synthetic retrieved places. The focused test failed before the recovery implementation and passed afterward.
- Recovery: catch only searchPlaces + toolBudget, check cancellation and sufficient matching candidates, run one fresh explicitly on-device session with an empty tool list and a compact retrieved catalogue, then apply the existing native selector and optimizer. No extra search, fabricated places, count reduction or cloud fallback.
- Added safe user-facing error mapping for generation/recalculation. Unknown errors use a generic message; tool state and coordinates are not shown. Diagnostic logs retain error types and recovery counts without dumping the tool.
- `rtk swift test --package-path tripsense-poc/TripSenseKit`: 52 deterministic tests passed; one opt-in live test skipped (53 tests discovered). Six new regression tests cover recovery, insufficient candidates, unrelated wrapped failures, invalid recovered IDs, cancellation and redacted user messages.
- `xcodebuild test` for TripSensePOC on iPhone 17 Pro Simulator / iOS 26.4, destination `platform=iOS Simulator,id=FBC5F4BA-CDB5-4B06-B86B-182FF71BAEE6`, ad hoc signing and `/tmp/tripsense-search-budget` derived data: build and all three fixture app tests passed. This does not exercise live model or MapKit behavior on iPhone.
- Scoped pinned SwiftFormat passed for all five touched Swift files; `git diff --check` passed.
- Existing evaluation documents/results remain unrelated and were preserved. No physical-device install, live-provider calls, commit, push or deployment performed. Rebuild the app on the user's iPhone and repeat the same input; inspect the redacted Diagnostics counts if it still stops.
