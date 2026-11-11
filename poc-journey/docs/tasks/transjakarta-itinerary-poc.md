# TransJakarta BRT itinerary POC

Status: Completed
Owner: Hendra / Codex
Branch: hendra/poc-fm-mapkit

## Outcome

Add an explicit TransJakarta BRT plus walking choice to Trip Integration and create/export a sourced Blok M itinerary with the existing venue, weather, proposal and persistence flow.

## Scope and decisions

- Use official, attributed GTFS Schedule data for a bounded corridor-1, direct-bus experiment.
- Consider direct walking for local legs and BRT access/egress walks for longer legs. Transfers are deferred.
- Use one full published headway as an explicit waiting buffer. This is a scheduling assumption with uncertainty.
- Search platforms within 800 m, at most two per endpoint, and limit each walking component to 20 minutes.
- Reuse the existing routing engine through its provider injection point. Keep older stored car requests readable.
- Only poc-journey changes are in scope. Signed device/provider execution using Hendra's configured App ID is authorized by the ongoing POC.
- No commit, push or deployment is authorized.

## Acceptance

- [x] Imported corridor-1 data retains source hash, operator/category, calendars, patterns and frequency semantics.
- [x] Interactive transport selection, per-leg walking/bus/wait evidence, attribution and export work.
- [x] Deterministic checks cover timing, boarding identity, repeated stops, limits, unavailable walking, cancellation, deadlines and legacy decoding.
- [x] Native-provider itinerary generation and an appropriate Simulator/device flow are executed and reported.

## Verification

Run the journey package/build/UI commands appropriate to the change. Record explicit synthetic/live-GTFS-estimate modes. Preserve original evidence and put new raw results in fresh ignored directories.

## Result

Implemented the explicit transport option, attributed corridor-1 import, bounded walking/GTFS provider, per-leg proof, backward-compatible storage, UI and exports. Preserved the existing routing optimizer and separate experiment storage.

The final signed iPhone run passed six scripted cases covering car comparison, BRT itineraries with 1/3/6 places, +30-minute revision and impossible-deadline rejection. WeatherKit was available, with valid cache reuse. An independent audit checked the six exported plan artifacts and nine available BRT components. Thirteen TransJakarta package cases, 245 total journey package tests, eight Python scoring tests and 13 final Simulator UI tests passed. All three apps built for Simulator. The initial provider timeout and UI scrolling failures, corrections and retained evidence are described in the [execution report](../../apps/c67-trip-integration/docs/transjakarta/REPORT-2026-11-06.md).

Physical boarding/accessibility, actual bus headways, manual interruption and human recommendation relevance remain open. The implementation and evidence are local and uncommitted.
