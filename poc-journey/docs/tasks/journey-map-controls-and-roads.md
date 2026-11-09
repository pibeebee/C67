# Journey map controls and road geometry

Status: Complete.
Owner: Hendra / Codex

## Requested outcome

Add zoom-in, zoom-out and full-screen map presentation. Show walking and car routes using road geometry and preserve GTFS bus paths throughout the itinerary map and journey detail.

## Implementation

- Every map provides explicit zoom, fit and full-screen controls. Embedded maps retain vertical page scrolling with pinch zoom. Full-screen maps permit panning and zooming.
- MapKit calculates road geometry only for displayed walking/car segments. Shared consumer ownership coalesces requests across map surfaces and cancels unused work. Loading failures support explicit retry. Native callbacks have cancellation, timeout and request identity guards.
- Geometry is presentation data. Scheduled itinerary times retain their existing provider or Demo provenance. Test launches use isolated labeled synthetic road geometry.
- A network GTFS sidecar supplies 542 valid ordered pattern shapes. Two unmatched source patterns remain recorded as unavailable. Empty or failed road responses leave the segment without a polyline.
- The existing importer supports an explicit partial-geometry option while preserving strict default validation. The original routing snapshot and historical report hashes retain their identities.

## Verification

Run Showcase unit/UI checks on an iOS 26+ Simulator, the shared geometry tests, Python script tests, scoped Swift formatting, link/path verification and whitespace checks. Capture a bounded live MapKit road probe with public Jakarta endpoints and retain provider output separately from fixtures.

Use a fresh ignored `.verification/journey-map-20261106/` directory for this execution. Record final counts, live-provider findings and signed-device install status here when complete.

## Verified outcome

- All 22 Showcase tests passed on iPhone 17e Simulator with iOS 26.4.1. The suite includes six road-loader tests and zoom/full-screen UI verification, alongside the guided-flow checks.
- Four shared geometry tests and all 40 Python script tests passed. Scoped Swift formatting, link/path scanning and whitespace checks passed.
- A live Mac MapKit probe returned 15 walking vertices over 631 metres for Bundaran HI–Tosari and 95 driving vertices over 6,927 metres for Bundaran HI–Blok M. The captured provider records are separate from UI-test geometry.
- The signed build was installed and launched on the connected iPhone. Manual device gestures and field-route observations have separate acceptance.
- The packaged network sidecar contains 542 patterns and 178,587 vertices. JAK.59-R03 and 3H-R06 remain unavailable because their ordered stop projections exceed the 150-metre constraint.

The final UI bundle is `ShowcaseFinal.xcresult` under the task's ignored evidence directory. Earlier failed bundles retain the accessibility identifier inheritance and duplicate modal-control findings. The controls now have explicit identifiers for embedded and full-screen contexts, with the covered map hidden from accessibility while its full-screen view is presented.

Road geometry is cached for the active application session. Normal Demo and Live map presentation use online MapKit road geometry. UI test launches use explicitly labeled deterministic shapes, while itinerary timing retains its selected mode's provenance.
