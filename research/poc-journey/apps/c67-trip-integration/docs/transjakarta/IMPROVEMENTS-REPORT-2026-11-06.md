# TJ itinerary improvements and paired evaluation

Captured 2026-11-06T10:54:08.631847+00:00. Overall result **PASS**.

## Implemented behavior

Platform discovery first checks ordered route connectivity within 800 metres. Up to 64 candidates are evaluated per direct/transfer stage, with a total budget of 128 walking lookups per calculation. The direct search expands beyond the previous nearest-two-platform filter. Walking durations are cached within a calculation and provider errors eligible for retry receive at most one additional attempt under the existing throttle.

The default pipeline loads the expanded attributed TJ network. Direct services are preferred, with up to one transfer as a fallback. Transfer candidates originate from identical boarding stops, shared parent stations or explicit recommended GTFS links. Every transfer requires a walking result and an additional authored 120-second buffer before the next full-headway wait. Endpoint and transfer walking components retain the 20-minute policy.

For local itinerary legs, provider-verified walking of at most 15 minutes is prioritized. This policy was introduced to keep six-venue calculations inside the request budget. The first expanded-network regression exhausted 128 walking requests on the six-venue case. That failure motivated this policy and is retained in the execution history.

The Showcase offers the existing sourced Jakarta catalog alongside Blok M and accepts a configurable origin for live location verification. A visit-time budget appears during setup, selection and review. Impossible total dwell is rejected before location requests. Explicit actions can extend the trip by one hour within the same day or shorten visit durations by 15 minutes, preserving chosen venues for recalculation.

## Paired measurements

Each pair uses the same departure and synthetic walking model on a frozen pre-change planner and the improved planner. The network group also changes from the original corridor-1 snapshot to the expanded runtime snapshot. Each OD is a diagnostic platform/end-location query.

| Group | Cases | Before feasible | After feasible | Recovered | Regressed |
| --- | ---: | ---: | ---: | ---: | ---: |
| Usable platforms behind nearer decoys | 200 | 20 | 200 | 180 | 0 |
| Nearby destination alternatives | 100 | 100 | 100 | 0 | 0 |
| Expanded-network source endpoint pairs | 199 | 12 | 195 | 183 | 0 |
| Official two-corridor transfers | 2 | 0 | 2 | 2 | 0 |

| Group | Before / after p50, ms | Before / after synthetic walking calls | Cases reaching candidate limit |
| --- | ---: | ---: | ---: |
| Usable platforms behind nearer decoys | 0.042 / 0.272 | 410 / 400 | 0 |
| Nearby destination alternatives | 0.508 / 1.169 | 370 / 660 | 20 |
| Expanded-network source endpoint pairs | 0.053 / 15.075 | 47 / 2616 | 125 |
| Official two-corridor transfers | 0.040 / 3.291 | 0 / 18 | 1 |

The platform group deliberately places 0–19 closer unusable stops around a valid platform at ten departure hours. These are correlated synthetic adversarial cases. The alternative-destination group uses ten original corridor-1 OD pairs with normal synthetic walking to nearby alternatives. The network group selects one published pattern and usable endpoint pair per imported route at 09:00 WIB. Actual chosen services may differ from the requested source route when an alternative reaches the same destination. The official transfer group restricts the attributed source to the two named corridors so that the connection itself is exercised.

These rates measure the fixed test sets. Walking accessibility, real bus waiting, traffic, field transfer entrances and travel accuracy require their own observations. Additional candidates trade calculation work and walking requests for coverage. Per-leg timings exclude planner initialization, source decoding/validation and network I/O. End-to-end pipeline latency includes additional work.

## Runtime source coverage

The runtime imports 199 routes, 544 patterns and 6773 stops from the original captured ZIP.

| Imported pattern category | Count |
| --- | ---: |
| Angkutan Umum Integrasi | 157 |
| BRT | 143 |
| Bus Wisata | 5 |
| Mikrotrans | 201 |
| Royaltrans | 6 |
| Rusun | 28 |
| Transjabodetabek | 4 |

The importer retains complete patterns inside the existing Jakarta geographic boundary. Of the original 694 patterns, 149 cross that boundary and one uses exact-times service. These exclusions are recorded instead of clipping patterns or changing service semantics. Broadening the physical coverage and handling scheduled exact-times service remain follow-up work. Published pickup/drop-off restrictions are enforced. The original source date and ZIP hash are retained.

## Unresolved paired inputs

| Case | Synthetic walking calls | Candidate limit reached | Requested source route calendar |
| --- | ---: | --- | --- |
| network-1T | 15 | True | All patterns for requested route inactive on 2026-11-07 under the published weekly calendar. Alternative search remains bounded. |
| network-6P | 2 | True | All patterns for requested route inactive on 2026-11-07 under the published weekly calendar. Alternative search remains bounded. |
| network-7R | 1 | True | All patterns for requested route inactive on 2026-11-07 under the published weekly calendar. Alternative search remains bounded. |
| network-7U | 2 | True | All patterns for requested route inactive on 2026-11-07 under the published weekly calendar. Alternative search remains bounded. |

A nil result can reflect the tested time, access policy, service restrictions or bounded search. The remaining cases require case-specific route/connection inspection before assigning a root cause.

## Regression and compatibility

Package verification exit code 0. The active 64-case compatibility suite and 1,000-input sweep were captured alongside the paired tests.

Core outcome counts `{'supported_feasible': 11, 'unsupported_capability': 31, 'supported_conflict': 16, 'provider_failure': 4, 'missing_data': 2}`. Sweep outcomes `{'supported_feasible': 320, 'supported_conflict': 680}`.

The legacy single-route feed gate remains covered by the 64-case suite. Its unsupported-gate counts describe that compatibility contract. Active network support is measured by the paired network group above. T39 now verifies recovery of the third valid platform. The explicit over-limit walking cases continue to reject.

Old stored journeys decode through the original single-ride fields. A new optional connection retains the second ride, transfer walking, source link and buffer. Storage audit checks source membership and transfer provenance. The UI and Markdown export include both rides; geometry outside the original sidecar appears as stop pins with an availability explanation.

Separate regression cases check a missed onward window, missing transfer edge, pickup prohibition, forged onward timing, numeric/coordinate provider failures, transient retry and cancellation, and early dwell infeasibility. Package logs, paired observations and source hashes are retained in this run directory.

## Explicit defaults and remaining acceptance

One-transfer fallback, the authored two-minute interchange buffer, the 15-minute local-walking priority and bounded candidate/request counts are implementation defaults selected for this POC. A direct feasible service is returned before exploring transfer alternatives. This preserves a bounded search and can miss a faster connecting service.

The full-headway buffer remains the acceptance policy. Calibrating waiting uncertainty requires field or verified realtime observations. Accessibility and holiday exceptions remain unresolved. Demo coordinates and weather are synthetic. Live signing, device provider behavior and physical trips require separate acceptance.

## Final verification and execution history

| Layer | Verified result |
| --- | --- |
| TripIntelligence | 57 XCTest functions passed. |
| PreferenceLearning | 29 XCTest functions passed. |
| VisitTiming | 59 Swift Testing functions passed. |
| PreferenceQuality | 40 Swift Testing functions passed. |
| TripIntegration | 71 Swift Testing functions passed, including six improvement tests, the 64 parameterized compatibility cases and the 1,000-input sweep. |
| Total package regressions | 256 test functions passed. The 501 paired inputs, 64 parameterized cases and 1,000 sweep inputs are counted separately from function counts. |
| Python script regressions | 39 tests passed, including importer provenance, bounds, category/restriction retention and transfer child-platform expansion. |
| Showcase Simulator | 15 tests passed on iPhone 17e with iOS 26.4.1, including city-catalog persistence, time-budget actions, itinerary save/reopen/export and prior guided-flow regressions. |
| Trip Integration Simulator | The existing TJ replay review/accept UI test passed on the same Simulator. |
| Native POC builds | All four applications passed unsigned Simulator builds. |

The final package and paired run is preserved under ignored `.verification/tj-improvements-20261106-verified/`. UI result bundles and logs are under `.verification/tj-improvements-20261106-ui/`, with `ShowcaseCorrected.xcresult` and `TripIntegrationTJ.xcresult` as the final UI evidence. Four-app build logs are under `.verification/tj-improvements-20261106-builds/`. The published report formats group labels for reading, while the original generated report and JSON retain the captured group IDs and hashes.

Several intermediate failures were resolved and remain documented.

- The first expanded-network six-venue replay exhausted the walking budget. The implemented provider-verified local-walking priority restored that regression within the same request cap.
- The first city-catalog integration fixture selected Erasmus Huis on Monday. The published schedule lists that day as closed. The positive fixture moved to Tuesday, and the sourced closure rules remained enforced.
- The first combined benchmark/regression run blocked MainActor long enough to trigger an unrelated weather-cache test's provider timeout. The paired harness now yields between benchmark inputs. The complete rerun passed the weather-cache tests and all 256 package functions.
- One intermediate Showcase build failed because a new catch block shadowed the model's error property. Explicit property assignment corrected the compilation failure. The corrected Simulator suite and four-app build passed.

The earlier `final` and `reviewed` evidence directories are intermediate runs. The `verified` directory is the final package/paired result. Existing v1/v2 capability reports retain their original test scope and counts. The active v3 compatibility suite retains legacy single-route gate tests, so its 31 legacy unsupported observations do not describe the expanded runtime's network coverage.

On the 200 known platform-search cases, feasibility increased from 10% to 100%. On the 199 source-route endpoint pairs it increased from approximately 6.0% to 98.0%. Both percentages describe these fixed synthetic test sets. The four unresolved endpoint pairs concern requested routes 1T, 6P, 7R and 7U, all with inactive weekly calendars on the tested Saturday. Alternative search reached its candidate cap, which remains an explicit limitation.

The original 1,000-input exact-platform sweep still returns 320 feasible legs and 680 expected access/service conflicts. Its 600 deliberately over-limit walking inputs remain rejected. The broader synthetic-walking comparison is the measurement for recovered platform and network coverage.

Additional request work accompanies the coverage increase. The 100 nearby-destination inputs use 660 synthetic walking calls after the change versus 370 before. The expanded-network group uses 2,616 versus 47 while recovering 183 previously unavailable endpoint pairs. These counts include newly evaluated alternatives and newly reachable OD pairs. Real provider latency and throttling need live measurements. Candidate pruning reduced this network group's calls from 3,683 in an intermediate measurement to 2,616 with the same 195 feasible results.

Source-pattern import and routing use seven TJ categories, but the endpoint benchmark can choose another supported service serving the same destination. Per-row `routeIDs` and `categories` in the raw paired JSON identify the actual chosen services. Importing a category does not establish that every timetable or journey in that category was exercised successfully.

The new transfer detail UI compiled and existing guided UI regressions passed. The official transfer was exercised through the shared itinerary pipeline, audit, storage and Markdown/JSON export. A dedicated UI gesture run for a transfer itinerary and physical interchange observation remain pending. The retained appearance test name alone does not establish actual Dark rendering or a manual accessibility review.
