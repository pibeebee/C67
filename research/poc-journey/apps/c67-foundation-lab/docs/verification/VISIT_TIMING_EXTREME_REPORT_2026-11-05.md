# Visit Timing — extreme regression and invariant checks

Date: **5 November 2026, WIB**. App configuration **v0.5.1, build 8**; calculation policy **visit-time-v2**, storage schema remains 1.

**Result:** 31 additional Swift Testing functions bring VisitTiming from 28 to **59/59 passing**. Several functions are parameterized. The expanded suite exposed correctness gaps; fixes are included rather than leaving failing tests or marking them as known issues.

The first red run executed 48 functions and recorded **41 assertion issues across 14 failing functions**. A subsequent numeric-clock check recorded two additional failures. These are assertion/case counts, **not 43 distinct bugs**. [Initial red log](visit-timing-extreme-2026-11-05/red.log), [numeric-clock red log](visit-timing-extreme-2026-11-05/red-timestamps.log), [first fixes](visit-timing-extreme-2026-11-05/green-first.log), [final runner](visit-timing-extreme-2026-11-05/runner-tests.log).

## Test provenance

- The eleven venues, four official sources and acquired GBK/Ragunan forecast fixtures from the original experiment are **unchanged**, including source dates. No old date was shifted to keep a fixture looking current.
- The rule matrix uses actual published schedules with fixed scenario dates, 6–12 November 2026. The evaluation clock is explicitly frozen after the original source retrieval.
- Corrupt schemas, impossible numbers, duplicate hours, modified notices/links and concurrent saves are labeled **engineering fault injections**. They do not claim that the venue/provider actually produced these failures.
- The suite tests application behavior against the supplied publication/snapshot. It does not verify on-site admission, weather accuracy, crowds, or user benefit.

## Coverage and corrections

| Area | Extreme case and resulting behavior |
| --- | --- |
| Date grammar and past time | Alternate spellings such as 2026-11-+5 could pass date parsing while bypassing the canonical today comparison. Dates now require ASCII yyyy-MM-dd. A plan from yesterday cannot regain slots after midnight. A one-millisecond advance past a start removes that start. Gregorian leap/year boundaries are checked. |
| Numeric/date bounds | Invalid durations and availability include Int.min/Int.max. NaN/infinite clocks and finite numbers outside supported four-digit timestamp representation are rejected. Corrupt epoch-millisecond/extreme forecast timestamps are removed from usable hourly context. |
| Provenance and contradictions | Evidence must be included in the venue's own source references, not merely exist elsewhere in the catalog. Known exposure requires a source; a suspension requires a source and meaningful notice. Blank identities, invalid URLs, a closed day with admission rules and foreign venue time zones are rejected for this Jakarta catalog. |
| Session ordering | Reversing otherwise valid service sessions no longer changes the allowed-start ranges or options. Published service gaps remain gaps. |
| Forecast envelope | Wrong venue/date, coordinates outside the operational Jakarta box, inconsistent fetch/expiry order and expired data cannot appear as current context, including early-return cases such as closed/suspended venues. The application lifetime is capped at 15 minutes. The coordinate box is a coarse gate, not proof of an exact venue pin. |
| Partial and ambiguous context | Duplicate/overlapping hourly intervals cannot silently choose the first conflicting value. Missing middle hours are not interpolated as dry. Invalid rain/temperature values become unknown. Contradictory solar data disables solar comparisons while independent usable hourly data remains available; bad rain does not erase valid solar data. Outputs remain JSON-serializable. |
| Ranking priority | A weighted rain-plus-clock score could prefer an earlier slot despite a slightly higher rain probability. Rain is now compared first, with clock time only breaking ties. The near-sunset preference remains the previously declared application heuristic. |
| History and identity | Valid JSON alone no longer establishes a valid run. Unknown schema/policy, mismatched references and impossible options are excluded from readable history while their files remain. Versions v1 and v2 are structurally supported without re-ranking old records. Repeating the same save is idempotent; different data with an existing run ID cannot overwrite the earlier experiment or export. |

The no-window UI label was generalized to cover past dates as well as insufficient visit duration. No new product screen, provider or ranking experiment for priority 2 was introduced.

## Bounded stress and invariants

| Check | Observed result |
| --- | --- |
| Full published-rule domain | **1,155 combinations**: 11 venues × 7 dates × 5 durations × 3 availability ranges. Valid start ranges were compared with independent exhaustive enumeration over a day's quarter-hour domain. Returned options and serialized-run constraints were also checked. |
| Constraint monotonicity | **308 comparisons**: increasing duration or narrowing availability never introduced a start that was previously invalid. |
| Clock progression | Advancing today's clock only removes possible starts, including crossing midnight. |
| Concurrent callers | **200 save requests** with **20 interleaved history reads**, followed by final reads/export: 200 unique runs retained and no unreadable records. Actor serialization is intentional; this does not mean 200 filesystem writes ran simultaneously. |
| Invalid and mixed history | Corrupt but syntactically valid records are retained on disk and counted as unreadable; valid neighbors remain accessible. A conflicting run ID cannot replace original bytes. |

These combinations are related checks over a small fixed catalog, not 1,155 independent real-world trials or evidence of city-wide reliability. The concurrency test uses an isolated temporary directory, not user history.

## Verification

| Layer | Result |
| --- | --- |
| VisitTiming | **59/59 functions passed**, including previous 28. [Final log](visit-timing-extreme-2026-11-05/runner-tests.log), [metrics](visit-timing-extreme-2026-11-05/metrics.json) |
| Existing Foundation package | **57/57 XCTest passed**. [Log](visit-timing-extreme-2026-11-05/legacy-tests.log) |
| Existing preference package | **29/29 XCTest passed**. [Log](visit-timing-extreme-2026-11-05/preference-tests.log) |
| Simulator build/UI | **4/4 passed**, iPhone 18 Pro / iOS 27.2, using final build 8. Includes the two old preference tests and timing closure/unknown/history/export/tab-preservation paths. [Summary](visit-timing-extreme-2026-11-05/ui-summary.json), [log](visit-timing-extreme-2026-11-05/ui-final.log), [screenshots](../../../../docs/missing-evidence.md#missing-81c808b6c745) |
| Actual Mac smoke | MapKit → Open-Meteo → policy v2 → save/export completed, status context_ranked, three alternatives, about **1.431 seconds**. This is one integration smoke, not a performance benchmark. [Run folder](../../../../docs/missing-evidence.md#missing-8f3d743c02d0), [log](visit-timing-extreme-2026-11-05/mac-live.log) |
| Formatting | Strict lint passed on changed Swift sources/tests. [Log](visit-timing-extreme-2026-11-05/format.log) |
| Preservation | Original venue data and acquired fixtures are unchanged. All 27 previously hashed Foundation/preference package source/resource files remain identical. Routing project was not edited. [Audit](visit-timing-extreme-2026-11-05/preservation.json), [final hashes](visit-timing-extreme-2026-11-05/source-hashes.json) |

No new physical-iPhone test/install was performed for build 8. The original build-7 phone run belongs to the [earlier checkpoint](VISIT_TIMING_REPORT_2026-11-05.md) and is not evidence that these fixes ran on a physical device.

## Reproduce

From the Foundation Lab folder:

~~~sh
bash scripts/test-visit-time.sh
bash scripts/test-visit-time.sh --filter ExtremeForecastTests
bash scripts/test-visit-time.sh --filter TimingInvariantTests
~~~

The dedicated runner supplies writable module-cache locations. Test directories are unique and removed after each storage test. No network is used by the 59-function package suite; the actual Mac smoke is separately labeled. New runs use policy v2, while supported historical v1 output is retained as historical output.

## Remaining limits

This strengthens deterministic behavior and data handling. It does not close the earlier gaps around manual fact acquisition/refresh, holiday exceptions, experiential best times or preference quality. It also does not establish arbitrary long-session reliability, disk-full/power-loss durability, service behavior under adversarial network streaming, or OS/physical-device cancellation. Those require different evidence; they are not counted as passing here. No commit, push or publication was performed.
