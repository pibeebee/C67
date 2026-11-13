# Journey POC: before/main comparison and assessment

Date: 9 November 2026
Status: Local consolidation ready for review
Branch: `codex/poc-journey-consolidation`

## 1. Decision and summary

**The result is good as a consolidated technical POC and a basis for further validation. Production readiness, current citywide TJ success rates and real-world recommendation quality remain unproven.**

The main contribution of this task is a reproducible workspace that retains the latest local features, makes application/package ownership clear, preserves historical evidence and passes the selected regression checks after concrete fixes. It is not a newly demonstrated improvement in recommendation accuracy or live routing speed.

There are three states to distinguish:

1. **Main baseline:** `48d7139ebb008f0ad06e9f9ef2dbb0f1fe7cc2b8`, containing the imported experiment handoff.
2. **Local POC before consolidation:** the same committed POC baseline plus the subsequent local TJ, Showcase, maps and custom-input work.
3. **Consolidated worktree:** current main as its base, with those scoped local changes transferred, documentation/CI/evidence validation aligned, and discovered UI/runner defects corrected.

The committed `poc-journey` tree on main matched the source checkout's committed tree exactly (`433ac4e0f32ca81da6103e95fd77b9a396afa778`). The tracked patch applied without conflicts. The inspected main did not supply a different newer routing/recommendation engine to reconcile; most current functional capabilities came from the local POC work already performed.

## 2. What changed and where it came from

| Area | POC on main | Latest local POC before consolidation | Consolidated result |
| --- | --- | --- | --- |
| Application entry point | Trip Integration and three sibling research projects | Guided Showcase app added locally | Showcase is documented as the primary user UI; the four research/diagnostic projects remain available |
| Shared engine | Trip Integration with sibling preference/timing packages | Same ownership, extended for TJ and custom inputs | Existing package direction retained; engine logic is not copied into Showcase |
| Starting point | Request validation fixes origin to Bundaran HI | Search/select an origin within the existing Jakarta boundary | Custom origin retained, including coordinate confirmation and invalidation on edits |
| Destination preferences | Original sourced Jakarta candidates and feature preferences | Combined catalog, eight target areas and required catalog spots | Retained; 26 candidate records include distinct spaces at the same venue, not 26 independently schedulable destinations |
| TJ itinerary | No explicit TJ option in the integrated request | Attributed network subset, direct/one-transfer routing, walking and TJ detail UI | Retained with 199 routes / 544 patterns in the runtime snapshot |
| Showcase maps | Showcase absent from main | Zoom, full-screen view, MapKit road geometry and GTFS bus shapes | Retained; bus geometry covers 542 of 544 runtime patterns |
| Proposal lifecycle | Reviewed save/apply/revision and audit | Extended to preserve custom inputs and TJ evidence | Retained, including old JSON compatibility, rejected/stale proposal guards and exports |
| Evidence validation | Import hashes checked against current files | 18 maintained imported files differ functionally from that baseline | Original manifest kept; development ledger covers those 18 changes plus two consolidation corrections |
| Verification tooling | Existing handoff runner and CI | Extra TJ/Python/Showcase checks present locally | CI and runner aligned; local RTK dependency removed from portable runners; Bash 3.2 optional-array handling corrected |

All 3,344 inventoried POC files matched immediately after transfer, including 88 newly authored files. The worktree was created separately, leaving the original branch and its nine local commits in place. TripSense, unrelated evaluations and private configuration were excluded from the transfer.

## 3. Defects found and corrected during consolidation

| Finding | Cause | Correction and result |
| --- | --- | --- |
| Evidence validator rejects 18 active files | It compares evolved maintained code with immutable import publication hashes | Added a separate, explicit development ledger and validator tests. Original source/publication hashes remain unchanged |
| Portable runner depends on RTK | Locally authored orchestration invoked a developer-only executable | Internal runner/evaluator subprocesses use standard tools. Tests exercise dispatch with RTK absent |
| Optional runner arguments fail on macOS Bash | Empty arrays combined with `set -u` are incompatible with the previous expansion on Bash 3.2 | Safe optional-array expansion; tests cover absent arguments and paths containing spaces |
| Quality UI tests cannot reliably reach controls | Whole-screen gestures, fixed screen margins and menu accessibility types do not match the visible content | Use actual keyboard/tab-bar bounds, target-aware scrolling and the stable menu identifier |
| Quality comparison disappears after keyboard dismissal | Repeated identical text-binding writes are treated as edits and invalidate the in-flight comparison | Ignore identical direction writes, dismiss focus before comparison and preserve literal input by disabling automatic correction |

The three affected Quality UI cases passed after correction, including the requirement that unconfirmed negation produces `preference_review_required`. Ranking rules and hard factual gates were preserved.

Some early wrapper runs also ended with shell parsing errors because the runner was edited while executing. Their underlying outputs were retained; settled-runner acceptance checks were executed separately. The interrupted integration run was retained and rerun after resumption. These failed/interrupted attempts are not presented as successful final runs.

## 4. Tests actually executed and how to interpret them

| Check | Recorded result | What it establishes |
| --- | --- | --- |
| Five shared Swift packages | 265 test functions passed | Preference/fact gates, timing, routing, cancellation, audit, persistence, old request decoding and other package behaviors |
| Python tests | 51 passed, including a rerun after resumption | Evidence integrity, importer/evaluator behavior and portable-runner dispatch |
| CLI | 55 tests passed, plus check/format commands | Existing CLI behavior remains usable |
| Native harnesses | 100 weather/local tests plus 26 Jakarta tests passed; cross-process write/read passed | Existing native experiment behavior and storage checks remain usable |
| Native builds | Four apps built successfully | Native Routing Lab, Foundation Lab, Trip Integration and Showcase compile for Simulator |
| Foundation Lab app/UI | Six unaffected full-suite cases passed; three affected Quality cases passed on targeted rerun | Nine unique covered cases, with explicit provenance across full and targeted runs |
| Trip Integration app/UI | 4 passed, 0 failed/skipped | Replay review/acceptance, Blok M/TJ flows and provenance distinction |
| Showcase app/UI | 26 passed, 0 failed/skipped | Guided creation, custom inputs, maps, save/relaunch/export, revision and cancellation behavior |
| TJ capability matrix | 64 observations match their expected outcomes | Mixed legacy-schema gates, direct-routing probes, conflicts, provider-error handling and data-gap checks |
| TJ sweep | 1,000 controlled corridor-1 departure/access inputs; 320 feasible and 680 expected conflicts; no invariant errors | Behavior under the authored access/service constraints, not an overall Jakarta success rate |
| Full captured-source audit | 5,552 observations across 241 routes / 694 patterns; no invariant errors | Source consistency and availability/gap observations; distinct from runtime journey generation |
| Static checks | 3,231 imported copies validated; 20 maintained changes registered; portability/link, SwiftFormat and whitespace checks passed | Reviewed source provenance, basic portability and formatting |

The app/UI total is **39 unique cases** across full runs and targeted corrections. It is not a claim that every case passed in one final uninterrupted bundle. Parameterized TJ inputs and source observations overlap package checks and must not be added to the test-function counts as independent experiments.

### Modern network evidence versus legacy tests

The 64-case report contains 11 `supported_feasible`, 16 `supported_conflict`, 31 `unsupported_capability`, four injected `provider_failure` and two `missing_data` observations. **Thirty of those 31 unsupported observations explicitly test legacy schema-v1 rejection; the remaining one tests a catalog limitation.** This breakdown must not be used as the modern 199-route engine's unsupported-rate metric. The feasible group also includes synthetic/walking controls, rather than 11 independently validated TJ itineraries.

Modern-network behavior has separate passing regressions in `BuswayImprovementTests`: route-aware platform selection, comparisons against the frozen baseline, source-route endpoint probes, two-corridor transfers (2→1 and 3→1), transfer timing/failure boundaries, custom-origin city itineraries and transfer itinerary save/reload/export. The paired test asserts no loss of previously feasible inputs and a higher feasible count within its authored matrix. Consolidation logs confirm the test passed; they do not retain a new per-case paired-results export, so this report does not reuse older percentage/latency figures as fresh measurements.

Representative integration checks include Tebet→Cikini by car, Senayan→a selected Blok M spot by TJ, Cikini→Erasmus with a reading preference and a Pulo Gadung→Blok M itinerary with an official-source corridor transfer. Walking/weather/search dependencies in these deterministic scenarios are explicit test providers.

## 5. Assessment: is the result good?

| Dimension | Assessment | Reason |
| --- | --- | --- |
| Scoped code consolidation | Good | Identical baseline, conflict-free application of the patch, checked transfer hashes and a separate worktree |
| Architecture and developer handoff | Good | A clear primary UI, one shared engine, retained research projects and updated guides |
| Regression robustness | Good within tested constraints | Current package/app checks passed after real UI and runner defects were corrected |
| Evidence integrity | Improved | Historical hashes are preserved; active evolution is explicit; failed runs and legacy limitations remain visible |
| Modern TJ coverage measurement | Incomplete | Current-network regressions exist, but the 64-case summary mixes legacy gates and current behavior |
| Personal recommendation quality | Not established by consolidation | No new participant study, held-out user relevance evaluation or satisfaction/input-effort measurement |
| Live operational reliability | Not established by consolidation | No new final-worktree physical-device, live-provider or field-trip acceptance |
| Production readiness | Not ready for release on this evidence | Runtime/data limits, provider/field validation and publication/review work remain |

Passing tests establish the checked contracts and invariants. They do not prove that all combinations are supported, all locations are current, the route is globally optimal, or the recommendations match real users' tastes. The task did not measure a new recommendation-quality or live-ETA improvement caused by pulling main.

## 6. Remaining limitations and recommended follow-up

1. **Separate legacy and current-network reporting.** Keep legacy compatibility tests, but add a clearly labeled modern-network end-to-end matrix across supported TJ categories, origins, transfer pairs and venue constraints. Report routing feasibility separately from catalog rejection, provider failure, service unavailability and bounded-search exhaustion.
2. **Run current-worktree live acceptance.** Check selected addresses/branches, MapKit walking/road responses, primary WeatherKit, cancellation, background/relaunch and network interruption on a physical iPhone. Earlier device successes remain historical and do not automatically validate this consolidation.
3. **Broaden and refresh sourced place facts.** Destination choice remains a finite catalog. Some area candidates lack eligible hours or verified preference attributes. Arbitrary MapKit destinations are not assigned inferred hours. Unknown attributes remain unknown. Recheck facts and GTFS as new dated captures without editing the old fixture clocks or source hashes.
4. **Validate real TJ transfers and access.** The router supports direct service and a fallback with at most one transfer; it does not cover arbitrary multi-transfer or TJ–MRT/KRL planning. Access discovery is within 800 m and each walking component is limited to 20 minutes. GTFS proximity and synthetic buffers do not prove a safe entrance, accessible crossing, valid paid-area connection or observed holiday/headway behavior. Wheelchair and per-user walking needs are not fully modeled.
5. **Keep route/geometry uncertainty visible.** Two runtime patterns (JAK.59-R03 and 3H-R06) lack accepted ordered geometry. Direct services are preferred before the transfer fallback; bounded candidate search is not a global-optimum guarantee. Bus waits use static headways and buffers, rather than vehicle arrival tracking. Venue capacity, queues and sudden closures remain outside the guarantee.
6. **Measure user benefit and operational performance.** Use real preference profiles and user review to distinguish generic recommendations from personal fit. Measure cold/warm latency and provider request/error behavior for 1–6 destinations on-device. Synthetic engine timings do not establish live ETA accuracy or user-perceived speed. Accessibility and field usability also need dedicated acceptance.
7. **Finish normal delivery review.** At this assessment checkpoint, the diff was local, uncommitted and unpushed. CI configuration had been edited; no remote CI run, PR, production port or deployment was included. Review the changed/new files before publication.

Recommended next task: create the modern-network reporting matrix and perform a bounded physical-device live run, while retaining the current deterministic suites as regression protection.

## References and evidence

- [Consolidation execution report](consolidation-report-2026-11-09.md)
- [Task and acceptance criteria](tasks/poc-consolidation-2026-11-09.md)
- [Current application guide](../apps/c67-journey-showcase/README.md)
- [Custom input behavior and prior evidence](tasks/journey-custom-origins-and-areas.md)
- [Evidence policy](../evidence/README.md)

Fresh local evidence is under ignored `.verification/consolidation-20261109/`: package/CLI/native/build acceptance logs, TJ summaries, full and corrected Quality bundles, resumed Trip Integration/Showcase bundles and preservation records. This assessment reviews that completed run; it does not claim a new execution of the behavioral test suites while writing the report.
