# Capability and verification status

## Scoped PR #12 repairs — 9 November 2026

Journey Showcase and its required shared TripIntegration engine are the contribution. Production code, Context Lab, and the standalone Foundation Lab/Trip Integration App and UITests retain current main. The development ledger now covers 12 maintained-source changes; immutable import hashes and historical reports are preserved. Earlier consolidation UI results describe the pre-scope-adjustment run, not a new test of the retained diagnostic UI. See the [repair task](docs/tasks/pr12-journey-fixes-2026-11-09.md) for the current checks and CI status.

## Journey Showcase entry point — 9 November 2026

Journey Showcase is the guided user UI for the TJ itinerary experiment; Trip Integration owns the shared engine and diagnostic app. The current POC includes custom origins, area/required-spot preferences, car/TJ routing, transfer details, road maps, proposal persistence and exports. See the [consolidation report](docs/consolidation-report-2026-11-09.md) for new-worktree verification and the [Showcase guide](apps/c67-journey-showcase/README.md) to run it.

The following dated sections retain their historical scope; earlier corridor-1-only limitations describe those versions rather than the current network engine.


## Journey map controls and road paths — 6 November 2026

Showcase maps provide zoom-in, zoom-out, route fitting and full-screen presentation. Walking and car overlays use MapKit road geometry with shared request ownership, cancellation, timeout, cache and retry behavior. The attributed TJ geometry sidecar supplies 542 of 544 imported patterns. Unavailable shapes have an explicit status.

All 22 Showcase tests, four shared geometry tests and 40 Python tests passed. A bounded live Mac probe returned walking and driving road polylines. The updated signed app was installed and launched on the connected iPhone. Device gesture observation, field access and the two unmatched GTFS patterns remain acceptance gaps. [Task evidence](docs/tasks/journey-map-controls-and-roads.md)

## TJ routing improvements — 6 November 2026

The current itinerary pipeline uses route-aware platforms and an attributed Jakarta TJ network subset with 199 routes and 544 patterns. It supports a direct service or one-transfer fallback with provider walking, an authored two-minute interchange buffer and a full headway per boarding. The Showcase exposes the existing Jakarta catalog, configurable live origin, early visit-time budget and explicit deadline/duration adjustments. Old stored journeys retain their single-ride decoding path.

Paired tests recovered the usable third platform in 200/200 adversarial inputs, versus 20/200 before. Network source-endpoint feasibility rose from 12/199 to 195/199. Two official BRT corridor connections rose from 0/2 to 2/2. All 501 paired inputs had zero feasibility regressions. Request and timing costs increased with broader alternatives and are included in the report. The four unresolved requested routes have inactive calendars on the tested Saturday, while alternative search remains bounded.

All 256 package test functions, 39 Python tests, 15 Showcase Simulator tests and the existing TJ review/accept UI test passed. Four native POC apps built for Simulator. The active 64-case suite uses v3 for compatibility, retaining legacy single-route gate probes separately from network coverage. The original 1,000 exact-platform inputs still yield 320 feasible legs and 680 expected access/service conflicts. Historical v1/v2 reports retain their baseline scope. Live-provider latency, field transfer access, holiday/accessibility facts and waiting calibration remain acceptance gaps. [Implementation and paired report](apps/c67-trip-integration/docs/transjakarta/IMPROVEMENTS-REPORT-2026-11-06.md)

Snapshot date: **9 November 2026**. Context Lab v0.5 (5) is the active dynamic-context experiment; the table below retains original native/P3 milestones. See [Context Lab status and next steps](docs/context-lab-handoff-2026-11-09.md). These are technical experiments with bounded data. There has been no participant study demonstrating satisfaction or reduced input effort.

| Capability / project | Original evidence | Limit |
| --- | --- | --- |
| Deterministic CLI | Source, synthetic tests and recorded Google-provider experiments retained | Japan transit coverage was unsupported; provider credentials are optional, not configured by this import |
| Native adaptive hybrid routing | Benchmark, Jakarta fixture tests and Mac live validation; actual initial/dirty source snapshot retained | Bounded heuristic, not a global optimality proof |
| Local/active native replanning | P0/P1/P2A/P2B reports, local/fixture tests and Simulator observations | Distinct from the integrated app's pre-trip changes; physical trip reliability remains open |
| Standalone Weather Lab | Native/fixture evidence, initial auth failure, later user-reported success | User report is labeled separately from directly captured JSON; P3 has its own physical API proof |
| Foundation Models | Guided generation, locale/availability/fallback evidence and Mac/iPhone runs | English task scope; personal-fit quality and factual time discovery remain limited |
| Local preferences + MapKit/E5 | Native fact gates, live search and device inference | Ranking a bounded catalog is not a probability of satisfaction |
| Sourced visit timing | Published regular hours, session/entry rules, weather/solar context and extreme tests | Capacity, queues, holidays and venue conditions not guaranteed |
| Preference quality / E5 benefit | Category/BM25/E5 comparisons and repeated cases retained | Repetitions are correlated; NDCG 0.977 is not 97.7% personal accuracy |
| P3 integration v0.1 build 3 | **35/35 package, 2/2 Simulator UI, 7/7 scripted iPhone live cases** in the original location | iPhone 17 / iOS 27.0.1, Xcode 27.2; live 1–3 venues; pre-trip only |

## Relocation verification

This import changes location, public metadata and Swift layout. [Relocation results](evidence/relocation-verification.md) records checks actually run against these published copies. Historical pass counts are not automatically inherited by the import or by production C67.

The relocated copies passed 220 package tests, 55 CLI tests, 126 native fixture tests, 12 Simulator UI tests and three unsigned Simulator builds. No new physical-device or live-provider run is claimed by this handoff.

## Current development entry point

Use Context Lab for dynamic place context and its Mac-local backend; see [source export verification](evidence/context-lab-relocation-2026-11-09.md). Use Journey Showcase for the TJ itinerary flow and Trip Integration for its shared engine/diagnostics. The native lab and CLI remain independent experiments. The main C67 application's iOS 18/VIPER/backend architecture has not been replaced.

## Still open

Broader venue facts; held-out recommendation relevance; manual physical network interruption/background/input changes; four-to-six-place live scaling; iOS 26 runtime; RAM/energy; actual trip observations; and user-effort/benefit validation. [Missing records](docs/missing-evidence.md) are explicit.

## Blok M evaluation — 6 November 2026

A separate dated Blok M catalog and Debug evaluation path now exercise the existing Trip Integration pipeline. Thirty-six category/E5/general comparisons and real Mac MapKit routes for 1/3/6 places were recorded. WeatherKit remained unavailable on the Mac run. A subsequent signed iPhone 17 / iOS 27.2 run passed primary-only WeatherKit diagnosis and all 11 scripted cases. Human relevance review and physical network/background/input-change observations remain pending. See the [execution report](apps/c67-trip-integration/docs/blok-m/REPORT-2026-11-06.md) and [protocol](apps/c67-trip-integration/docs/blok-m/PROTOCOL.md).


## TransJakarta itinerary evaluation — 6 November 2026

Trip Integration adds an explicit car/taxi or corridor-1 BRT plus walking choice, with attributed static GTFS, native walking, per-leg platform/headway evidence and proposal/export persistence. A signed iPhone 17 / iOS 27.2 run passed six scripted cases covering 1/3/6 busway stops, a three-stop car comparison, +30-minute revision and deadline rejection. WeatherKit was available with valid cache reuse. The independent audit passed for all six captured plans. Final checks passed 245 package tests, eight Python evaluator tests, 13 Simulator UI cases and three app builds. The [execution report](apps/c67-trip-integration/docs/transjakarta/REPORT-2026-11-06.md) records the earlier failures and corrections, concrete itinerary, generation/request counts, assumptions and pending field/human observations.

## TransJakarta capability boundaries — 6 November 2026 (historical v1)

The [capability report](apps/c67-trip-integration/docs/transjakarta/CAPABILITY-REPORT-2026-11-06.md) adds 48 scenario observations and 1,000 deterministic variations beyond Blok M. Core outcomes: eight feasible observations (including walking/synthetic controls), 14 expected conflicts, 22 unsupported capability gates, two missing-data observations and two injected provider failures. The sweep produced 320 feasible bus legs and 680 expected access/service conflicts, with no invariant failures. All 250 package test functions and 22 Python script tests passed. Parameterized scenarios/sweep inputs are not counted as separate test functions.

Direct corridor-1 leg probes work outside Blok M. Transfers, non-BRT/Mikrotrans and TJ–MRT/KRL remain unimplemented; citywide itinerary inputs also hit the existing catalog/fixed-origin contract. The nearest-two-platform limitation is explicitly reproduced. Full-feed inspection finds 241 routes, boarding/alighting restrictions, one exact-times frequency record, and no MRT/KRL agency or minimum transfer durations. See the [protocol](apps/c67-trip-integration/docs/transjakarta/CAPABILITY-TESTS.md) and run `rtk proxy bash research/poc-journey/scripts/verify.sh transjakarta`. This is offline evidence; no new live-provider or physical-trip acceptance is claimed.


## TJ-only capability evaluation — 6 November 2026, v2

The user's revised scope is **TJ only**. The active [protocol](apps/c67-trip-integration/docs/transjakarta/CAPABILITY-TESTS.md) and [TJ-only report](apps/c67-trip-integration/docs/transjakarta/TJ-ONLY-REPORT-2026-11-06.md) replace non-TJ cases with BRT corridors 2–14, Royaltrans, Transjabodetabek, Rusun and Bus Wisata, alongside existing non-BRT/Mikrotrans cases. The v1 manifest/report remain historical.

All 64 core cases matched expected outcomes: ten feasible controls, 16 conflicts, 32 unsupported runtime gates, four injected provider failures and two gaps. The 1,000 corridor-1 engine inputs retained 320 feasible bus legs and 680 expected access/service conflicts without invariant failures. Separate source-only audits produced 5,552 observations across all 241 TJ routes and 694 patterns, covering all seven published service categories. Source availability does not establish application routing; ordered-call invariants passed, while exact-times service, prohibited pickup on two Royaltrans patterns, holiday exceptions and transfer-duration gaps remain explicit.

All 250 package test functions and 34 Python tests passed. Run `rtk proxy bash research/poc-journey/scripts/verify.sh transjakarta`; provide `TJ_GTFS_ZIP` for the full source audit. The application remains direct corridor 1 plus walking; no new UI/live-provider/field-trip acceptance is claimed.

## Custom origins and destination preferences — 6 November 2026

C67 Journey now starts new trips with a combined 26-candidate Jakarta catalog. Setup supports selecting a start/return coordinate from MapKit addresses/POIs in Live, or seven explicitly synthetic Demo origins. Preferences support multiple target areas and required sourced spots before recommendation. Area, preference facts, opening hours and mandatory destinations apply together, with visible conflicts and no silent venue replacement. See the [task and current verification](docs/tasks/journey-custom-origins-and-areas.md). This extension preserves the existing TJ routing limits and does not establish complete Jakarta venue coverage.
