# Task: Native Foundation Models and MapKit experiment

Status: Ready for review
Owner: Hendra / coding assistant
Reviewers: Not assigned
Branch: hendra/poc-fm-mapkit (existing task branch)

## Outcome

Build an isolated TripSense POC using native model tool calling, real MapKit search/routes and deterministic scheduling. Explicit user request authorizes a standalone MVVM experiment; C67's VIPER/backend architecture remains owned by its existing areas.

## Scope and dependencies

- Allowed: `research/tripsense-poc/`, this task and verification links.
- No external dependencies, backend, shared database, commit, push or deployment.
- Preserve existing `AGENTS.md` changes and `.serena/`.
- Requires iOS/macOS 26+, eligible Apple Intelligence device and ready model assets for live inference. MapKit requires network access.

## References

- [Existing architecture](../architecture/architecture.md), [product context](../product/product-context.md).
- User's attached TripSense POC specification, 3 November 2026.

## Acceptance criteria and verification plan

- First compile/run the smallest Foundation Models → Tool → MapKit probe; record observed outcome.
- Build standalone iOS app and run deterministic Swift Testing coverage of themes, routes, hours, duration, invalid IDs and unavailable services.
- Keep fixtures explicit, reject unverified model IDs and never derive routing metrics/hours from model text.
- Record SDK, command/test evidence and live/device limitations in the POC report.
- Run formatting, whitespace and scoped diff review.

## Result and handoff

- Implemented: separate [Xcode project](../../research/tripsense-poc/TripSensePOC.xcodeproj), native model/search/route tools, typed outputs, deterministic category/ID/count/schedule validation, unknown/verified/demo hours, map/cards/removal, cancellation and diagnostics.
- Commands: `rtk swift test --package-path research/tripsense-poc/TripSenseKit` — 17 deterministic tests pass; default live test skipped. `TRIPSENSE_LIVE_TEST=1` with `--filter LiveIntegrationTests` — one actual Mac model → Tool → MapKit test passes.
- iOS: generic Simulator build passes; `xcodebuild test` on iPhone 18 Pro iOS 27.2, ad hoc signed — 2 application unit tests pass, no UI automation. [Machine-readable test result](../../research/tripsense-poc/evidence/ios-tests.json).
- Live scenarios A/B/D executed using Mac Foundation Models and MapKit; C covered with explicit hours fixtures. [Report](../../research/tripsense-poc/FEASIBILITY.md) records failures and limitations, including unrelated model choice, excessive count, over-budget rejection and heuristic slower than baseline.
- Setup/architecture/API sources: [POC README](../../research/tripsense-poc/README.md). No existing C67 contract, architecture ADR or backend change.
- Physical-iPhone execution, visual/accessibility/light-dark inspection, reliable live venue hours and better route ordering remain unverified.
- Final checks: pinned SwiftFormat check passes (0/66 files need formatting); `git diff --check`, new-file whitespace and local documentation links pass. Scoped source/project/evidence review found no provider credentials or accidental build products. Existing unrelated `AGENTS.md` and `.serena/` changes remain untouched.
- No commit, push, deployment or shared mutation performed. Existing unrelated changes preserved.

### Xcode local-package repair — 3 November 2026

The user reported project-loading errors and missing `TripSenseCore` in Xcode despite the earlier CLI build. Moved the standalone package manifest/sources/tests into `research/tripsense-poc/TripSenseKit`, renamed the package to TripSenseKit and replaced the self-root `path: .` dependency with `path: TripSenseKit`. The app project/scheme/product stay TripSensePOC/TripSenseCore. Earlier experiment commands in captured evidence refer to the previous layout; current commands are in the README. Fresh-cache package resolution succeeds and identifies `TripSenseKit` at the new path. A generic iOS Simulator build with fresh `/tmp/tripsense-package-repair` derived data passes; 17 deterministic package tests pass (live test explicitly skipped), pinned SwiftFormat and whitespace checks pass. The obsolete root `.swiftpm` generated workspace was backed up outside the repository. Xcode GUI reopening remains a user-side check; close previously opened package workspaces and reopen the app `.xcodeproj`.

### Route optimization and sourced opening hours — 3 November 2026

Status: Ready for review. Implemented the agreed four-stage plan: bounded exhaustive candidate/order optimization, departure-time validation, OSM-backed opening hours with conservative matching, and baseline/fixture/live evidence. Scope: standalone TripSense POC and its documentation only. Preserve unrelated changes and distinguish unknown or community-reported hours from verified hours. External authorization: no commit, push, deployment or shared database changes.

#### Optimization verification results

- `rtk swift test --package-path research/tripsense-poc/TripSenseKit`: **38 deterministic Swift Testing tests pass**, one opt-in live test skipped in this default run. Tests include an independent Heap-permutation comparator for one through six destinations, 720-order/36-ETA bounds, locked choices, changed final ETAs, time windows, unknown/ambiguous OSM data, request cancellation and network failures. [Output](../../research/tripsense-poc/evidence/optimization-unit-tests.txt).
- `xcodebuild test` with iPhone 18 Pro Simulator iOS 27.2 and ad hoc signing: **3 app unit tests pass**, covering fixture generation/removal, locking and cancellation; no UI automation. [Summary](../../research/tripsense-poc/evidence/optimization-ios-tests.json). Generic Simulator build also passed during implementation.
- Live Mac runs A/B/D completed using actual model search and MapKit ETA/directions. Their estimated travel-time deltas against revalidated baselines were −546 s, −71 s and −422 s, respectively; mixed D selects a different combination from the same pool. Evidence and interpretation: [feasibility](../../research/tripsense-poc/FEASIBILITY.md).
- Live OSM verification is **not complete**: all six public Jakarta places were located by MapKit, but OSM provider lookup timed out (`NSURLErrorDomain -1001`). A separate direct Overpass GET returned HTTP 406; alternate endpoint status requests timed out. The unknown fallback was observed, while sourced-hours parsing/matching was tested with fixtures. Retry on a network with Overpass access before claiming OSM coverage or comparing its hours with official sites.
- No physical-device, interactive UI, screen-reader, dark/light acceptance, current Google/provider terms review, deployment, commit or push performed.

### Overpass request reliability — 4 November 2026

Status: In progress. User authorized explicit TripSense User-Agent, 60-second network timeouts within the existing 180-second optimizer deadline, shared minimum-30-second cooldown after 406/429 respecting Retry-After, and physical-device/network comparison using Irawan’s phone. Implement one fixed public query and body hash on Mac/iPhone, preserve unknown after any failure, and avoid automatic retry loops. No commit/push/deployment authorized.
