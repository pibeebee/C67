# Benchmark code validation — 7 November 2026

Code defects affected search coverage and the interpretation of the itinerary benchmarks. The validation reproduced each defect before applying corrections. Historical timing records and successful schedule arithmetic passed stricter checks. Search completeness and method selection need reassessment with the corrected implementation.

The review covers `PlaceContextEngine`, the context pilot CLI, Apple ETA adapter/parser, independent fixture evaluator and live auditor. Native A–E historical timing tables were checked against their saved reports. Validation uses preserved inputs and a bounded new live run. Temporary instrumented builds exercise copies of the original context engine.

## Confirmed defects and corrections

| Defect | Reproduction | Correction and effect |
| --- | --- | --- |
| ETA budget gate skipped cached legs | Instrumented original search skipped a cached candidate in 49 of 504 configurations using the existing five-stop fixtures. | Check cache before reserving new calls, recompute available budget per destination, and permit cached prefixes after the call cap is reached. Two configurations that previously returned no candidate now return five stops at the same declared caps of 12 and 24 calls. |
| Search cutoff flags omitted policy limits | Regression tests show that a three-order cutoff and visit-slot shortlisting could leave `searchTruncated` false. | Report truncation when orders or slots are left unexamined. Returned candidates still require feasibility checks. |
| Partial ETA item invalidated a whole batch | A synthetic two-destination response contains one complete ETA and one item missing distance/time. The original decoder throws and the caller marks both unavailable. | Decode missing timing/distance fields per destination, preserve valid items, and emit a specific missing-field diagnostic for the affected destination. A missing travel time remains unavailable. |
| Auditor accepted inconsistent status/coverage | The fixture auditor accepted an empty result labeled `candidate`. The live auditor accepted visits labeled `no_candidate_within_search`. Missing/duplicate fixture rows and wrong campaign totals also lacked checks. | Require status to agree with visits, require complete unique fixture observations, and cross-check ETA cell accounting and stage/pipeline timing. Six injected corruptions are rejected. |

The cache defect is in the new context planner. The partial-batch decoder is shared by the local REST lab. The reproduced one-item response failures still contain genuine missing provider fields. The batch correction preserves healthy neighboring responses when batching is used.

## Controlled before/after evidence

The same 24 existing five-stop fixture cases run under 7 ETA caps and 3 policies, totaling 504 configurations per engine version. Independent arithmetic/session/wait checks passed for all 504 corrected outputs.

| Case | ETA cap | Original | Corrected | Actual calls before → after |
| --- | ---: | --- | --- | ---: |
| Development split-session fixture 1, first-feasible | 12 | No candidate | Five-stop candidate | 8 → 12 |
| Same fixture and policy | 24 | No candidate | Five-stop candidate | 20 → 24 |

Across these configurations, two gained a candidate and zero lost one. This is an exploratory regression comparison on existing cases. These cases were used to diagnose the defect, and the comparison supplies no new held-out generalization estimate. A permanent regression test recreates the 12-call counterexample with explicit directed travel costs and split sessions.

Instrumented observations (original local evidence, omitted from this publication), corrected observations (original local evidence, omitted from this publication), comparison summary (original local evidence, omitted from this publication).

## Audit of existing measurements

Stricter auditors rechecked 37 stored live observations across seven reports and 540 fixture observations from the three-stop and five-stop campaigns. All passed status, schedule, cell-accounting and applicable timing checks. Copies are under the validation artifact directory, preserving the original reports.

The route timer uses `ContinuousClock` wall time around the planner. It includes ETA acquisition and the lab's 1.2-second pacing. The diagnostic path also writes a trace during the provider call. Its duration is therefore elapsed adapter work. The complete CLI timer includes search/enrichment, successive plan jobs and checkpoint writes. A campaign timer covering multiple plans cannot serve as one itinerary's latency.

Old processing durations describe executions of the old code. Failed-attempt durations remain failure latencies. The validated schedule arithmetic does not establish complete search coverage or human acceptance of a new five-stop result.

The five-stop diagnostic request used `beamWidth = 1` and a geographically authored input order. The primary benchmark used width 12 and a different input order. Comparisons across those settings reflect both changes. The code persists the width/order in the diagnostic report.

## Replay of recorded live ETA

An offline replay reconstructs the declared operating windows and visit requests from the saved five-stop report, then supplies only recorded ETA values at the exact requested departures. The original engine requests all 59 recorded cells and returns `incomplete_travel_data`. The corrected engine requests 62 cells, including three queries outside the archived trace. It also returns `incomplete_travel_data` in this replay. Unknown queries remain unavailable.

This replay demonstrates the changed search path and the evidence gap for three additional queries. Fresh provider validation is required to observe those queries. Replay before (original local evidence, omitted from this publication), replay after (original local evidence, omitted from this publication).

## Fresh live check after correction

One bounded live check fetched five fresh place details, independently searched Apple identities, and obtained WeatherKit data for the same next-day five-stop request. It retained the 30-minute wait cap, 15-minute grid, geographic input order, search width 1 and 64-call cap.

The corrected engine made 62 ETA calls in 77.55 seconds of route processing and returned `incomplete_travel_data`. Fifty-five responses supplied usable ETAs. Seven responses omitted the distance and travel-time fields and now have precise missing-field diagnostics. The independently checked totals and non-ready outcome agree with the trace. Fresh report (original local evidence, omitted from this publication), ETA trace (original local evidence, omitted from this publication), audit (original local evidence, omitted from this publication).

The implementation uses `incomplete_travel_data` whenever any explored leg lacked an ETA and the bounded search returned no candidate. That label supplies an observation about missing evidence. It cannot establish that missing data caused the failure of every possible itinerary. A successful live five-stop result under the original waiting cap remains unobserved.

## Scheduling assumption

The 15-minute start grid is explicit in `VisitContextEngine`. Both the planner and the independent reference used that grid. They therefore agree on its arithmetic while imposing a scheduling restriction the user never requested.

On the earlier candidate obtained under a 60-minute wait cap, all 39 minutes 56 seconds of waiting match rounding each arrival to the next quarter-hour. The user requested at most 30 minutes. That result supports investigating start-time flexibility. It does not establish that a different five-stop order cannot meet the original cap. This validation retains the existing start grid so the code corrections can be evaluated with the same scheduling model.

## Verification

- 107 regular package tests passed, including four new Swift regressions. One explicit fixture benchmark remains skipped in the generic suite and is covered by the separate campaigns.
- Three initial Swift regressions failed against the original code. The cache counterexample is also reproduced by the original instrumented engine and covered by the fourth permanent regression.
- Six Python auditor corruption controls passed.
- 504 corrected comparison outputs passed independent hard-rule checks.
- 37 stored live outputs and 540 stored fixture outputs passed stricter re-audits.

Failed regressions before correction (original local evidence, omitted from this publication), verified package tests (original local evidence, omitted from this publication), auditor controls (original local evidence, omitted from this publication).

## Effect on the method recommendation

The earlier recommendation of first-feasible remains supported for the particular accepted three-stop schedule. Method ranking for five stops needs a fresh comparison using the corrected cache/decoder/coverage checks. Existing five-stop failures reflect both search implementation defects and restrictions in the scheduling model. Current evidence supports preserving the original 30-minute waiting requirement while reassessing search behavior.
