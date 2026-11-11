# Final TJ itinerary POC test report

Report date 6 November 2026. Final routing evaluation completed at 17:54 WIB.

## Final assessment

The tested implementation generated feasible bus journeys for **497 of 501 diagnostic inputs**. Four inputs returned no feasible journey. The completed outputs passed the journey validators and the additional timing, walking-limit and endpoint assertions used by the evaluation.

The final POC supports route-aware platform discovery, direct TJ service, a one-transfer fallback, sourced destination selection, configurable live origin, visit-time budgeting, proposal acceptance, persistence and export. The recorded evaluation uses a fixed GTFS snapshot and synthetic walking. Its feasibility rate describes the selected diagnostic inputs.

## Tested configuration

| Item | Final configuration |
| --- | --- |
| Transport operator | TransJakarta, agency Tije |
| Runtime coverage | 199 routes, 544 trip patterns and 6,773 stop records inside the application's Jakarta boundary |
| Departure date for routing diagnostics | Saturday, 7 November 2026 |
| Network endpoint query time | 09:00 WIB |
| Other diagnostic departure hours | 00, 01, 05, 06, 08, 09, 12, 17, 22 and 23 WIB |
| Platform access radius | 800 metres |
| Walking limit | 20 minutes per component |
| Local itinerary policy | Prioritize provider-verified walking up to 15 minutes |
| Transfer policy | Search up to one transfer when direct service fails |
| Boarding wait | One full published headway per boarding |
| Interchange buffer | Additional two minutes, alongside transfer walking and the next boarding wait |
| Search budget | Up to 64 candidate paths per direct/transfer stage and 128 walking lookups per calculation |
| Transient walking retry | At most one additional attempt under request pacing and provider limits |
| Destination catalogs | Sourced Blok M and Jakarta catalogs |
| UI runtime | iPhone 17e Simulator with iOS 26.4.1 |

The one-transfer limit, two-minute buffer and local-walking priority are POC policy defaults. Their practical suitability requires live and field measurements.

## Routing results

| Diagnostic group | Inputs | Feasible | No feasible result | Feasibility within group |
| --- | ---: | ---: | ---: | ---: |
| Usable platform surrounded by closer unusable platforms | 200 | 200 | 0 | 100% |
| Nearby alternatives around destination platforms | 100 | 100 | 0 | 100% |
| Endpoint pairs selected from the imported network routes | 199 | 195 | 4 | 98.0% |
| Two-corridor BRT connections | 2 | 2 | 0 | 100% |
| **Total** | **501** | **497** | **4** | **99.2%** |

The first group varies the number of closer unusable platforms from zero to nineteen across ten departure hours. The second group exercises ten endpoint pairs across the same ten hours. These are deterministic, correlated scenarios.

The network group selects one published pattern and usable endpoint pair per imported route. The planner may choose another service that reaches the destination. Feasibility in this group establishes an endpoint result under the test assumptions. The raw result records the actual chosen route IDs and service categories for each input.

### Verified BRT connections

The connection tests restrict the attributed source to the two named corridors and require a result containing two bus rides.

| Connection | Result | Ride count | Estimated total duration | Synthetic walking lookups |
| --- | --- | ---: | ---: | ---: |
| Corridor 2 → corridor 1 | Feasible | 2 | 123 minutes 30 seconds | 7 |
| Corridor 3 → corridor 1 | Feasible | 2 | 135 minutes 14 seconds | 11 |

Total duration includes access walking, boarding waits, bus travel, transfer walking, the interchange buffer and egress walking. Candidate enumeration reached its configured cap for the corridor 3 → 1 test.

## Four unresolved endpoint inputs

| Requested source route | Weekly-calendar finding | Walking lookups | Alternative search |
| --- | --- | ---: | --- |
| 1T | All imported patterns for this route are inactive on the tested Saturday. | 15 | Candidate cap reached |
| 6P | All imported patterns for this route are inactive on the tested Saturday. | 2 | Candidate cap reached |
| 7R | All imported patterns for this route are inactive on the tested Saturday. | 1 | Candidate cap reached |
| 7U | All imported patterns for this route are inactive on the tested Saturday. | 2 | Candidate cap reached |

The route-calendar findings explain why the requested services cannot supply the tested Saturday departure. Bounded alternative search also returned no complete journey. Further exploration would be required to determine whether a different service combination, departure time or access point could serve those destinations.

## TJ category coverage

| TJ service category | Imported patterns | Selected by at least one feasible routing diagnostic |
| --- | ---: | --- |
| BRT | 143 | Yes |
| Angkutan Umum Integrasi | 157 | Yes |
| Mikrotrans | 201 | Yes |
| Rusun | 28 | Yes |
| Royaltrans | 6 | Source imported, successful service selection not demonstrated by these diagnostics |
| Bus Wisata | 5 | Source imported, successful service selection not demonstrated by these diagnostics |
| Transjabodetabek | 4 | Source imported, successful service selection not demonstrated by these diagnostics |

Runtime import preserves complete patterns inside the geographic boundary and enforces pickup/drop-off permissions. Patterns crossing the boundary and scheduled exact-times service require additional coverage or timetable handling. Transfer candidates originate from identical boarding stops, shared parent stations or explicit recommended GTFS links. Each computed connection requires a walking result.

## Itinerary and application behavior

| Capability | Verified outcome |
| --- | --- |
| Platform discovery | Reaches a usable platform even when closer candidates have no eligible ordered ride. |
| Service identity | Retains route, category, direction, boarding and alighting occurrences in journey evidence. |
| Transfer timing | Accounts for both rides, transfer walking, the interchange buffer and a boarding wait for each bus. |
| Connection validation | Rejects missing transfer edges, prohibited pickup, missed onward service windows and forged onward timing. |
| City itinerary | Completes an audited TJ itinerary using the Jakarta catalog, Cikini as the custom origin and Erasmus Huis as the selected destination on a sourced opening day. |
| Early time budget | Identifies total visit duration exceeding the available trip window before location requests. |
| User corrections | Provides actions to add one hour within the same day or reduce visit durations by 15 minutes, retaining chosen venues for recalculation. |
| Provider resilience | Exercises transient retry, cancellation and invalid provider evidence through injected responses. |
| Acceptance and persistence | A transfer itinerary passes final audit, acceptance, save, reload and Markdown/JSON export. |
| Showcase UI | Exercises catalog selection, time-budget actions, draft persistence, guided creation, journey review, acceptance and export. |

Provider resilience results come from controlled injected responses. Live network recovery rates and real provider latency require separate measurement.

## Calculation cost

| Diagnostic group | Median calculation time per input | p95 calculation time | Synthetic walking lookups across group |
| --- | ---: | ---: | ---: |
| Platform discovery | 0.272 ms | 0.597 ms | 400 |
| Nearby destination alternatives | 1.169 ms | 1.814 ms | 660 |
| Network endpoint pairs | 15.075 ms | 69.860 ms | 2,616 |
| Two-corridor connections | 3.291 ms | 3.485 ms | 18 |

The 501 inputs used **3,694 synthetic walking lookups** in total. The maximum observed per input was **34**. Candidate enumeration reached its cap on **146 inputs**, including feasible outputs. Those outputs retain the search-bound limitation.

Timing covers the measured per-leg calculation. Planner initialization, source decoding/validation and network I/O are excluded. Real walking-provider requests, rate limiting, weather, search and complete itinerary generation add work to the application flow.

## Final implementation verification

The following checks executed against the final implementation.

| Verification layer | Result |
| --- | --- |
| Shared Swift packages | 256 test functions passed across five packages |
| Python evaluator/importer scripts | 39 tests passed |
| Journey Showcase Simulator | 15 tests passed |
| Trip Integration TJ review and acceptance UI | 1 test passed |
| Native POC Simulator builds | All four applications built successfully |

The test-function counts are verification totals. The 501 diagnostic inputs execute inside the routing evaluation and have their own result counts above.

## Acceptance limits

- Walking, coordinates used by replay adapters and replay weather are synthetic. Field access, traffic, actual waiting and bus arrival accuracy remain unmeasured in this evaluation.
- The router handles a direct service or one transfer. A feasible direct result is preferred before exploring transfer alternatives.
- Geographic coverage follows the current Jakarta boundary. Broader service coverage requires additional source and boundary handling.
- Exact-times schedules, holiday exceptions and verified accessibility constraints remain open.
- Transfer candidates and a successful walking estimate still require field verification of entrances, crossings, paid areas and platform access.
- Transfer behavior is verified through the shared itinerary pipeline, audit, storage and export. Dedicated gesture verification of a transfer itinerary in the UI remains pending.
- Actual Dark appearance and manual accessibility acceptance remain pending.

## Source and evidence

The attributed runtime snapshot was checked on 6 November 2026 at 14:01:50 WIB. Its upstream Last-Modified value is 30 October 2026 at 09:51:57 UTC. The captured ZIP SHA256 is `376b11f72ac30f9f4eb972ae32c7f1a3251b416dc3cd77cc573475a3b2676b9c`.

The publisher is PT Transportasi Jakarta. The snapshot retains CC BY 4.0 attribution. [Official GTFS](https://gtfs.transjakarta.co.id/files/file_gtfs.zip) · [Publisher attribution](https://ppid.transjakarta.co.id/informasi/berkala) · [License](https://creativecommons.org/licenses/by/4.0/)

Final runtime observations and source hashes are retained under ignored `poc-journey/.verification/tj-improvements-20261106-verified/`. This report uses the final-result fields in `summary.json` and `paired-results.json`. UI evidence is in `ShowcaseCorrected.xcresult` and `TripIntegrationTJ.xcresult` under `.verification/tj-improvements-20261106-ui/`. Build logs are under `.verification/tj-improvements-20261106-builds/`.
