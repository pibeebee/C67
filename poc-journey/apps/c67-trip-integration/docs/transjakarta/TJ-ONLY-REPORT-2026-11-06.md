# TransJakarta-only capability evaluation — v2

Subsequent implementation expanded route-aware search, TJ network coverage, one-transfer routing, time-budget controls and the sourced Jakarta catalog. The paired evaluation records the updated behavior and recovered inputs. This v2 report retains the original baseline results. [Improvement report](IMPROVEMENTS-REPORT-2026-11-06.md)

Run: 2026-11-06T09:41:52.976061+00:00. Manifest: `tj-only-capability-2026-11-06-v2`.

## Result and interpretation

Runtime assertions: **PASS**. 64/64 core observations; 1000/1,000 variation observations.

Passing a capability gate confirms a limitation, not a successful multi-service TJ journey. Only supported_feasible observations with a bus ride establish routing support. Walking, provider timing and modified services are explicitly synthetic; no live-provider or field-trip claim.

| Core outcome | Count |
| --- | ---: |
| missing_data | 2 |
| provider_failure | 4 |
| supported_conflict | 16 |
| supported_feasible | 10 |
| unsupported_capability | 32 |

## Why conflicts, unsupported cases, simulated provider failures and gaps occur

The explanations below refer to the captured v2 observations, not to measured failures during physical bus journeys. Expected rejection, absent implementation and unavailable evidence have different meanings. The original outcome labels and counts are retained; the subgroups below clarify their causes without changing or rerunning the historical results.

### Conflicts: 16 core cases

`supported_conflict` is an umbrella label in this evaluator. It includes infeasible itinerary constraints, deliberate input/proof rejection, a cancelled operation and a known search limitation. It must not be read as 16 valid passenger journeys that the engine unexpectedly failed to route.

| Cases | Reproduced cause | Why the result occurs | Practical implication |
| --- | --- | --- | --- |
| T25 | Same-named stops belong to disconnected patterns. | Stop names alone do not establish a connection; the synthetic patterns have no permitted direct ride between the requested endpoints. | Correctly avoids inventing a transfer. This does not prove that the real network has no alternative. |
| T26 | The requested journey reverses a single directional pattern. | A boarding occurrence must precede its alighting occurrence. The fixture contains no reverse service. | Correct directional rejection; another pattern would need separate evidence. |
| T30 | Boarding reaches the exclusive service-window end. | In the synthetic fixture, ready at 09:50 plus the full 10-minute headway gives 10:00, exactly when the window ends. | The conservative waiting policy cannot promise this boarding. It is not an observed last-bus departure. |
| T33, T34 | A one- or five-minute delay exhausts the last boarding window. | The baseline fits just before the cutoff; adding access delay makes the buffered boarding fall outside it. | A previously feasible proposal must be recalculated after delay. These are direct-bus window tests, not implemented transfer connections. |
| T35 | A visit is extended by 30 minutes. | The new visit duration exceeds the deadline set to the accepted plan's finish plus one second. | Rejecting acceptance preserves the baseline instead of silently shortening or dropping a visit. |
| T36 | Outbound service exists but the return does not. | The synthetic fixture provides a forward pattern; a reverse ride after the visit is absent. | One-way feasibility does not establish a feasible round trip. |
| T37, T38 | Access exceeds an explicit POC threshold. | Candidate discovery stops at 800 metres; each walking component must be at most 1,200 seconds. The 801-metre and 1,201-second inputs deliberately exceed those limits. | These are configured search/access limits, not proof that the walk is physically impossible. The 20-minute limit applies per component, not to total trip walking. |
| T39 | The usable boarding platform ranks third by distance. | Only the two nearest platforms are considered. Both are unusable in the fixture; removing them restores a valid ride via the third platform. | This is a demonstrated engine search limitation. Broader or route-aware candidate discovery is needed to avoid this false negative. |
| T42 | A mandatory visit cannot fit a one-hour trip deadline. | The request retains the mandatory venue, visit duration and complete transport requirement instead of deleting the venue to make the result appear feasible. | An itinerary conflict is correctly surfaced and cannot be accepted. |
| T44 | The request asks for zero or seven destinations. | The current request contract permits one to six destinations. | Input validation, rather than a routing failure. |
| T46 | The routing snapshot is too old or the geometry source hash differs. | The POC rejects a snapshot at the seven-day freshness boundary and geometry not tied to the routing snapshot's original ZIP. | A provenance guard prevents combining stale or mismatched evidence. The inputs were deliberately perturbed. |
| T47 | An in-flight walking operation is cancelled. | Cancellation terminates the pending native continuation. A separate fresh TJ request retains its own mode. | A successful lifecycle/cancellation guard, rather than an infeasible itinerary. UI race behavior was not newly verified by this probe. |
| T63 | Headway is zero or a frequency window runs backwards. | The authored inputs violate feed validation rules before routing begins. | Invalid-data rejection; these values were injected and are not reported as defects in the official snapshot. |
| T64 | An alighting occurrence is forged to be at or before boarding. | The proof no longer satisfies ordered stop-sequence validation. | Integrity rejection; the original valid journey remains distinct from the tampered proof. |

For interpretation, these 16 observations comprise six route/direction/service-window conflicts (T25, T26, T30, T33, T34, T36), two itinerary-deadline conflicts (T35, T42), two access-limit cases (T37, T38), one search limitation (T39), one input-validation case (T44), three provenance/data/proof rejections (T46, T63, T64) and one cancellation guard (T47).

The **680 conflicts in the 1,000-input sweep** have a separate, reproducible breakdown:

| Sweep cause | Inputs | Explanation |
| --- | ---: | --- |
| Base walking component already exceeds the cap | 500 | The authored duration is 1,201 seconds against the 1,200-second limit. |
| Added access duration crosses the cap | 100 | A 120-second base walk plus 30 minutes becomes 1,920 seconds. These rows are counted after excluding the over-limit base-duration group above. |
| Walking is within policy but the selected directed service is unavailable | 80 | Forty variations each request G00034 → G00061 or G00038 → G00058. No eligible directed ride fits those exact platform pairs under the tested service conditions. This does not evaluate an alternate destination platform or a transfer itinerary. |

These mutually exclusive groups explain all 680 results. They do not establish a 68% real-world TJ journey failure rate.

### Unsupported capabilities: 32 core cases

These cases are blocked by current application contracts or implementation scope. Additional services exist in the complete TJ source, but source presence does not make them supported by the application. The probes do not execute a broader network router and then fail to find a path.

| Cases | Count | Implementation cause | What would be required |
| --- | ---: | --- | --- |
| T05–T08, T27, T58 | 6 | The feed contract is single-route, the planner searches a direct ride, and the journey contract stores one optional `ride`. Multiple ordered rides, transfer walks/waits and exit/re-entry are not represented. | A multi-route feed and multi-ride journey model, transfer search, validated interchange access and temporal connection checks. |
| T17–T21, T49–T56 | 13 | Runtime feed validation is restricted to route `1`, category `BRT`, agency `Tije`. Other BRT corridors fail this gate even though their patterns are in the source ZIP. | Import and validate the additional corridors, then exercise their service patterns, platform identities and geometry through the runtime. |
| T09–T12 | 4 | Non-BRT and mixed BRT/non-BRT scenarios exceed the route/category gate; a mixed itinerary also needs a multi-ride representation. | Preserve each segment's actual route/category, implement non-BRT ingestion, and add interchange support for mixed journeys. |
| T13–T15 | 3 | Mikrotrans and mixed-category journeys exceed the same gate. The application does not yet integrate Mikrotrans boarding/alighting and service rules. | A category-aware adapter plus sourced stop, restriction, timing and transfer behavior. |
| T22–T24, T57 | 4 | Royaltrans B14, Transjabodetabek B51, Bus Wisata BW1 and Rusun 11C are rejected by the current route/category contract. | Explicit handling of these TJ services, their calendars, restrictions, geographic coverage and any service-specific user constraints. |
| T16, T41 | 2 | The itinerary request fixes the origin query to Bundaran HI, validates geographic bounds and requires known catalog destinations. The six citywide venue IDs are outside the Blok M catalog. | Expand sourced destinations and origin/geography contracts before claiming citywide end-to-end routing. T16's separate coordinate probe is an authored out-of-bounds point, not a routed Bekasi trip. |

**Probe precision note:** T09 and T14 mutate the requested service category while retaining route `1` from the first segment. Their resulting route/category combination is a test injection, not the published category of corridor 1. These two rejections establish the strict category gate only. They do not validate the intended mixed-service journey. Dedicated T12 and T13 probes retain actual 1B and JAK.79 identities. The captured observations are preserved; a future rerun should give each mixed-service segment its own source-matched route/category pair.

### Simulated provider failures: four core cases

All four are deliberately injected into the walking dependency. They do not show that an external provider failed during this run, and they do not measure the frequency of real outages. The expected behavior is to terminate explicitly and refuse to invent a usable duration or connection.

| Case | Injected cause | Why the engine rejects or stops | Verified behavior |
| --- | --- | --- | --- |
| T28 | The walking double returns no access result. | A bus journey requires a usable origin-to-platform walk; proximity alone cannot supply its duration. | No bus journey is returned; no fallback ETA is fabricated. |
| T45 | The native callback never completes; a separate walking fixture lacks egress. | The test overrides the native request callback and uses a five-millisecond test timeout. Separately, missing alight-to-destination walking prevents completing the journey. | The pending call terminates and records a failure; the partial journey is not accepted as complete. No live network request is made. |
| T61 | Walking durations are NaN, infinity or negative. | These values cannot support finite, nonnegative arrival-time arithmetic. | Invalid numeric evidence is rejected before producing a TJ leg. |
| T62 | The walking response contains a different endpoint coordinate. | Its proof does not correspond to the requested walking segment, even if a duration is present. | Coordinate mismatch is rejected instead of connecting the wrong locations. |

Cancellation is reported separately under T47, not counted as a provider outage. A future live-provider evaluation would need its own captured errors, retries, timeouts and network conditions; this simulation provides no evidence about those rates.

### Data and constraint gaps: two core cases, plus separate source findings

The `missing_data` label also includes an unimplemented structured constraint. It does not mean that every gap is a missing file or a defective official source.

| Case | Cause | Why it matters | Evidence needed to resolve it |
| --- | --- | --- | --- |
| T32 | The captured feed supplies weekly calendars but no `calendar_dates.txt` holiday exceptions. | The test can verify an inactive weekday, but cannot establish whether a holiday cancels, adds or modifies service. Absence of an exception table does not prove service changes occur or that the regular timetable always applies. | Dated operator confirmation or an applicable exception source, plus explicit exception handling. |
| T40 | The request has no structured wheelchair-accessibility or per-user walking-limit fields, and the integration lacks verified entrance/path accessibility. | A valid boarding coordinate and a fixed 20-minute walking policy cannot establish that an individual traveller can access the platform. This is both an interface/capability gap and an evidence gap. | Structured traveller constraints, sourced accessible entrances/interchange paths and enforcement through the planner. This observation does not claim that the complete official ZIP contains no accessibility-related fields. |

The **709 source-gap observations** belong to the separate 5,552-row source audit, not to the two core cases above:

- **694 calendar checks:** holiday exceptions are not provided or inferred, one observation per source pattern.
- **Five queries for JAK.20-R02:** its frequency record has `exact_times=1`; the frequency-only auditor deliberately does not substitute the `exact_times=0` waiting policy.
- **Ten queries for S14-R02 and S14R-R02:** all recorded stop calls prohibit pickup, so the auditor cannot form an unconditional boarding pair. This is a restriction on those two recorded patterns, not a claim that all Royaltrans services prohibit boarding.

In addition, all **14 explicit transfer records lack minimum transfer durations**. Shared boarding coordinates also do not establish walkability, paid-area access, direction, waiting time or accessibility. These transfer evidence gaps are recorded separately and are not added to the 709 pattern-audit observations. No field observation in this run resolves them.

## Capability boundary

| Capability | Observed boundary |
| --- | --- |
| Direct corridor-1 BRT outside Blok M | Runtime leg probes; catalog/UI expansion is separate. |
| Same-stop travel | Walking-only control; excluded from successful TJ ride counts. |
| BRT interchanges | Multi-route input rejected; journey contract holds one ride. |
| Non-BRT / Mikrotrans | Categories present in full source, rejected by current runtime feed gate. |
| Transjabodetabek / Royaltrans / Rusun / Bus Wisata | Source identity retained; current runtime rejects these TJ services. |
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

14 explicit transfer records; 0 provide a minimum transfer duration. calendar_dates present: False. The only agency is Tije; every motorized-service scenario in this version targets TJ.

Pickup-restricted calls: 129; drop-off-restricted calls: 66. Frequency exact_times distribution: `{'0': 746, '1': 1}`. These are concrete importer/runtime requirements for broader coverage; the corridor-1 importer cannot simply be applied unchanged.

| Candidate route from source | Published name | Category |
| --- | --- | --- |
| B51 | Cikarang - Cawang | Transjabodetabek |
| 10 | Tanjung Priok - PGC | BRT |
| 11C | Rusun Pulo Gebang - Penggilingan | Rusun |
| 13 | Ciledug - Tegal Mampang | BRT |
| 2 | Pulo Gadung - Monumen Nasional | BRT |
| 3 | Kalideres - Monumen Nasional via Veteran | BRT |
| 1 | Blok M - Kota | BRT |
| 4 | Pulo Gadung - Galunggung | BRT |
| 5 | Kampung Melayu - Ancol | BRT |
| 6 | Ragunan - Galunggung | BRT |
| 7 | Kampung Rambutan - Kampung Melayu | BRT |
| 8 | Lebak Bulus - Pasar Baru | BRT |
| 9 | Pinang Ranti - Pluit | BRT |
| 11 | Pulo Gebang - Kampung Melayu | BRT |
| 12 | Tanjung Priok - Pluit | BRT |
| 14 | Jakarta International Stadium - Senen | BRT |
| 1A | Pantai Maju - Balai Kota | Angkutan Umum Integrasi |
| 1E | Pondok Labu - Blok M | Angkutan Umum Integrasi |
| 1B | Stasiun Palmerah - Transport Hub Dukuh Atas | Angkutan Umum Integrasi |
| 6M | Stasiun Manggarai - Blok M | Angkutan Umum Integrasi |
| B14 | Bekasi Barat - Kuningan | Royaltrans |
| BW1 | Sejarah Jakarta | Bus Wisata |
| JAK.79 | Cengkareng - Tubagus Angke | Mikrotrans |
| JAK.107 | Jembatan Garden - Puri Beta | Mikrotrans |
| JAK.78A | Benda - Cengkareng Timur | Mikrotrans |

Candidate presence is data evidence only; transfer paths, entrances and travel times have not been established.

## TJ network source stress audits

5552 source observations cover all 694 trip patterns across 241 TJ routes.

Eight probes per pattern: call integrity; pickup/drop-off restrictions; weekly calendar/holiday gap; before-opening query; 09:00; 17:00 plus 30-minute access; 00:01 on the next day; and the final frequency-window boundary.

| Source audit outcome | Count |
| --- | ---: |
| source_available | 2380 |
| source_gap | 709 |
| source_unavailable | 1075 |
| source_valid | 1388 |

| TJ source category | Routes | Patterns |
| --- | ---: | ---: |
| Angkutan Umum Integrasi | 64 | 166 |
| BRT | 31 | 162 |
| Bus Wisata | 3 | 5 |
| Mikrotrans | 98 | 227 |
| Royaltrans | 13 | 26 |
| Rusun | 14 | 28 |
| Transjabodetabek | 18 | 80 |

3264 shared boarding-coordinate candidates were found. 14 explicit transfer records were inspected. Neither shared coordinates nor these records establish a safe transfer or a feasible connection.

These are source-only audits with a conservative full-headway assumption. They do not generate application journeys, model door-to-door walks or run a transfer router. Exact-times service and absent holiday exceptions stay explicit gaps. Source observations are stored separately in network-audit.json.

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
| T09 | BRT to feeder: Bundaran HI → Pondok Labu | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 1, category Angkutan Umum Integrasi. No journey generated for Bundaran HI -> Pondok Labu; full-feed audits check the actual source pattern separately. |
| T10 | Feeder to BRT: Pondok Labu → Kota | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 1E, category Angkutan Umum Integrasi. No journey generated for Pondok Labu -> Kota; full-feed audits check the actual source pattern separately. |
| T11 | Feeder BRT feeder: Palmerah → Pantai Maju | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 1B, category Angkutan Umum Integrasi. No journey generated for Palmerah -> Pantai Maju; full-feed audits check the actual source pattern separately. |
| T12 | Direct non-BRT: Palmerah → Transport Hub Dukuh Atas | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 1B, category Angkutan Umum Integrasi. No journey generated for Palmerah -> Transport Hub Dukuh Atas; full-feed audits check the actual source pattern separately. |
| T13 | Mikrotrans to BRT: Cengkareng via JAK.79 → Kota | unsupported_capability / routing | Runtime feed gate rejected actual TJ route JAK.79, category Mikrotrans. No journey generated for Cengkareng via JAK.79 -> Kota; full-feed audits check the actual source pattern separately. |
| T14 | BRT to Mikrotrans: Kota → Tubagus Angke via JAK.79 | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 1, category Mikrotrans. No journey generated for Kota -> Tubagus Angke via JAK.79; full-feed audits check the actual source pattern separately. |
| T15 | Three service categories: Jembatan Garden via JAK.107 → Ragunan | unsupported_capability / routing | Runtime feed gate rejected actual TJ route JAK.107, category Mikrotrans. No journey generated for Jembatan Garden via JAK.107 -> Ragunan; full-feed audits check the actual source pattern separately. |
| T16 | Beyond supported geography: Bekasi → Jakarta destination | unsupported_capability / input | Input gate rejects an alternate Bekasi origin; a separate out-of-bounds coordinate probe is rejected too. No Bekasi route evaluated. |
| T17 | BRT corridor 2: Pulo Gadung → Monumen Nasional | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 2, category BRT. No journey generated for Pulo Gadung -> Monumen Nasional; full-feed audits check the actual source pattern separately. |
| T18 | BRT corridor 3: Kalideres → Monumen Nasional | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 3, category BRT. No journey generated for Kalideres -> Monumen Nasional; full-feed audits check the actual source pattern separately. |
| T19 | Cross-city corridor 9: Pinang Ranti → Pluit | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 9, category BRT. No journey generated for Pinang Ranti -> Pluit; full-feed audits check the actual source pattern separately. |
| T20 | Elevated corridor 13: Ciledug → Tegal Mampang | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 13, category BRT. No journey generated for Ciledug -> Tegal Mampang; full-feed audits check the actual source pattern separately. |
| T21 | BRT corridor 14: Jakarta International Stadium → Senen | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 14, category BRT. No journey generated for Jakarta International Stadium -> Senen; full-feed audits check the actual source pattern separately. |
| T22 | Royaltrans cross-boundary service: Bekasi Barat → Kuningan | unsupported_capability / routing | Runtime feed gate rejected actual TJ route B14, category Royaltrans. No journey generated for Bekasi Barat -> Kuningan; full-feed audits check the actual source pattern separately. |
| T23 | Transjabodetabek with restricted calls: Cikarang → Cawang | unsupported_capability / routing | Runtime feed gate rejected actual TJ route B51, category Transjabodetabek. No journey generated for Cikarang -> Cawang; full-feed audits check the actual source pattern separately. |
| T24 | Tourist loop service: Sejarah Jakarta loop → Sejarah Jakarta loop | unsupported_capability / routing | Runtime feed gate rejected actual TJ route BW1, category Bus Wisata. No journey generated for Sejarah Jakarta loop -> Sejarah Jakarta loop; full-feed audits check the actual source pattern separately. |
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
| T43 | Personalized TJ coffee and Wi-Fi: Bundaran HI → Eligible coffee venue | supported_feasible / itinerary | TJ recommends sourced coffee/Wi-Fi bm08; complete TJ plan preserves profile and venue. Synthetic Blok M end-to-end control. |
| T44 | Invalid stop counts: Origin → Zero or seven venues | supported_conflict / input | Zero and seven requested destinations rejected explicitly. |
| T45 | Timeout and partial walking: Origin → Destination | provider_failure / provider | Native callback timeout injected without network; separate partial walking fixture prevents egress. |
| T46 | Stale feed and geometry mismatch: Origin → Destination | supported_conflict / data | Seven-day freshness boundary and geometry source-hash mismatch both rejected. |
| T47 | Cancel and restart TJ work: Origin → Destination | supported_conflict / routing | Cancellation terminates an in-flight native walking continuation; a fresh TJ request retains TJ mode. UI race regression is tracked separately, not claimed here. |
| T48 | Save reopen export reject: Bundaran HI → Accepted itinerary | supported_feasible / storage | Save/reopen/export preserves accepted UUID and audited bus proof after a conflicting revision is rejected. |
| T49 | BRT corridor 4: Pulo Gadung → Galunggung | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 4, category BRT. No journey generated for Pulo Gadung -> Galunggung; full-feed audits check the actual source pattern separately. |
| T50 | BRT corridor 5: Kampung Melayu → Ancol | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 5, category BRT. No journey generated for Kampung Melayu -> Ancol; full-feed audits check the actual source pattern separately. |
| T51 | BRT corridor 6: Ragunan → Galunggung | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 6, category BRT. No journey generated for Ragunan -> Galunggung; full-feed audits check the actual source pattern separately. |
| T52 | BRT corridor 7: Kampung Rambutan → Kampung Melayu | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 7, category BRT. No journey generated for Kampung Rambutan -> Kampung Melayu; full-feed audits check the actual source pattern separately. |
| T53 | BRT corridor 8: Lebak Bulus → Pasar Baru | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 8, category BRT. No journey generated for Lebak Bulus -> Pasar Baru; full-feed audits check the actual source pattern separately. |
| T54 | BRT corridor 10: Tanjung Priok → PGC | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 10, category BRT. No journey generated for Tanjung Priok -> PGC; full-feed audits check the actual source pattern separately. |
| T55 | BRT corridor 11: Pulo Gebang → Kampung Melayu | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 11, category BRT. No journey generated for Pulo Gebang -> Kampung Melayu; full-feed audits check the actual source pattern separately. |
| T56 | BRT corridor 12: Tanjung Priok → Pluit | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 12, category BRT. No journey generated for Tanjung Priok -> Pluit; full-feed audits check the actual source pattern separately. |
| T57 | Rusun feeder: Rusun Pulo Gebang → Penggilingan | unsupported_capability / routing | Runtime feed gate rejected actual TJ route 11C, category Rusun. No journey generated for Rusun Pulo Gebang -> Penggilingan; full-feed audits check the actual source pattern separately. |
| T58 | Three TJ interchanges: Kampung Rambutan → Pluit via several TJ services | unsupported_capability / routing | Runtime contract gate: multi-route feed rejected; journey serializes one ride only. No transfer itinerary generated for Kampung Rambutan -> Pluit via several TJ services. |
| T59 | Missed short window then later bus: Corridor origin → Corridor destination | supported_feasible / routing | Synthetic short 09:00-09:05 window cannot fit a full headway; the next valid window boards at 10:10 and retains the long wait. |
| T60 | Six visits with varied durations: Bundaran HI → Six selected Blok M venues | supported_feasible / itinerary | Complete TJ replay preserves six selected Blok M venues and distinct 15/30/45/60/75/90-minute stays. This is a catalog-limited itinerary control, not a citywide network route. |
| T61 | Invalid provider durations: TJ access origin → TJ boarding coordinate | provider_failure / provider | NaN, infinity and negative walking durations are explicitly rejected; no fabricated TJ leg. |
| T62 | Wrong walking coordinates: TJ access origin → TJ boarding coordinate | provider_failure / provider | Walking response with mismatched endpoint coordinates is rejected before calculating a bus journey. |
| T63 | Invalid headway and frequency window: TJ boarding coordinate → TJ alighting coordinate | supported_conflict / data | Zero headway and reversed frequency window rejected without running a route. |
| T64 | Forged ordered bus proof: TJ boarding coordinate → TJ alighting coordinate | supported_conflict / data | A forged alighting occurrence before/equal to boarding cannot pass journey validation. |

## Deterministic stress sweep

10 directed coordinate pairs × 10 departure hours × 5 access delays (0/1/5/15/30 minutes) × 2 base walking durations (120/1,201 seconds). A new planner and provider are created for every row. Access delay is added to the access walking component, so it can cross the existing 20-minute component cap. This does not simulate transfer delays, traffic, or actual bus reliability.

| Sweep measure | Result |
| --- | ---: |
| Feasible bus legs | 320 |
| Access/service conflicts | 680 |
| Defects | 0 |
| Calculation p50 / p95, milliseconds | 2.624 / 3.137 |
| Maximum synthetic walking calls per variation | 4 |
| Total synthetic walking calls | 2680 |
| Longest feasible fixture trip, seconds | 7253 |

Calculation timings measure this local deterministic harness, not live Maps latency or travel-time accuracy. Request counts refer to synthetic walking calls, including rejected candidate attempts; they are not live network requests.

## Next work, ordered by blocking dependency

1. Expand the sourced venue catalog and origin contract for citywide end-to-end inputs.
2. Introduce a multi-route feed and ordered multi-ride journey contract with transfer walk/wait evidence; retain service categories.
3. Validate BRT/non-BRT/Mikrotrans interchange access and timing. Full-feed coverage alone does not prove connections.
4. Add explicit service calendars, boarding restrictions, scheduled-service interpretation and supported geographic bounds for the remaining TJ categories.
5. Expose supported constraints and detailed interchange steps in UI; run bounded live checks and field observations.

## Reproducibility and limits

Raw results, Swift log, source hashes and pinned-feed inspection are kept in this fresh ignored run directory. The historical snapshot clock is fixed; no source dates are advanced to bypass freshness. Previous app/device runs are not inherited as evidence for this suite. No live providers, credentials, paid APIs, production changes, commits, or deployments are used.

## Scope revision and verification

Version 2 follows the user's revised TJ-only request. It replaces the eight non-TJ core cases with additional TJ corridors and services, removes cross-operator comparisons from the active suite and expands to 64 cases. The v1 manifest and [earlier report](CAPABILITY-REPORT-2026-11-06.md) remain unchanged for provenance. Identical Txx IDs across versions must be interpreted with their manifest ID/hash.

The active manifest is `tj-only-capability-2026-11-06-v2`. Every active scenario declares only agency Tije. The source ZIP SHA256 remains the original attributed capture; no historical date was advanced and no new feed was downloaded.

### Concrete source gaps discovered

- **JAK.20-R02, Mikrotrans:** the published frequency record has `exact_times=1`. Its five window queries remain gaps in this frequency-only source diagnostic; they are not approximated as `exact_times=0` service.
- **S14-R02 and S14R-R02, Royaltrans:** every published stop call prohibits pickup (`pickup_type=1`). No unconditional boarding pair is invented. These account for ten query gaps and require source/operator clarification before promising a passenger boarding journey on those patterns.
- **Holiday exceptions:** the ZIP has no `calendar_dates.txt`. All 694 pattern calendar checks explicitly retain this uncertainty. Together with the 15 window-query gaps above, this explains all 709 source-gap observations.
- **Transfers:** the 14 explicit transfer records lack minimum durations. Shared boarding-stop candidates also require separate access, direction, paid-area and timing evidence.

Source-unavailable counts are outcomes under the diagnostic's calendar and conservative waiting assumption. A short published window can fail to fit one full headway even when a bus might run. Neither the 1,075 unavailable nor the 2,380 available source observations is a real-world transit success rate or an application routing result.

| Verification layer | Result |
| --- | --- |
| Active TJ core scenarios | 64/64 matched their expected capability/conflict/provider result. |
| Engine stress inputs | 1,000/1,000 processed with no invariant defects; 320 feasible bus legs and 680 expected access/service conflicts. |
| Full-source pattern audits | 5,552 observations across 241 TJ routes and 694 patterns; zero ordered-call/source-parse invariant failures. |
| Python script regressions | 34 tests passed, including TJ-only scope guards and source-time/restriction/calendar tests. |
| TripIntelligence package | 57 XCTest test functions passed. |
| PreferenceLearning package | 29 XCTest test functions passed. |
| VisitTiming package | 59 Swift Testing test functions passed. |
| PreferenceQuality package | 40 Swift Testing test functions passed. |
| TripIntegration package | 65 Swift Testing test functions passed. |
| Total package regressions | 250 test functions passed. The 64 parameterized core cases and 1,000 sweep inputs are executed within two of these functions, not counted as 1,064 separate functions. |

Raw reviewed evidence is in ignored `.verification/tj-only-capabilities-20261106-reviewed/`; package logs are in `.verification/tj-only-capabilities-20261106-packages/`. The initial TJ-only run remains in its own directory. Read the [current protocol](CAPABILITY-TESTS.md) for commands and evidence boundaries.

The ten feasible core observations comprise three unchanged-snapshot direct bus leg probes, one walking-only control, three synthetic service-window probes and three replay itinerary/persistence controls. The six-venue case preserves distinct stays of 15/30/45/60/75/90 minutes. The 32 unsupported observations identify actual runtime contract gates; they do not demonstrate successful application routing on those additional services.

This revision changes tests, evaluator tooling and documentation. The application router still handles direct corridor 1 plus walking. No application UI, public transport contract, production code, live-provider behavior, commit, push or deployment is changed or claimed.
