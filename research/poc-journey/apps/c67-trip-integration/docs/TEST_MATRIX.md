# Priority 3 test protocol and execution status

The execution gate opened after Giovan explicitly confirmed WeatherKit activation. Final state: **35 package tests and 2 Simulator UI tests passed; 7/7 scripted iPhone live cases passed**. See [the dated report](VERIFICATION_REPORT_2026-11-05.md) for evidence and remaining gaps. The pretest handoff is archived separately.

## What is real and what is authored

The opening schedules, Friday entry pause, GBK session break, regular Monday closures and MACAN notice come from dated public sources inherited from P1/P2. Baca Di Tebet and Erasmus Huis additions use official pages. They are published facts, not observations of admission or capacity. Venue exceptions/holidays remain unknown. See `VENDOR.md` and the resource JSON for exact URLs and check timestamps.

Replay coordinates, 20-minute legs, rain probabilities, service failures, timeouts and corrupt files are **authored engineering fixtures**. They are not current traffic or forecast observations. The fixed evaluation clock is 5 Nov 2026 14:00 WIB; normal replay trip is Friday 6 Nov 2026. Old source dates never move automatically. A live test later than the seven-day fact policy must recheck sources and create a new dated catalog, preserving this one.

## Automated cases prepared

All **35 package tests and 2 UI tests passed** on the final verification. The two new identity cases below came from actual MapKit output, after the original 33-case run. [Executed inventory](test-inventory.json) maps function names to logs.

| ID | Case / trigger | Expected observation | Evidence type |
| --- | --- | --- | --- |
| C01 | Cikini Friday arrival 11:30 WIB, 60m stay | Earliest entry 13:00; arrival 11:15 may enter and stay through the entry pause | Published regular rule + authored arrival |
| C02 | GBK Friday arrival 09:45, 60m stay | Cannot finish before 10:00; next valid start 15:00 | Published two-session rule + authored arrival |
| C03 | Monday GBK, Ragunan, BDT, Erasmus; Dia.Lo.Gue missing hours | Closed destinations have no valid starts; missing remains unknown | Published schedules / absent evidence |
| C04 | MACAN suspension; sources >7 days old | No scheduled window; requires source recheck | Published notice + clock manipulation |
| C05 | Deadline next day; two BDT areas | Request rejected, original choices remain available for correction | Contract fault |
| C06 | 7 requested proposals, 61-minute dwell, must and avoid coffee | Each invalid input rejected | Contract fault |
| C07 | UTC 18:00 maps to next WIB day; arrival 09:00:01 | Correct WIB date, round forward to 09:15 | Timezone/boundary |
| C08 | Invalidate request epoch while old result is pending | Old epoch cannot publish | Concurrency contract |
| E01 | Duplicate MapKit pins plus Bandung result | Collapse duplicate; exclude outside Jakarta polygon | Authored search responses |
| E02 | Two plausible Cikini matches | No automatic selection; explicit supplied pin accepted; invented ID rejected | Authored ambiguous search |
| E03 | Nyi Ageng Serang returned for Cikini query | Different branch cannot inherit Cikini facts or enter selectable matches | Authored realistic branch mix-up |
| E04 | Visit crosses two forecast hours | Use both intervals; maximum 90%; missing second hour => unknown | Authored hourly weather |
| E05 | Duplicate hour or probability 1.2 | Reject corrupt interval; never replace missing with 0% | Provider fault |
| E06 | Points 1 km and >3 km from representative | Every group member is within 3 km of its representative | Authored coordinates |
| E07 | Actual English name Jakarta Provincial Library, Cikini address | Cikini-specific alias accepted | Live-derived regression |
| E08 | Same English name, Nyi Ageng Serang address | Cikini facts cannot transfer to that branch | Live-derived negative regression |
| P01 | Required Cikini + BDT replay, 20m legs | All selected places retained; 3 legs, 60m total travel, sourced entry rules respected; synthetic label | Complete replay |
| P02 | Empty optional profile | General label; unique venues; only schedulable recommendations | Integrated cold start |
| P03 | Require Wi-Fi at Cikini with no supporting claim | Required destination retained for correction; cannot borrow BDT evidence | Integrated hard-preference gate |
| P04 | Append invented source ID to a result | Final audit rejects | Corrupt output |
| P05 | Cikini stay +30m, same input otherwise | Leave/return +30m in the one-stop fixture; original bytes unchanged | Revision replay |
| P06 | Cikini 09:00 departure, return deadline 10:45, fixed20m legs | Earliest return 10:50; conflict, cannot accept, destination retained | Real rule + authored travel |
| P07 | Required Dia.Lo.Gue without sourced hours | Visible required/unselectable; cannot schedule it or substitute another place | Integrated missing facts |
| P08 | English negation not structurally confirmed; remove mandatory place | Review required; prepare fails | Intent and set invariants |
| P09 | Every ETA unavailable | Conflict; ETA stays nil; all requested IDs remain in preparation | Provider outage |
| P10 | Cancel while actually suspended inside ETA work | Cancellation propagated, no successful result | Fault injection |
| P11 | Change revision; inject a pin not in results | Reject before routing | Stale/tampered preparation |
| P12 | Accept, reapply stale base, reject; age >15m | Fresh valid version can apply; stale version/age cannot; rejection keeps accepted version | Session state |
| P13 | Save/load, corrupt primary after a backup, export | Restore valid prior version, retain corrupt file, export compatible native report and evidence label | Storage/recovery |
| W01 | Same covered window; expanded deadline; age901s since latest fetch | Reuse only first matching fresh window; refetch expanded/expired windows | Counting fake provider |
| W02 | Open-Meteo cache followed by primary-only request | Must fetch WeatherKit; fallback is not primary evidence | Provider policy |
| W03 | Slow cooperative provider, 5ms injected timeout | Unknown result, empty hours, timeout error | Timeout injection |
| W04 | WeatherKit authorization failure, two groups | One primary request in operation; both unknown, failure not cached | Auth fault injection |
| W05 | Weather transport fails for every group | Route may remain feasible; visit weather unknown and diagnostics explicit | Integrated outage |
| W06 | Corrupt primary without backup | Throw; preserve file, do not reset to an empty session | Storage fault |
| U01 | Debug replay: recommend → choose → resolve → route → review → accept | Correct labels, visible timeline and saved version | Simulator UI, synthetic only |
| U02 | Replay enters weather diagnosis screen | Live diagnosis button disabled | UI boundary |

## Live matrix after confirmation

Record exact device/OS, app revision, catalog timestamps, cold/warm state, request input and outputs. Never fill ETA, weather or timing numbers in advance. Use the nearest supported future date satisfying the published weekday; record that date as a **new live run**, not a rewritten fixture. Confirm ticket/holiday/temporary-closure uncertainties remain visible.

| ID | Real flow | Critical evidence / acceptance |
| --- | --- | --- |
| L01 | Signed iPhone WeatherKit diagnosis, fallback disabled | Actual `weatherkit` hourly data, metadata and legal attribution/Apple mark; permission error means **failure**, not success via fallback |
| L02 | Empty profile, automatic unique venue proposals | General label, 1–6 places, current MapKit name/branch/polygon, no fabricated preferences |
| L03 | Reading + coffee **must** in the same area | BDT RBBJ can qualify only with its own claims; silent room/café cannot combine unrelated facts; choice and room-booking uncertainty visible |
| L04 | Nature/outdoor with GBK + Ragunan, daylight/lower-rain advice | Exact scheduled interval, full-stay/session compliance, solar/forecast provenance; advice not met in route must remain explicit |
| L05 | E5 on versus category-only with identical nonempty soft profile | Same hard gates, source IDs and required set; record ranking differences, model metadata, cold/warm latency and corrections. E5 unavailability must be labeled fallback |
| L06 | At least three selected places; accept baseline, change one dwell +30m | New revision, all selected IDs retained, provider-validated remaining timeline and return time, weather interval recomputed or explicitly unknown; original accepted version retained until apply |
| L07 | Deadline deliberately too short | Visible conflict and accept disabled; no hidden dropped destinations or placeholder ETA |
| L08 | Network unavailable, then restored | Preserve accepted result; actionable error/unknown state; cancellation and manual retry recover; no fabricated recommendation or 0% rain |
| L09 | Change input or cancel while searching/routing; leave/reopen result | Old result cannot overwrite current input/accepted plan; completed accepted result survives navigation and relaunch |
| L10 | Export actual run and read compatible native report | JSON/Markdown/provider log agree with UI, numbers, provider attribution, IDs, date/timezone, stage duration and request counts |

## Acceptance and interpretation

- **Critical correctness:** no silent dropped/added mandatory place, no borrowed branch/area fact, no invented ETA/weather/price/hour, no visit outside sourced full-stay/entry ranges, no accepted infeasible or stale proposal, no old planner write. Any violation blocks integration acceptance.
- **Live service evidence:** real signed-device WeatherKit and MapKit evidence must succeed separately. Replay, compile success, prior Weather Lab results and Open-Meteo fallback cannot satisfy L01.
- **Resource accounting:** <=7 searches per attempt, <=512 ETA requests per route run, groups within3km and cache policy traceable. Latency, memory and correction counts must be measured; no claimed performance threshold has been demonstrated.
- **Scope:** this is a pre-trip integration. Recommendation catalog coverage, holiday exceptions, all soft-time goals jointly optimized, active-trip tracking and observed user benefit remain open. Participants are not asked to travel until technical correctness is established.

Use outcome labels **pass / fail / blocked by external setup / not tested** per case, with artifact links. Final automated outcomes are passed. Live L01–L07 passed as scripted native-device cases. L08 was covered by injected faults, not by disconnecting the physical network. L09 has package cancellation/version evidence and Simulator happy-path coverage; manual physical background/input-change interaction remains untested. L10 has real-device export and cross-file audit evidence; every live UI detail has not been manually inspected. This is not a claim that all ten live scenarios or user benefit have been proven.
