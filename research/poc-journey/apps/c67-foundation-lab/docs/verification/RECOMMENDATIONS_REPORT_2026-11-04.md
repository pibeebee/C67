# Foundation Lab v0.2 — preference-first place recommendations

Date: 2026-11-04, Jakarta/WIB. Physical-iPhone follow-up: **2026-11-05**. Build: 4. Prompt: `recommendations-v1`.

The implemented flow now tests the Foundation Models part of the supplied onboarding concept independently of routing. A user can start with no itinerary, choose interests and pace, and receive retrieved place candidates with model assessments and broad visit-time suggestions. Alternatively, the user can select up to six places and retain every one with equal priority.

**Conclusion:** the new flow runs with native Apple technologies and local model inference on the tested Mac and physical iPhone. The Mac series demonstrates broad place matching and understanding an English preference correction. The iPhone follow-up completed with three recommendations and three rejected/fallback stages. It does **not** establish reliable best visiting times for real Jakarta venues, fully grounded free-form explanations, or reduced user effort in an observed user session. See the [physical-iPhone follow-up report](recommendations-iphone-2026-11-05/REPORT.md).

## Delivered behavior

- Preference-first onboarding, with no routing JSON required. Interests and pace are optional; additional intent controls and English text are collapsible.
- A named-place search sheet requires an explicit selection, rather than silently accepting the first search result. Synthetic UI mode is labeled.
- MapKit discovery uses up to three queries, interleaves result categories, removes duplicates and checks the existing Jakarta operational mask. Up to ten retrieved candidates are retained; at most six are assessed in fresh model sessions.
- Per-candidate structured assessment separates fit, reasons, broad visit window, basis, source references and unknowns. At most three positive discovery assessments are marked as recommendations. Selection takes positive assessments in native shortlist order; this is not a learned global ranking or an optimization of the whole trip.
- Broad category/name matching gates positive discovery assessments. It does not prove quietness, reading seats, price, crowds, popularity or accessibility.
- Visit suggestions distinguish supplied opening/experience facts, tentative general activity ideas and unknown timing. A specific window must overlap known opening hours. A claim of supplied time facts must cite a supplied time fact.
- All explicitly selected places remain present even if assessment fails or they do not match current preferences. No main destination is invented.
- Alternatives exclude previous discovery selections (or reviewed candidates when no selections were available). Preference changes invalidate results and cancel pending work. Empty search results display an empty state.
- Explicit profile saving, separate recommendation history, raw/rejected output, source inspection and JSON/Markdown export. The older itinerary-import lab remains available under Experiments.
- English model/free text; Indonesian controls. Budget, destination character, transport and walking controls record intent with explicit data limitations. They do not fabricate data or change routing.

## Verification status

| Check | Outcome | Evidence and boundary |
|---|---|---|
| Swift tests | **Passed: 57/57** | 36 previous tests plus 21 recommendation tests; test doubles do not prove inference quality. [Log](recommendations-2026-11-04/swift-tests.log) |
| Swift formatting | **Passed** | `swift-format lint --strict` on app, package source and tests |
| Final Simulator build/run | **Passed** | iPhone 18 Pro / iOS 27.2; build 4; [build log](recommendations-2026-11-04/simulator/buildLogPath.log) |
| Signed iOS build | **Passed** | Existing development signing configuration; [build log](recommendations-2026-11-04/device-build.log) |
| Simulator interaction | **Passed within fixture scope** | Both onboarding branches, search/select a fictional museum, preferences, retained own place, discovery, empty alternatives, export and reopening saved results after relaunch. [Snapshots](recommendations-2026-11-04/simulator/observations.json), [restored result](recommendations-2026-11-04/simulator/restored-result.json), [exported JSON](recommendations-2026-11-04/simulator/FM-Recommendations-09C0CD66-9F23-4C79-96E3-091FD362279C/recommendations.json) |
| Actual MapKit discovery | **Passed on Mac** | Public Jakarta coffee/bookstore searches; real coordinates and category identity only. Full first-run provenance is retained in [development/compact-live](recommendations-2026-11-04/development/compact-live/recommendations.json) |
| Actual local model | **Completed on Mac** | Nine frozen-input pipeline runs, plus three deterministic comparisons. All outputs retained. This is not iPhone inference evidence. |
| Install on physical iPhone | **Passed** | Build 4 installed in the same Foundation Lab bundle; existing routing app untouched. [Install log](recommendations-2026-11-04/install.log) |
| New physical-iPhone inference | **Completed with partial usable output, 2026-11-05** | Actual local model + live MapKit, 23.04 s, 10 retrieved/6 assessed/3 selected. Four of seven stages passed validation; two place assessments and the explanation fell back. [Report](recommendations-iphone-2026-11-05/REPORT.md), [run](recommendations-iphone-2026-11-05/run.json). The previous locked-launch [failure](recommendations-2026-11-04/iphone-console.log) is retained. |
| User benefit | **Not tested** | No participant observation, measured correction burden or actual trip |
| Routing preservation | **Passed for audited files** | 26 source/project hashes unchanged. [Audit](recommendations-2026-11-04/routing-preservation.json). No route engine changes or routing execution in the new flow. |

The new recommendation tests cover empty/own-place entry, impossible dates, contradictory interests/avoids, duplicate identities, outside-Jakarta places, category limitations, parking versus nature categories, foreign references, unsupported time-fact claims, unknown time basis, known closing conflicts, forbidden mutation fields, summary references, model fallback provenance, own-place retention, alternative exclusions and profile/history restoration. Existing tests retain timeout, cancellation, stale-revision, import and storage checks. No claim is made that Simulator inference or a unit-test double validates the iPhone model.

## Frozen regression series

[Manifest](recommendations-2026-11-04/evaluation/manifest.json), [summary](recommendations-2026-11-04/evaluation/summary.json), and all per-run JSON, Markdown, stdout and stderr are retained. The manifest freezes source, binary, three inputs and a public MapKit search snapshot before the series. Frozen source and binary hashes still matched after the series.

The later UI walkthrough added only a navigation link to reopen restored recommendations from the experiment screen. [Its source hash change](recommendations-2026-11-04/post-evaluation-ui.json) is recorded separately; package/model source remained unchanged. The updated app was rebuilt for Simulator and iPhone, reinstalled, and its restored-result navigation was observed. [Final build metadata](recommendations-2026-11-04/simulator/final-build.json) identifies that Simulator build.

| Scenario | Trials | Observed result | Wall time per model run |
|---|---:|---|---:|
| No own places; coffee/reading; frozen MapKit candidates | 3 | Same three positive selections each time. Generic market not selected. All six visit windows were `any`; real venue best times were not established. | 19.36–20.60 s |
| Three own fictional places; supplied hours/reading seat/photo preference | 3 | All places retained. Garden suggested `afternoon` from the soft afternoon photo fact. Museum/cafe remained `any`. | 9.00–9.89 s |
| Same own places; English correction from coffee to culture/photography, avoid coffee | 3 | Extracted interests culture/photography and avoid coffee in all three trials. Explicit pace control remained relaxed. Own places retained. Garden afternoon suggestion remained. | 9.79–10.57 s |

Across the nine runs, **48/48 stage outputs passed shape/reference/time-rule validation**. The maximum recorded input was 972 tokens per stage on the tested Mac. This is not 100% factual accuracy. Three deterministic comparisons completed in 0.031–0.040 seconds using the same inputs and frozen candidates. Their discovery choices remained unverified templates; own places remained selected by the user. This comparison measures pipeline behavior and time, not equivalent recommendation quality or a measured user advantage.

The repeated selected IDs, windows and extracted preferences matched within each three-trial group. All trials used greedy generation and shared the same model/runtime and inputs, so they are strongly correlated. These are three development scenarios, not a blind holdout, a new 24-case suite or independent samples from all possible users.

The later physical-iPhone run is separate from these nine Mac trials: it produced a tentative morning coffee suggestion where the Mac had returned `any`, and three of seven stages were rejected. This is evidence that the Mac's 48/48 structural result must not be generalized to the iPhone. The cross-device runs were not an exact frozen-input comparison.

## Remaining failures and limits

1. **Fit prose can overclaim.** In the frozen discovery run, a cafe explanation still associated it with reading despite only a cafe identity/category being supplied. The broad coffee match legitimately passed the native relevance gate; the unsupported reading detail was not caught by shape/reference validation. Category matching also does not prove that a bookstore offers seating to read.
2. **Explanations can strengthen a weak claim.** One corrected-preference summary described the museum as having “any time availability,” although `any` meant no preferred broad window and the fixture actually supplied opening hours. The UI retains sources and labels; free-form text still needs semantic review. A valid cited ID does not entail every sentence.
3. **Missing venue information remains a data gap.** The real MapKit identity/category results did not provide reliable venue visiting-time facts for this experiment. All 18 discovery place-time assessments across the three trials returned `any`. The model did not prove it could infer a useful best visit time from category alone.
4. **A soft fixture preference is not real-world verification.** The garden afternoon result follows a supplied illustrative photography preference. It proves use of supplied context, not accurate Jakarta golden-hour, weather or crowd prediction.
5. **No independent ranking or route optimization.** The app evaluates a bounded shortlist and takes the first positive assessments. It does not search every Jakarta venue, prove the best three choices, or prove the combined trip feasible.
6. **Budget, hidden gems and walking/access are unverified.** The onboarding can capture these preferences, but the tested data cannot verify them. They are explicitly disclosed rather than inferred as facts.
7. **Fallback remains limited.** Without usable model output, the app retains retrieved candidates and own selections, shows unknown fit/time and a deterministic summary. It does not pretend that templates are personalized model recommendations. The template's generic unknown list may still include an attribute supplied in the source disclosure; it is not an exhaustive per-fact explanation.
8. **Low-effort use is still a hypothesis.** Submission/correction counters record runs in this app, not every user gesture, deliberation or needed correction. No participant study was performed.

Earlier development attempts are retained under [development](../../../../docs/missing-evidence.md#missing-30df9b165dfd). One version confused retrieval timestamps with visiting-time evidence, causing all six assessments to be rejected. The final compact task input omits observation metadata while retaining it in stored provenance, explicitly states whether time facts exist, and uses field guides. Another version cited place IDs in the explanation; the final summary input avoids supplying those IDs and keeps evidence IDs separate. Raw failures were not repaired or counted as successful model output.

## How to use and reproduce

Open `C67FoundationLab.xcodeproj`, scheme `C67FoundationLab`. Normal launch uses the new preference-first flow. For a known example, search/select places or use the synthetic example under Experiments. The old imported routing example remains under **Lab lama**; it is no longer an entry requirement.

```sh
bash scripts/run.sh recommend --out /tmp/c67-live-recommendations
bash scripts/run.sh recommend --known --synthetic-search --out /tmp/c67-known-recommendations
bash scripts/run.sh recommend --input examples/recommendations/discover-coffee-reading.json --search-snapshot docs/verification/recommendations-2026-11-04/development/compact-live/recommendations.json --out /tmp/c67-replayed-recommendations
python3 scripts/evaluate-recommendations.py /absolute/path/to/fm-trip-eval /absolute/path/to/live-recommendations.json /absolute/path/to/known-recommendations.json /tmp/c67-fresh-series
```

`--fixture-ui` uses isolated synthetic UI data and no model inference. `--recommendation-smoke` uses a fixed example brief with the actual local model and MapKit in the iPhone app. Neither implies a user session or a real trip. All outputs remain proposals and cannot write to routing storage.

The next evidence needed is semantic review of the recorded reasons and summaries, then observation of users attempting place selection with the app. Reliable venue-specific best times additionally need trustworthy venue/experience facts; routing does not need to be reopened for these checks.
