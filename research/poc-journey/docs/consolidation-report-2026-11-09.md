# Journey POC consolidation — 9 November 2026

Status: Ready for review.

## Source and structure

The worktree starts at main `48d7139`. The source checkout's committed POC tree is identical to main, so its tracked patch applied without conflicts. All 3,344 inventoried POC files matched after transfer, including 88 newly authored files. The source checkout's unrelated TripSense and evaluation changes were excluded.

Journey Showcase is the primary guided user application. Trip Integration remains the shared recommendation/timing/weather/routing/audit/storage engine and a diagnostic app. Foundation Lab, Native Routing Lab and CLI retain their research roles and existing paths. Production C67 is unchanged.

## Evidence boundary

The original publication manifest and historical source dates/results are preserved. A separate development ledger describes 18 transferred maintained-source changes plus a quality-screen focus correction and its UI-test compatibility correction (20 entries total). Validator tests reject wrong baseline hashes, subsequent tampering, unregistered changes and archival overrides. New reports do not relabel old test results as new execution evidence.

## Execution results

| Check | Fresh result |
| --- | --- |
| Five shared Swift packages | 265 test functions passed |
| Python evidence/importer/runner tests | 51 passed |
| CLI check, formatting and tests | 55 tests passed |
| Native weather/local harness | 100 tests and cross-process write/read passed |
| Native Jakarta harness | 26 tests passed |
| Native unsigned Simulator builds | All four apps passed |
| TJ capability evaluator | All 64 expected outcomes matched; no errors |
| TJ departure/access sweep | 1,000 inputs, no invariant errors |
| Pinned full-feed source audit | 5,552 observations over 241 routes / 694 patterns; no invariant errors |
| Foundation Lab app/UI | Six unaffected full-suite cases passed; all three corrected Quality cases passed on targeted rerun |
| Trip Integration app/UI | Four passed after resume, zero failed/skipped |
| Showcase app/UI | 26 passed after resume, zero failed/skipped |
| Pinned public E5 assets | Four assets passed size/SHA256 checks |
| Formatting and static checks | SwiftFormat, evidence, portability/link and whitespace checks passed |

The TJ core cases include explicit conflicts, unsupported capabilities, injected provider failures and missing-data cases. Matching these expected results does not mean every itinerary is feasible. The wider source audit is distinct from the imported 199-route runtime subset. The existing captured GTFS ZIP was read locally; no new feed was downloaded and no source timestamp was advanced.

The three apps cover 39 unique app/UI cases: Foundation Lab 9 (six unaffected cases passed in full-suite runs, then all three affected Quality cases passed in `QualityFinal.xcresult`), Trip Integration 4 and Showcase 26. Earlier failing or interrupted bundles remain retained; their failures are not counted as final passing executions. The resumed bundles live under `ui-resumed/`, and the final Quality summary is `quality-final-summary.json`.

Raw outputs remain under the ignored `.verification/consolidation-20261109/` directory. Package test functions are counted separately from parameterized scenario inputs. CI configuration is updated, but no remote workflow run is claimed.

## Corrections during consolidation

The portable verification runner no longer requires the local agent's `rtk` executable, and its optional arrays work with macOS Bash 3.2 under `set -u`. Three runner tests exercise four-app dispatch, optional cache paths containing spaces, and TJ runs with/without a captured ZIP.

The first Foundation Lab UI bundle retained two navigation failures in the old quality helper. The helper now uses the actual visible keyboard/tab-bar bounds, adjusts direction to the target and locates the liked-facet menu across accessibility types. The quality screen dismisses direction focus before comparing and when scrolling. Its direction binding ignores identical writes, preventing keyboard commits from invalidating an in-flight comparison, and disables automatic text correction to preserve the typed instruction. It preserves all preference/ranking assertions. Earlier wrapper attempts were also retained: editing the shell runner during execution caused trailing parser failures after their underlying checks completed. Final acceptance runs use the settled runner and fresh output directories.

## Limits and delivery

The consolidation is ready as a local diff on `codex/poc-journey-consolidation`, based on main `48d7139`. Open the Showcase project from this worktree using the [primary guide](../apps/c67-journey-showcase/README.md). Shared package ownership and standalone research applications retain their existing paths. New source, fixtures, maps, reports and tests are present as tracked modifications or new untracked files for review.

No live-provider, signed-device, field-journey or production acceptance is implied by deterministic checks. No source changes are committed, pushed or deployed.

## Original checkout preservation

The preservation audit before interruption verified unchanged HEAD, branch, index checksum, every pre-existing status entry and all 3,771 inventoried file hashes. On resume, the source HEAD/branch/status and checksums of all 88 transferred new files and the imported maintained-source entries were checked again. Two unrelated icon ZIP archives appeared under `Claude outputs/` during execution, adding one untracked-directory status entry. They were left untouched and were not copied into this worktree. Exact status equality therefore has this externally observed addition; no pre-existing change was removed or overwritten.

## Comparative assessment

The [before/main comparison and assessment](poc-consolidation-assessment-2026-11-09.md) separates transferred features from consolidation fixes, explains test coverage and assesses remaining gaps. In particular, 30 of the 31 unsupported observations in the 64-case TJ summary exercise legacy schema-v1 gates. Modern-network regressions are separate; the 64-case outcome ratio is not the current network engine's coverage or failure rate.
