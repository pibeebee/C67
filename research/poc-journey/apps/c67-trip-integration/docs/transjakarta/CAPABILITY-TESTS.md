# TransJakarta-only capability tests

The routing improvements use a v3 compatibility manifest and a separate paired evaluation. Run `rtk proxy python3 poc-journey/scripts/evaluate_transjakarta_improvements.py --output poc-journey/.verification/YOUR_NEW_RUN` to capture the complete package regression, 501 before/after inputs and the 64-case/1,000-input suite. The active compatibility fixture is [transjakarta-capability-v3.json](../../Packages/TripIntegration/Tests/TripIntegrationTests/Fixtures/transjakarta-capability-v3.json). Historical v2 results below retain their original meaning. Legacy schema-v1 rejection probes cover compatibility, while paired network tests measure the expanded runtime.

The suite targets **TransJakarta agency Tije only**. It contains 64 core scenarios, 1,000 engine variations and an optional complete-network source audit. The [TJ-only execution report](TJ-ONLY-REPORT-2026-11-06.md) records v2 results. The previous [v1 report](CAPABILITY-REPORT-2026-11-06.md) and manifest are preserved as historical evidence.

## Run from the repository root

```sh
rtk proxy env POC_OUTPUT_DIR=poc-journey/.verification/YOUR_NEW_RUN \
  bash poc-journey/scripts/verify.sh transjakarta
```

For all TJ source-pattern audits, supply the original matching capture:

```sh
rtk proxy env POC_OUTPUT_DIR=poc-journey/.verification/YOUR_NEW_RUN \
  TJ_GTFS_ZIP=/absolute/path/to/captured-transjakarta-gtfs.zip \
  bash poc-journey/scripts/verify.sh transjakarta
```

The ZIP must match the manifest SHA256. The command never downloads or silently refreshes a feed. Without the ZIP, full-network audits are explicitly `missing_data`; the 64 core scenarios and 1,000 bundled-snapshot engine inputs still run. Each run requires a fresh nested `capabilities` output directory. No live provider, paid API, Simulator, signing account or physical journey is used.

## Scenario inventory

[transjakarta-capability-v2.json](../../Packages/TripIntegration/Tests/TripIntegrationTests/Fixtures/transjakarta-capability-v2.json) records the historical TJ-only specification. All scenarios declare `operators: [Tije]`. The current [BuswayCapabilityTests.swift](../../Packages/TripIntegration/Tests/TripIntegrationTests/BuswayCapabilityTests.swift) uses v3 and is hashed in each run. The manifest is bundled in the test target. T16 now verifies custom-origin input with geographic validation, and T39 expects recovery of the third usable platform.

| Cases | Coverage |
| --- | --- |
| T01–T04 | Direct corridor-1 legs outside Blok M and a walking-only control. |
| T05–T08 | One/two BRT interchanges and cross-city TJ targets. |
| T09–T16 | BRT–non-BRT, non-BRT directly, Mikrotrans and an alternate/out-of-bounds origin. |
| T17–T24 | Corridors 2, 3, 9, 13 and 14; Royaltrans B14; Transjabodetabek B51; Bus Wisata BW1. |
| T25–T40 | Disconnected/same-named stops, opposite direction, exit/re-entry, unavailable access, opening/closing/midnight, inactive calendar, last boarding missed by 1/5 minutes, +30-minute revision, return unavailable, 800-metre/20-minute cutoffs, third-nearest valid platform and accessibility gaps. |
| T41–T48 | Citywide catalog boundary, mandatory venue deadline, sourced TJ coffee/Wi-Fi preference, invalid counts, missing callback/partial walking, stale feed, cancellation and restart of TJ work, save/reopen/export/reject. |
| T49–T58 | Corridors 4–8 and 10–12; Rusun 11C; a target with three TJ interchanges. |
| T59–T64 | Short missed window followed by a later bus; six stays of 15/30/45/60/75/90 minutes; NaN/infinite/negative walking; wrong walking endpoint; zero headway/reversed service window; forged stop occurrence. |

The full source confirms candidate route/category identities. Geographic and route-combination labels describe requested tests; they do not establish an operational connection. Runtime rejection of an additional route/category is a capability gate, not a generated TJ itinerary. Current runtime coverage remains direct corridor 1 plus walking, and the end-to-end venue controls remain catalog-limited.

T01 alights at northbound **Kali Besar G00060** in the Kota area. T02 boards southbound **Kota G00061**. These are different locations. Platform-to-platform diagnostic legs do not establish the final walk to a visitor's destination.

## Three separate evidence layers

1. **Runtime core:** 64 parameterized cases call existing feed/request gates, the direct planner, explicit replay itinerary pipeline, proof validators, callback seams and storage/export. Results are `supported_feasible`, `supported_conflict`, `unsupported_capability`, `missing_data`, `provider_failure` or `defect`. Walking-only controls do not count as TJ bus support. Conflicts include documented search limits; they do not prove no real-world journey exists.
2. **Runtime sweep:** 10 directed corridor-1 pairs × 10 WIB hours × 5 additional access durations (0/1/5/15/30 minutes) × 2 walking durations (120/1,201 seconds). Each of the 1,000 inputs has a fresh planner/provider. This remains a corridor-1 regression and does not claim coverage of other TJ routes. Access delay is part of walking and can cross the 1,200-second component limit.
3. **Full TJ source audit:** all 241 routes and 694 trip patterns from the matching ZIP, spanning BRT, Angkutan Umum Integrasi, Mikrotrans, Transjabodetabek, Royaltrans, Rusun and Bus Wisata. Eight probes per pattern produce 5,552 source observations. They check call ordering; pickup/drop-off restrictions; weekly calendar and absent holiday data; before-opening, morning, evening plus 30 minutes, after-midnight and last-window queries. Frequency diagnostics retain a full-headway assumption. Exact-times service remains a gap instead of being treated as frequency service.

Source observations use `tj_source_audit_only` and always set `generatedAppJourney: false`. A `source_available` window is not an application itinerary or a prediction of actual bus arrival. Shared boarding coordinates and explicit transfer records are recorded as candidates only; paid-area access, minimum walking/transfer time, fares and interchange accessibility are not inferred.

## Evidence and acceptance

Each run retains `T01.json`–`T64.json`, `sweep.json`, `network-audit.json`, `summary.json`, `REPORT.md` and `swift-tests.log`. The summary captures source/manifest hashes, host and command. Missing results, wrong outcomes, unsupported cases claiming a generated journey, incomplete sweep/source matrices and failed Swift tests fail the run. Invalid source references/ordered-call invariants also fail; expected source calendar/timetable gaps remain visible.

Core walking counts are optional when not instrumented. Sweep counts are synthetic walking calls, not network traffic. Local calculation times do not measure provider latency or travel-time accuracy. Run broader package regressions separately with `rtk proxy bash poc-journey/scripts/verify.sh packages`.
