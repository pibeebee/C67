# C67 Journey Showcase

A separate iOS 26+ SwiftUI POC for creating a one-day itinerary through a guided UI. The app offers the sourced Blok M and Jakarta catalogs and reuses the sibling Trip Integration package for factual recommendation gates, hours, weather, routing, audit and proposal persistence. Setup accepts an origin query for live verification and shows the visit-time budget with explicit duration/deadline adjustments.

## Run

Open `C67JourneyShowcase.xcodeproj`, select scheme `C67JourneyShowcase`, and run on an iOS 26+ Simulator. The default mode is **Demo**. Demo search, walking/car durations and weather are authored inputs with visible synthetic labels. Maps load base tiles and visible walking/car road geometry from MapKit online. The map labels Demo timing separately. Demo is available in Debug and Release configurations.

Generate the project from this directory with `xcodegen generate`. The post-generation hook adds the dictionary-valued WeatherKit capability. The bundled Gabarito font is registered through the generated Info.plist and retains its SIL OFL license.

The app is installed separately using bundle ID `com.hendra.pocjourney.showcase`. Signing uses the operator's own local team override. WeatherKit requires this new App ID's matching service and provisioning configuration. The older `com.hendra.pocjourney` app has its own entitlement/provisioning history.

## Guided flow

1. Create a trip with a date, WIB departure/deadline, 1–6 places, visit duration and car/taxi or TransJakarta + walking.
2. Pick interests or continue with general recommendations. Advanced controls set mandatory and avoided attributes.
3. Review sourced place suggestions, adjust selections and mark mandatory destinations.
4. Confirm the location when MapKit finds multiple valid candidates, then calculate the itinerary.
5. Review the map, transport/visit timeline, weather, conflicts and source details. Open a TJ leg for the corridor, direction, platforms, headway buffer and ordered intermediate stops.
6. Save a feasible current proposal, reopen it after relaunch, make a +30-minute proposal, accept/reject it, and export Markdown/JSON.

The footer stays reachable while content scrolls. Every map provides zoom-in, zoom-out, fit-route and full-screen controls. Embedded maps support pinch zoom with vertical page scrolling. Full-screen maps support panning and zoom. Walking lines follow MapKit road geometry, and bus lines follow the attributed GTFS shape. Unavailable routes show a loading/failure status and a retry action.

## Modes and storage

The “Mode dan sumber” toolbar opens Demo/Live selection and WeatherKit diagnosis. Switching mode cancels the current calculation. Each mode uses separate draft, session, provider logs and exports under `Application Support/C67JourneyShowcase/<mode>`. One draft and one accepted itinerary are presented. The shared store retains immutable run artifacts and a previous-session backup.

Demo uses the original catalog/feed clock and date provenance. Live calls MapKit and primary WeatherKit, enables the existing E5/category path and keeps Open-Meteo fallback opt-in. Unavailable facts, weather or routes stay explicit. Edited inputs invalidate pending results, and accepted data survives a rejected proposal.

Debug-only `--journey-live-check` runs an isolated personalized coffee/Wi-Fi itinerary with real providers, acceptance, reload and export. It writes `Documents/JourneyLiveChecks/<UUID>` and does not write normal user-mode storage. `--journey-test-id <unique name>` isolates UI-test data and uses visibly labeled test-only road geometry. Normal map presentation requests road shapes only for displayed itinerary legs. Preview, full-screen and detail maps share the geometry cache. Requests are paced, cancelled when no visible consumer needs them, and protected against late callbacks and missing native completions.

## TransJakarta scope and geometry

The POC loads an attributed Jakarta TJ network subset with 199 routes and 544 patterns. Route-aware platform discovery considers access within 800 m, with a 20-minute limit per walking component. A feasible direct service is preferred, followed by a one-transfer fallback using GTFS candidate links, provider walking, a two-minute authored transfer buffer and a full headway per boarding. Candidate paths are capped at 64 per stage and walking lookups at 128 per calculation. Provider-verified local walks up to 15 minutes are prioritized in itinerary routing. Transient walking failures can receive one paced retry.

Transfer timing, platform identity and both services appear in detailed UI and JSON/Markdown exports. The network geometry sidecar covers 542 of 544 imported patterns with 178,587 vertices. JAK.59-R03 and 3H-R06 fail the ordered 150-metre projection constraint and retain an unavailable-geometry explanation. The original corridor-1 sidecar remains available for compatibility. Field entrances, accessibility, observed headways and holiday exceptions require additional evidence.

`BuswayGeometryCatalog` loads an optional sidecar keyed to the routing ZIP SHA256. The importer maps ordered stop occurrences to shape vertices within 150 m and preserves loop occurrences. Missing/mismatched geometry yields an explicit pin-only explanation. It never supplies replacement travel times.

The sidecar can be regenerated from an existing matching capture, from the repository root.

```sh
python3 poc-journey/scripts/import_transjakarta.py --input-zip PATH_TO_CAPTURED_ZIP --feed poc-journey/apps/c67-trip-integration/Packages/TripIntegration/Sources/TripIntegration/Resources/transjakarta-corridor-1.json --geometry-output poc-journey/apps/c67-trip-integration/Packages/TripIntegration/Sources/TripIntegration/Resources/transjakarta-corridor-1-geometry.json
```

Use `--output` and optional `--geometry-output` when explicitly downloading a new routing snapshot. Existing reports retain their original dates and hashes.

## Verify and evidence

From the repository root, `bash poc-journey/scripts/verify.sh packages` runs shared package tests, and `bash poc-journey/scripts/verify.sh build` builds all four native POC apps. Set `P3_SIMULATOR_DESTINATION` and run `verify.sh ui` for the existing apps and the new Showcase unit/UI suites. Use a fresh ignored `POC_OUTPUT_DIR` for each execution.

See [visual rules](docs/DESIGN.md), [execution report](docs/REPORT-2026-11-06.md), and the [task brief](../../docs/tasks/journey-showcase.md). Source attribution is retained in the [journey third-party record](../../THIRD_PARTY.md).

## Custom origins and destination preferences

New trips use the combined Jakarta catalog. In setup, search and select a start/return point; Live searches MapKit addresses and POIs within Jakarta, while Demo offers labeled synthetic origins. In preferences, select one or more areas and optionally search the sourced catalog for required spots. Area constraints, required spots, hours and verified attributes all apply together. Empty or conflicting matches remain visible. Arbitrary searched venues are not assigned inferred opening hours.

See [implementation and verification](../../docs/tasks/journey-custom-origins-and-areas.md).

## PR review repairs — 9 November 2026

Journey is contributed with its required shared engine. The standalone Foundation Lab and Trip Integration diagnostic UI/UITests retain current main; their historical consolidation results do not describe a new execution after this scope adjustment.

Creating a new Live trip preserves English E5 matching; Demo retains its synthetic non-embedding defaults. Regression coverage includes mode changes and restored Live drafts. The area/required-spot controls are composed from smaller views to avoid the compiler crash observed on the CI toolchain, with existing labels and accessibility identifiers preserved. Run `verify.sh journey-models` with `P3_SIMULATOR_DESTINATION` for the provider-free model and geometry regression suite. See the [repair task](../../docs/tasks/pr12-journey-fixes-2026-11-09.md) for current verification.
