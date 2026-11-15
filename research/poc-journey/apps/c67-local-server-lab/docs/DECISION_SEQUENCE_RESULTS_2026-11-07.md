# Decision-sequence experiment — 7 November 2026

## Decision

The diagnostic-first sequence produced useful, falsifiable decisions. Independent stress fixtures exposed a quality gap hidden by the earlier distance-based replay. A bounded intervention E3 improved that gap, while live simulator runs measured a substantial latency cost. Live discovery found the six external named places, but their integration/fact prerequisites were absent. No new recommender model, road engine, training job, or pacing change was selected.

This is evidence that the sequence was useful for this workspace. It does not prove it is the universally optimal order of experiments, or that E3 has production accuracy. The original app is unchanged; E is an experimental lab variant.

## Evidence and frozen decisions

- [Protocol](DECISION_SEQUENCE_PROTOCOL_2026-11-07.md), frozen before observations.
- Fixture identity (original local evidence, omitted from this publication): 144 synthetic cases, 48 development and 96 held-out; four stop counts, six families, separate seeds.
- E3 selection lock (original local evidence, omitted from this publication): E2/E3 compared on development only; E3 selected before the holdout ran. Runtime policy hash unchanged afterward.
- Held-out audit (original local evidence, omitted from this publication), secondary control audit (original local evidence, omitted from this publication), consolidated summary (original local evidence, omitted from this publication).
- All fixture metrics CSV (original local evidence, omitted from this publication), live metrics CSV (original local evidence, omitted from this publication), paired live quality CSV (original local evidence, omitted from this publication), final verification (original local evidence, omitted from this publication).

## 1. Establish independent quality and discovery baselines

Python generated directed costs independently of coordinates and the D distance prior. Families cover asymmetric costs, explicit bottlenecks, continuous FIFO time-dependent congestion, multiple visit sessions, tight/impossible deadlines, and unavailable providers. The independent evaluator enumerated all 31,320 permutations across the fixtures, enforcing every stop, full dwell, 15-minute visit starts, session boundaries, return and deadline. The objective is earliest-valid-start elapsed, then travel. FIFO makes earliest feasible starts appropriate for this reference; arbitrary non-FIFO waiting optimization is outside scope.

The real lab C and D methods ran against these providers. C uses the actual bounded hybrid/batch code with full-search requested for these fixture comparisons; it is not an exact oracle. Python reconstructed the returned schedules and ETAs without importing the Swift planner. No returned feasible itinerary violated the independently checked constraints.

Development: of 36 oracle-feasible cases, D had 24 material-gap cases; C had one. The predeclared flag was elapsed gap >300 seconds OR >5%; this is an engineering flag, not a user acceptance threshold. This triggered the bounded-validation branch.

The fixtures are deliberate stress cases, not a representative sample of Jakarta. A seed split is a holdout within these families, not a new-city generalization test. Reference optima apply to these synthetic cost functions only. They do not establish Apple ETA or field accuracy.

## 2. Test a bounded intervention and its cost

E adds at most three validations. It starts with the D shortlist, uses observed edge/prior mismatch, waiting and deadline slack as continuation triggers, calibrates only speculative ranking, and deliberately explores a different first stop on attempt two. It keeps the best provider-validated result. Final ETAs still come from the unchanged exact-departure evaluator; speculative values never enter final legs or the provider cache. No learned traffic model is involved.

On development, E2 had 19 material-gap cases and median 10 ETA cells; E3 had 16 and median 14. E3 was selected before running the held-out cases.

There were 76 oracle-feasible holdout cases, four provably infeasible cases and 16 provider-unavailable cases. All 96 remain in the evidence. Unavailable is not treated as infeasible.

| Policy | Missed feasible | Material gap among returned feasible | Combined quality failures / 76 | Median ETA cells on oracle-feasible cases | Median elapsed gap among returned feasible |
| --- | ---: | ---: | ---: | ---: | ---: |
| C bounded hybrid | 0 | 2 | 2 | 45 | 0 s |
| D first feasible | 1 | 57 | 58 | 6 | 2,520 s |
| E3 selective | 0 | 40 | 40 | 14 | 465 s |
| F3 fixed local top three | 2 | 51 | 53 | 12 | 1,800 s |

E3 reduced combined failures versus D by 31.0%, with median cells 68.9% below C. It passed the predeclared synthetic tradeoff gate. **Residual failure in 40/76 feasible stress cases is substantial:** the experiment does not justify calling E3 accurate enough for general use. C also misses the optimum on two cases, reinforcing why C is not ground truth.

F3 is a secondary control added and frozen after the primary holdout results; E3 was not retuned. It validates the first three prior-ranked orders without calibration or a risk trigger. Both policies have a three-candidate cap, but their actual ETA cell counts differ because orders share different prefixes/departure times. F3 therefore does not isolate selective ranking from identical network expenditure. It is a useful cost/quality comparison, not proof of superiority at exactly equal cell budgets.

There are 576 audited policy observations in total: 96 baseline development, 96 development intervention, 288 primary holdout, and 96 secondary control. The raw field named `cpuSeconds` measures local wall duration, not process CPU; summaries label it `medianLocalWallSeconds`.

## 3. Contemporary client/server simulator experiment

Build: Debug, iPhone 18 Pro Max simulator/iOS 27.2, same Mac, one server worker and one active provider request, same actual E5 and precomputed catalogue passages. Apple Maps REST ETA and WeatherKit are live, fallback off, ETA start spacing 1.2 seconds, no cross-job ETA cache. D and E alternate per case.

The contemporary trip is **Saturday 7 November, 09:00–19:00 WIB**. This intentionally differs from the earlier benchmark's 07:00 starts for N4/N5. Old and new latency figures must not be treated as an unchanged paired experiment. Both current variants share date, constraints and the same six archived real pins, validated within their 24-hour lab window. Discovery is excluded from this controlled timer and tested separately below.

Client timer covers submit, job processing, complete result reception and client persistence. E returns its completed bounded search; it does not stream or expose its first internally feasible candidate. Proposal acceptance/revision is exercised using each variant's own N5 baseline.

| Stops | D median complete-result latency | E median complete-result latency | Median ETA calls D → E | Observed E minus D itinerary elapsed |
| --- | ---: | ---: | ---: | ---: |
| 1 | 2.39 s | 2.38 s | 2 → 2 | 0 s |
| 3 | 4.67 s | 13.25 s | 4 → 11 | 0 s |
| 4 | 5.88 s | 16.71 s | 5 → 14 | −17 s, each repetition |
| 5 | 7.12 s | 19.10 s | 6 → 16 | −927 s, each repetition |

For N5-R1, D elapsed was 486.65 minutes, E 471.20 minutes. E saved 9.32 travel minutes and 6.13 waiting minutes, preserving all visits and full dwell. REV5 saved 793 seconds and MIX5 877 seconds versus their contemporary D results. For N4, E traveled 10.57 minutes longer but waited 10.85 minutes less: a tiny elapsed improvement is not automatically a better human experience.

All 34 observations completed: 28 ready and six legitimate non-ready outcomes. The final independent live audit passed 34/34. TIGHT5 at 09–13 failed the sourced GBK session/full-stay gate before the aggregate dwell check, so its observed outcome is `needs_places`, not `infeasible_lower_bound`. The initial auditor expected the older time-window outcome and flagged two rows; that initial audit is preserved (original local evidence, omitted from this publication). The corrected auditor independently checks the raw Saturday sessions and dwell inequality, with an additional corruption test ensuring this is not a blanket allowance.

The internal first feasible candidate appears at approximately 6–7 seconds for both D/E on N5, reconstructed from second-resolution logs relative to job start. This is not an exposed user result or a precision latency benchmark. A progressive-result UI remains unimplemented.

Live provider observations can drift. These paired results are not a global optimum or causal regret estimate. Three repetitions do not establish p95 or an SLA. Short local regression/control checks overlapped parts of the campaign on the shared Mac; this is not a host-isolated performance experiment. E adds no observed benefit on N1/N3 while increasing N3 latency substantially, so enabling it unconditionally is not supported.

## 4. Real discovery and external-place gates

Discovery evidence (original local evidence, omitted from this publication): 12 actual named searches, six existing identities and six outside the integrated catalogue. The external places are Museum BI, Museum Nasional, Museum Wayang, Museum Tekstil, Museum Bahari and Museum Joang 45. Definitions and aliases were written before calls. Operator/government references establish the named targets, not fresh opening hours or user relevance:

- [Bank Indonesia](https://www.bi.go.id/id/layanan/museum-bi/default.aspx)
- [Museum Nasional address](https://www.museumnasional.or.id/alamat/)
- [Jakarta museum directory](https://www.jakarta.go.id/index.php/museum)

All six external queries returned one authored name-token match. This is not a blind human identity/relevance evaluation, and named searches do not establish recall for open-ended preference requests. Returned fields included name, coordinates, address, identifiers and sometimes category. No opening-hour or required amenity fields were observed in these responses. No claim is made about every Apple API or the system place-card UI.

The existing stricter identity policy selected only 4/6 existing locations: origin remained ambiguous and GBK did not satisfy its name gate. A separate simulator run with actual search and no shared pins completed six attempts (N1/N3/N5, D/E), all `needs_locations`, in approximately 1.32–4.14 seconds. **Those are not successful itinerary-generation timings.** The full-search audit (original local evidence, omitted from this publication) preserves these outcomes.

Six additional actual HTTP jobs attempted the external IDs. All failed the current catalogue/domain gate before provider work; counters did not increase. External gate evidence (original local evidence, omitted from this publication). Thus candidate discovery, supported identity mapping and sourced facts must be addressed before a new reranker can deliver an external-place itinerary through this pipeline. The evidence does not establish that POISS or another model would be useless after those prerequisites are met.

## Verification, bounds and cleanup

- 69 regular tests passed; the explicit-path benchmark test is skipped in the generic suite and was separately executed for all four fixture campaigns. Initial Swift literal compilation errors were corrected and the original failure log retained.
- Six fixture-auditor corruptions, six live-auditor corruptions and one sourced-session corruption were rejected with explicit validation errors.
- 13 HTTP calls for raw discovery, 25 for the full-search simulator flow, and 377 for controlled D/E: **415 HTTP calls and 224 ETA cells**, within the frozen 1,000/1,200 campaign bounds. Account remainder remains unknown; no quota/auth stop occurred.
- Server RSS peak 321.16 MiB; maximum resource sampling gap 1.071 seconds. These are Mac process observations, not iPhone memory/energy or production capacity. Resource summary (original local evidence, omitted from this publication).
- Original 66 source/input hashes remain identical; original simulator app binary restored and launched. Lab servers stopped and temporary tokens revoked. Normal-store inventory before the experiment contained zero files under the checked normal Documents/Application Support locations; no nine-file preservation claim is made for this run.
- UI automation could not bind the Simulator application. Client execution and result exports are verified; visual layout and touch interaction are **not** verified in this experiment.
- No production integration, model download/training, road-engine installation, pacing modification, deployment, homelab usage, commit or publication.

## What the sequence supports next

Keep D/E as explicit lab tradeoffs rather than a blanket accuracy upgrade. Investigate a stricter rule for when extra validation is worth its latency, with equal-request-budget comparisons and new held-out scenarios. For outside-catalogue planning, address identity and sourced metadata first. Recommender changes become testable after an eligible candidate corpus and independent human relevance labels exist.

## Reproduction

Use a fresh directory for a new fixture campaign; retain the existing evidence. From the lab directory:

```sh
python3 scripts/decision-fixtures.py generate artifacts/my-decision-run
C67_DECISION_FIXTURES="$PWD/artifacts/my-decision-run/fixtures.json" \
C67_DECISION_OUTPUT="$PWD/artifacts/my-decision-run/development.json" \
C67_DECISION_VARIANTS=C,D,E2,E3 \
swift test -j 4 --filter DecisionSequenceTests/testBenchmark
python3 scripts/decision-fixtures.py audit artifacts/my-decision-run \
  --observations artifacts/my-decision-run/development.json \
  --output artifacts/my-decision-run/development-audit.json
```

Freeze policy selection before setting `C67_DECISION_SPLIT=holdout`. Do not tune on the historical holdout. Live reproduction requires a new future/current supported trip window, fresh sources/pins, a fresh manifest and budget, private local configuration, simulator app backup and final restore. Do not replay the November 7 departure as though it were a new live request.
