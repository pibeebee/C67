# TransJakarta and multimodal capability evaluation

Run: 2026-11-06T09:22:19.284361+00:00. Manifest: `tj-capability-2026-11-06-v1`.

## Result and interpretation

Runtime assertions: **PASS**. 48/48 core observations; 1000/1,000 variation observations.

Passing a capability gate confirms a limitation, not a successful multimodal journey. Only supported_feasible observations with a bus ride establish routing support. Walking, provider timing and modified services are explicitly synthetic; no live-provider or field-trip claim.

| Core outcome | Count |
| --- | ---: |
| missing_data | 2 |
| provider_failure | 2 |
| supported_conflict | 14 |
| supported_feasible | 8 |
| unsupported_capability | 22 |

## Capability boundary

| Capability | Observed boundary |
| --- | --- |
| Direct corridor-1 BRT outside Blok M | Runtime leg probes; catalog/UI expansion is separate. |
| Same-stop travel | Walking-only control; excluded from successful TJ ride counts. |
| BRT interchanges | Multi-route input rejected; journey contract holds one ride. |
| Non-BRT / Mikrotrans | Categories present in full source, rejected by current runtime feed gate. |
| TJ–MRT / TJ–KRL | Operator and mode gates reject rail; no rail timetable or multi-ride integration. |
| Citywide itinerary | Blok M catalog and fixed origin block this before routing. |
| Wheelchair / custom walking cap | No structured request or verified accessible transfer data. |
| Platform discovery | Third valid platform can be missed by the nearest-two limit (T39). |

## Full-feed inspection

Snapshot SHA256: `376b11f72ac30f9f4eb972ae32c7f1a3251b416dc3cd77cc573475a3b2676b9c`.

241 routes, 8139 stop records, 694 trip patterns and 25688 stop calls; 0 invalid references.

| Source service category | Routes |
| --- | ---: |
| Angkutan Umum Integrasi | 64 |
| BRT | 31 |
| Bus Wisata | 3 |
| Mikrotrans | 98 |
| Royaltrans | 13 |
| Rusun | 14 |
| Transjabodetabek | 18 |

14 explicit transfer records; 0 provide a minimum transfer duration. calendar_dates present: False. The only agency is Tije; MRT/KRL timetables are not in this ZIP.

Pickup-restricted calls: 129; drop-off-restricted calls: 66. Frequency exact_times distribution: `{'0': 746, '1': 1}`. These are concrete importer/runtime requirements for broader coverage; the corridor-1 importer cannot simply be applied unchanged.

| Candidate route from source | Published name | Category |
| --- | --- | --- |
| 2 | Pulo Gadung - Monumen Nasional | BRT |
| 3 | Kalideres - Monumen Nasional via Veteran | BRT |
| 1 | Blok M - Kota | BRT |
| 4 | Pulo Gadung - Galunggung | BRT |
| 5 | Kampung Melayu - Ancol | BRT |
| 6 | Ragunan - Galunggung | BRT |
| 7 | Kampung Rambutan - Kampung Melayu | BRT |
| 8 | Lebak Bulus - Pasar Baru | BRT |
| 9 | Pinang Ranti - Pluit | BRT |
| 1A | Pantai Maju - Balai Kota | Angkutan Umum Integrasi |
| 1E | Pondok Labu - Blok M | Angkutan Umum Integrasi |
| 1B | Stasiun Palmerah - Transport Hub Dukuh Atas | Angkutan Umum Integrasi |
| 6M | Stasiun Manggarai - Blok M | Angkutan Umum Integrasi |
| JAK.79 | Cengkareng - Tubagus Angke | Mikrotrans |
| JAK.107 | Jembatan Garden - Puri Beta | Mikrotrans |
| JAK.78A | Benda - Cengkareng Timur | Mikrotrans |

Candidate presence is data evidence only; transfer paths, entrances and travel times have not been established.

## Core scenarios

| ID | Intent | Outcome / first blocking layer | Runtime evidence |
| --- | --- | --- | --- |
| T01 | Direct TJ beyond Blok M: Bundaran HI → Kota area (Kali Besar boarding stop) | supported_feasible / routing | Actual engine leg: Bundaran HI Astra [G00034] -> Kali Besar [G00060], 1-R07. Synthetic walking; no catalog or live-provider claim. |
| T02 | Reverse direction: Kota → Bundaran HI | supported_feasible / routing | Actual engine leg: Kota [G00061] -> Bundaran HI Astra [G00031], 1-R08. Synthetic walking; no catalog or live-provider claim. |
| T03 | Short corridor journey: MH Thamrin → Tosari | supported_feasible / routing | Actual engine leg: MH Thamrin [G00036] -> Tosari [G00030], 1-R08. Synthetic walking; no catalog or live-provider claim. |
| T04 | Same-stop walking: Bundaran HI → Bundaran HI | supported_feasible / routing | Walking only, zero seconds in this authored fixture; excluded from TJ ride support. |
| T05 | One BRT interchange: Ragunan → Kota | unsupported_capability / routing | Runtime contract gate: multi-route feed rejected; journey serializes one ride only. No transfer itinerary generated for Ragunan -> Kota. |
| T06 | Two BRT interchanges: Kampung Rambutan → Kalideres | unsupported_capability / routing | Runtime contract gate: multi-route feed rejected; journey serializes one ride only. No transfer itinerary generated for Kampung Rambutan -> Kalideres. |
| T07 | East to west: Pulo Gadung → Kalideres | unsupported_capability / routing | Runtime contract gate: multi-route feed rejected; journey serializes one ride only. No transfer itinerary generated for Pulo Gadung -> Kalideres. |
| T08 | South to north: Ragunan → Ancol | unsupported_capability / routing | Runtime contract gate: multi-route feed rejected; journey serializes one ride only. No transfer itinerary generated for Ragunan -> Ancol. |
| T09 | BRT to feeder: Bundaran HI → Pondok Labu | unsupported_capability / routing | Runtime feed gate rejected Angkutan Umum Integrasi/1B. Scenario blocked before routing; inspect the full feed for actual route candidates. |
| T10 | Feeder to BRT: Pondok Labu → Kota | unsupported_capability / routing | Runtime feed gate rejected Angkutan Umum Integrasi/1B. Scenario blocked before routing; inspect the full feed for actual route candidates. |
| T11 | Feeder BRT feeder: Palmerah → Pantai Maju | unsupported_capability / routing | Runtime feed gate rejected Angkutan Umum Integrasi/1B. Scenario blocked before routing; inspect the full feed for actual route candidates. |
| T12 | Direct non-BRT: Palmerah → Transport Hub Dukuh Atas | unsupported_capability / routing | Runtime feed gate rejected Angkutan Umum Integrasi/1B. Scenario blocked before routing; inspect the full feed for actual route candidates. |
| T13 | Mikrotrans to BRT: Cengkareng via JAK.79 → Kota | unsupported_capability / routing | Runtime feed gate rejected Mikrotrans/JAK.01. Scenario blocked before routing; inspect the full feed for actual route candidates. |
| T14 | BRT to Mikrotrans: Kota → Tubagus Angke via JAK.79 | unsupported_capability / routing | Runtime feed gate rejected Mikrotrans/JAK.01. Scenario blocked before routing; inspect the full feed for actual route candidates. |
| T15 | Three service categories: Jembatan Garden via JAK.107 → Ragunan | unsupported_capability / routing | Runtime feed gate rejected Mikrotrans/JAK.01. Scenario blocked before routing; inspect the full feed for actual route candidates. |
| T16 | Beyond supported geography: Bekasi → Jakarta destination | unsupported_capability / input | Input gate rejects an alternate Bekasi origin; a separate out-of-bounds coordinate probe is rejected too. No Bekasi route evaluated. |
| T17 | TJ to MRT: TJ Bundaran HI → MRT Lebak Bulus | unsupported_capability / routing | Runtime operator and transport-enum gates reject MRT. Missing operator timetable, interchange access, and multi-ride model; no onward connection evaluated. |
| T18 | MRT to TJ: MRT Lebak Bulus → TJ destination | unsupported_capability / routing | Runtime operator and transport-enum gates reject MRT. Missing operator timetable, interchange access, and multi-ride model; no onward connection evaluated. |
| T19 | TJ MRT TJ: TJ origin → TJ destination via MRT | unsupported_capability / routing | Runtime operator and transport-enum gates reject MRT. Missing operator timetable, interchange access, and multi-ride model; no onward connection evaluated. |
| T20 | Direct bus versus MRT: Bundaran HI → Lebak Bulus | unsupported_capability / routing | Runtime operator and transport-enum gates reject MRT. Missing operator timetable, interchange access, and multi-ride model; no onward connection evaluated. |
| T21 | TJ to KRL: TJ Dukuh Atas → KRL destination | unsupported_capability / routing | Runtime operator and transport-enum gates reject KRL. Missing operator timetable, interchange access, and multi-ride model; no onward connection evaluated. |
| T22 | KRL to TJ: KRL Manggarai → TJ destination | unsupported_capability / routing | Runtime operator and transport-enum gates reject KRL. Missing operator timetable, interchange access, and multi-ride model; no onward connection evaluated. |
| T23 | Palmerah access: KRL Palmerah → TJ Dukuh Atas via 1B | unsupported_capability / routing | Runtime operator and transport-enum gates reject KRL. Missing operator timetable, interchange access, and multi-ride model; no onward connection evaluated. |
| T24 | Last KRL connection: KRL origin → KRL destination via TJ | unsupported_capability / routing | Runtime operator and transport-enum gates reject KRL. Missing operator timetable, interchange access, and multi-ride model; no onward connection evaluated. |
| T25 | Same name different stop: Named platform A → Same-named platform B | supported_conflict / routing | Disconnected synthetic patterns with same-named endpoints produce no bus journey. |
| T26 | Opposite platform: Southbound platform → Northbound destination | supported_conflict / routing | A single directional pattern does not yield a reverse ride. |
| T27 | Exit and re-entry transfer: Paid-area exit → Different paid-area entrance | unsupported_capability / routing | Runtime contract gate: multi-route feed rejected; journey serializes one ride only. No transfer itinerary generated for Paid-area exit -> Different paid-area entrance. |
| T28 | Nearby but inaccessible: Origin → Nearby destination | provider_failure / provider | Injected walking unavailability blocks the bus route; no fallback ETA. |
| T29 | Before opening: Corridor origin → Corridor destination | supported_feasible / routing | 08:00 departure + 120-second access; 09:10 boarding includes opening wait and full headway. |
| T30 | Service end exclusive: Corridor origin → Corridor destination | supported_conflict / routing | Synthetic 10:00 service end is exclusive; ready at 09:50 plus 10-minute headway is unavailable. |
| T31 | Previous service day: Corridor origin → Corridor destination | supported_feasible / routing | Synthetic 23:00-26:00 service uses the previous service day for a 01:00 journey. |
| T32 | Calendar and exceptions: Corridor origin → Corridor destination | missing_data / data | Weekly exclusion verified. Holiday exception absence is a data gap, not proof that holiday service runs. |
| T33 | One-minute connection delay: Corridor origin → Corridor destination | supported_conflict / routing | A 1-minute delay invalidates a previously available last synthetic boarding. |
| T34 | Five-minute connection delay: Corridor origin → Corridor destination | supported_conflict / routing | A 5-minute delay invalidates a previously available last synthetic boarding. |
| T35 | Visit plus 30 minutes: Mandatory venue → Return origin | supported_conflict / itinerary | +30-minute visit exceeds the baseline finish deadline; acceptance is rejected. |
| T36 | Outbound only: Corridor origin → Corridor destination and return | supported_conflict / routing | Outbound is available; reverse pattern/service is absent after the visit. |
| T37 | 800-metre access cutoff: Offset origin → Boarding coordinate | supported_conflict / routing | Actual nearby search accepts 799/800m and rejects 801m; distances constructed against the engine distance metric. |
| T38 | 20-minute walking cutoff: Origin → Destination | supported_conflict / routing | 1199/1200 seconds per walking component accepted; 1201 rejected. This is not a total-trip walking cap. |
| T39 | Third-nearest valid platform: Origin → Destination | supported_conflict / routing | Known search limitation reproduced: two closer unusable platforms hide the third valid platform within 800m. Removing decoys restores the ride. |
| T40 | Accessibility constraint: Wheelchair traveller → Destination | missing_data / input | Current request has no structured wheelchair/per-user walking constraint; GTFS coordinates cannot prove an accessible entrance. |
| T41 | Six geographically spread venues: Kota and Ragunan → Six citywide venues | unsupported_capability / catalog | Six citywide destinations are rejected at catalog validation, before recommendation/routing. Existing six-stop Blok M regression remains separate. |
| T42 | Mandatory venue deadline: Bundaran HI → Mandatory Blok M venue | supported_conflict / itinerary | Mandatory venue retained in the request; impossible deadline yields an unacceptably infeasible proposal. |
| T43 | Personalized coffee and Wi-Fi: Bundaran HI → Eligible coffee venue | supported_feasible / itinerary | Car/TJ both recommend sourced coffee/Wi-Fi bm08; complete TJ plan preserves profile and venue. Synthetic Blok M end-to-end control. |
| T44 | Invalid stop counts: Origin → Zero or seven venues | supported_conflict / input | Zero and seven requested destinations rejected explicitly. |
| T45 | Timeout and partial walking: Origin → Destination | provider_failure / provider | Native callback timeout injected without network; separate partial walking fixture prevents egress. |
| T46 | Stale feed and geometry mismatch: Origin → Destination | supported_conflict / data | Seven-day freshness boundary and geometry source-hash mismatch both rejected. |
| T47 | Cancellation and mode change: Origin → Destination | supported_conflict / routing | Cancellation terminates an in-flight native walking continuation; a fresh car request retains car mode. UI race regression is tracked separately, not claimed here. |
| T48 | Save reopen export reject: Bundaran HI → Accepted itinerary | supported_feasible / storage | Save/reopen/export preserves accepted UUID and audited bus proof after a conflicting revision is rejected. |

## Deterministic stress sweep

10 directed coordinate pairs × 10 departure hours × 5 access delays (0/1/5/15/30 minutes) × 2 base walking durations (120/1,201 seconds). A new planner and provider are created for every row. Access delay is added to the access walking component, so it can cross the existing 20-minute component cap. This does not simulate transfer delays, traffic, or actual bus reliability.

| Sweep measure | Result |
| --- | ---: |
| Feasible bus legs | 320 |
| Access/service conflicts | 680 |
| Defects | 0 |
| Calculation p50 / p95, milliseconds | 2.603 / 3.121 |
| Maximum synthetic walking calls per variation | 4 |
| Total synthetic walking calls | 2680 |
| Longest feasible fixture trip, seconds | 7253 |

Calculation timings measure this local deterministic harness, not live Maps latency or travel-time accuracy. Request counts refer to synthetic walking calls, including rejected candidate attempts; they are not live network requests.

## Next work, ordered by blocking dependency

1. Expand the sourced venue catalog and origin contract for citywide end-to-end inputs.
2. Introduce a multi-route feed and ordered multi-ride journey contract with transfer walk/wait evidence; retain service categories.
3. Validate BRT/non-BRT/Mikrotrans interchange access and timing. Full-feed coverage alone does not prove connections.
4. Acquire attributed MRT/KRL timetable/service and entrance data, then add operator adapters and last-connection tests.
5. Expose supported constraints and detailed interchange steps in UI; run bounded live checks and field observations.

## Reproducibility and limits

Raw results, Swift log, source hashes and pinned-feed inspection are kept in this fresh ignored run directory. The historical snapshot clock is fixed; no source dates are advanced to bypass freshness. Previous app/device runs are not inherited as evidence for this suite. No live providers, credentials, paid APIs, production changes, commits, or deployments are used.

## Execution history and additional verification

The initial run is preserved under ignored `.verification/tj-capabilities-20261106-initial/`. It failed T01 because the test selected southbound Kota G00061 as a northbound alighting stop. The fixture was corrected to the separately located northbound Kota-area stop Kali Besar G00060. No engine behavior was changed to make this pass. The stress sweep deliberately retains a northbound G00061 request as an unavailable-direction control. The initial evidence and original source hashes were not overwritten.

The reviewed run is retained under ignored `.verification/tj-capabilities-20261106-reviewed/`. Its manifest and source hashes are in `capabilities/summary.json`; detailed observations and the Swift log are alongside it. Earlier corrected/final runs are retained separately.

| Check | Actual result |
| --- | --- |
| Capability suite | Both Swift test functions passed; one executes 48 parameterized scenarios, the other checks 1,000 variations. These are not 1,048 separately reported Swift test functions. |
| Python script regressions | 22 tests passed, including 11 evaluator checks and 11 existing evaluator/geometry tests. |
| TripIntelligence | 57 XCTest tests passed. |
| PreferenceLearning | 29 XCTest tests passed. |
| VisitTiming | 59 Swift Testing tests passed. |
| PreferenceQuality | 40 Swift Testing tests passed. |
| TripIntegration | 65 Swift Testing tests passed, including the two new capability functions and existing 1/3/6-stop/personalization/geometry/provider regressions. |
| Total package regressions | 250 test functions passed across five packages; parameterized cases and the sweep are counted separately above. |

Package logs are retained under ignored `.verification/tj-capabilities-20261106-packages/`. This change adds test resources and evaluation/reporting tools, without changing public types, routing behavior, UI, accepted-trip formats or production code. No new Simulator, physical-device, live-provider or field-travel acceptance is claimed.

The eight feasible core observations comprise three unchanged-snapshot direct bus leg probes outside Blok M, one walking-only control, two synthetic service-window probes and two replay itinerary/persistence controls. The 22 unsupported observations are runtime capability gates; they are not 22 transit itineraries attempted against an integrated network router.

The 680 sweep conflicts include deliberately over-limit access walks and an intentionally unavailable directional pair. They are expected fixture outcomes, not an estimate that 68% of Jakarta journeys fail. Similarly, the 320 feasible results are correlated deterministic variations, not a transit recommendation accuracy score.
