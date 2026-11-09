# Journey Showcase POC

Status: In progress
Owner: Hendra / Codex

## Outcome and approved choices

Create a separate iOS application with a complete guided itinerary creation UI, detailed TransJakarta journey maps, isolated Demo/Live storage and the existing Trip Integration engine. Cover Blok M, Bundaran HI return trips, direct corridor 1 and local walking. Use bundle ID `com.hendra.pocjourney.showcase` and iOS 26+.

## Implementation

Reuse shared recommendation, timing, native providers, audit and proposal persistence. Add attributed GTFS geometry as an optional sidecar, preserving ordered stop occurrences. Add a SwiftUI guided flow, local draft persistence, revision and export. Follow the C67 visual reference and iOS Interface Design skill. Keep unrelated work and historical evidence intact.

## Acceptance

- Guided create, recommendation, branch review, generation, map/timeline, save/reopen and revision work.
- TJ details show ordered stops, correct bus segment, walking, waiting assumption and attribution.
- Demo is explicit and deterministic. Live uses real provider results and separate storage.
- Package regression, geometry, state/persistence and Simulator UI tests pass. Capture representative screenshots and a Markdown execution report.
- Signed device and WeatherKit results use the new App ID and report any prerequisite accurately.

## Verification

Use the journey verification scripts and fresh ignored evidence directories. No commit, push or deployment is included.
