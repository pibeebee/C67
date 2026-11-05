# Preference quality — v0.6, build 9

Date: 5 November 2026, Asia/Jakarta. Experiment: **04 · Kecocokan**. Policy: `quality-v2-category0.6-semantic0.4`.

## Result

The new experiment completes local profile → sourced, area-specific eligibility → category/E5/combined comparison → explicit feedback → reranking → history/export. It runs without Foundation Models or a hosted AI endpoint. The previous three screens and their package sources/resources are preserved.

The evidence supports **native filtering against supplied facts**, including combined requirements in the same area. It does **not** establish that embeddings or the combined score improve recommendations: all six completed soft-preference comparisons tied on the recorded source-attribute coverage measure. Human fit, reduced input burden and citywide discovery quality remain untested.

The final signed build ran actual E5 inference on the physical iPhone after it was unlocked. That run took **0.802 seconds** against the bundled catalog; it did not include a MapKit request. This is one scripted pipeline smoke test, not a latency benchmark or a physical-device UI walkthrough.

## What changed

`Packages/PreferenceQuality` contains the contracts, dated catalog, native rules, rankers, optional MapKit identity checks, storage, evaluation executable and tests. It reuses the existing `PreferenceLearning` E5 adapter and assets without modifying that package. New `QualityLabModel` and `QualityLabViews` implement tab 04. The app entry point adds the tab and smoke/test flags; normal launch still selects tab 02.

The screen offers presets, per-feature **Wajib / Diutamakan / Hindari / Tidak ditentukan**, optional text review, three ranking panels, reasons and sources, a specific liked aspect, candidate dismissal, history and JSON/Markdown export. Input changes cancel pending work and invalidate the displayed comparison; a revision check prevents older work from replacing newer input. Completed results survive switching tabs. Storage is isolated in `C67Quality-v1`; UI tests use separate test storage. Corrupt neighboring files remain recoverable evidence rather than being silently overwritten.

Text review is deliberately bounded. Recognized positive words can propose structured choices which the user must accept. Negation, corrections and unsupported directions require structured review. Confirmed text can inform semantic ranking, but it never overrides mandatory rules. This is not general natural-language understanding.

Liking a venue requires selecting one source-supported aspect. Other attributes of that venue are not learned automatically, and that venue is excluded from subsequent suggestions. Explicit avoidance overrides an earlier liked aspect. There is no implicit behavioral tracking or model fine-tuning.

## Actual places and provenance

The catalog contains **12 area records across nine venues**, supported by **11 pages retrieved on 5 November**. Multiple areas/pages from one operator are not independent samples. Each source has a URL, retrieval timestamp and SHA-256; claims reference source IDs. These are manually curated publications, not invented venue fixtures or on-site observations. Missing attributes remain unknown. Retrieval date does not establish when a service last changed.

| Venue / scope | Evidence used and limits |
|---|---|
| Baca Di Tebet: RBBJ, silent room, café | Separate scopes prevent merging café permissions with silent-room rules. RBBJ supports reading with permitted coffee drinking; the silent room supports reading and a quiet rule but prohibits drinks. Reading in the café remains unknown. [Home](https://bacaditebet.id/), [FAQ](https://bacaditebet.id/faq/), [terms](https://bacaditebet.id/terms/). |
| The Newsroom | Coffee, Wi-Fi and a smoking area are listed. Books for sale do not establish permission or facilities for reading on site; quietness remains unknown. The operator's MANUAL page dates to 2023, so it is not independent or current operational verification. [Operator page](https://manual.co.id/directory/the-newsroom/). |
| Bakoel Koffie Cikini | Coffee is supported. A narrative mention of internet use is not accepted as Wi-Fi evidence; reading remains unknown. [Operator website](https://www.bakoelkoffie.com/). |
| DiaLoGue | Art/culture supported; coffee and reading not inferred from the general venue identity. [Operator profile](https://dialogue-artspace.com/profile/about/). |
| Museum MACAN: gallery and café | Published closure blocks both areas pending access verification, despite regular visitor/café information. [Visitor information](https://www.museummacan.org/visit). |
| Hutan Kota GBK | Outdoor/nature supported for the park scope. [Jakarta government page](https://pusat.jakarta.go.id/kelurahan/kelurahan-gelora/fasilitas/fasilitas-taman-hutan-kota/taman-hutan-kota). |
| Ragunan | Outdoor/nature applies to park grounds, not every enclosed exhibit. [Official website](https://ragunanzoo.jakarta.go.id/language/en/). |
| ASHTA reading program | The published program ended on 31 December 2025. It is retained as an expired case and excluded from current verified recommendations. [Program page](https://ashta.co.id/program/free-reading-space/). |
| Erasmus Huis library | Reading/culture supported for its indoor library; coffee permission and a quiet policy remain unknown. [Official library page](https://www.netherlandsandyou.nl/web/indonesia/erasmushuis/library). |

“Coffee” in this experiment means **permission to drink coffee in that scope**, not a guarantee that coffee is sold, available or can be ordered at a particular seat. A quiet policy is not measured noise or crowding. The app requires source review after seven days; it does not automatically refresh facts or guarantee that a recent publication remains correct.

The source audit is [sources.json](preference-quality-2026-11-05/sources.json); exact claims and URLs are in the frozen catalog under [frozen-source](preference-quality-2026-11-05/frozen-source/Packages/PreferenceQuality/Sources/PreferenceQuality/Resources/quality-jakarta-2026-11-05.json). Full downloaded HTML is not bundled in this report.

## Ranking contract

All three rankers use the **same eligible area records**:

1. Reject dismissed/liked identities, expired programs and known blocked access.
2. Treat stale, unknown or conflicting required evidence as needing verification. A mandatory feature requires `yes`; avoidance requires `no`. Unknown is not proof of absence.
3. Require the requested combination within the same area record. Features from two rooms of one building cannot satisfy one combined request.
4. Rank eligible records using category support, E5 similarity, or the fixed experimental blend.

Category scoring is the fraction of soft preferences supported by affirmative claims. Mandatory requirements are eligibility rules, not extra score. E5 uses `intfloat/multilingual-e5-small`, revision `614241f622f53c4eeff9890bdc4f31cfecc418b3`, 384 dimensions, int8 ONNX Runtime 1.24.2 on CPU. The original pinned assets total about 135 MB. Text representations contain the supplied attributes; E5 does not generate venue facts.

Combined score = `0.6 × category + 0.4 × ((cosine + 1) / 2)`. These weights are fixed experimental choices, not calibrated satisfaction probabilities. E5 may reorder ties without demonstrating greater usefulness. Three area records may represent fewer than three venues.

Empty input gives `general_not_personalized`. Unsupported soft preferences with no mandatory requirement give `no_supported_preference`, with general category alternatives and no claimed personalized embedding result. No eligible match gives `no_verified_match`; unconfirmed directions give `preference_review_required`. Model failure retains an explicit `category_fallback`. Cancellation propagates rather than becoming an apparent model failure.

## Evaluation and findings

Twenty-four authored cases use the same dated candidates and expected eligible IDs for category and model runs. They cover combined activities, quiet areas, outdoor/nature, art/culture, explicit avoids, corrections, negation, unknown prices/amenities, specific likes, dismissal and cold start. They are development cases based on curated facts, **not a blind holdout or independent human relevance judgments**.

| Final result | Observation |
|---|---|
| Eligibility checks | 24/24 matched the authored expected sets and review states. |
| Actual E5 comparisons | 17; remaining cases: 3 no verified match, 2 review required, 1 unsupported preference, 1 general list. |
| Top-three IDs outside expected eligible sets | 0 across all methods. This primarily verifies the shared native gate, not E5 reasoning or universal factual accuracy. |
| Completed soft-preference comparisons | 6; combined better than category: 0, worse: 0, tied: 6 on source-attribute coverage. |

The diagnostic mean supported-soft-feature fraction was 0.3889 for each method. Its denominator is returned records × requested soft features; sparse sources and unknown attributes affect it. **This is not 38.89% recommendation accuracy or satisfaction.** Different orders do not establish a benefit on this measure.

For mandatory coffee + reading, only BDT RBBJ qualifies in this catalog. Coffee + reading + a quiet policy has no verified match; the system does not force three suggestions or infer that the café and silent room can be combined. Reading while avoiding coffee selects the known no-drinks silent-room scope. These conclusions concern supplied evidence, not the best venue in all Jakarta.

Development evaluation exposed a liked-art case with no remaining supported art candidate: v1 still emitted semantic alternatives. Policy v2 labels it `no_supported_preference` instead. Word-boundary matching also prevents “Jakarta” from matching “art”, and an explicit correction now overrides a previously liked aspect. The original gold IDs and 60/40 weights were not tuned to model outcomes. Earlier `model-series`/`model-final` runs remain alongside final `model-verified`; repetitions share sources/cases and caches and are **correlated development checks**, not independent trials. Cold and cached timings are not comparable benchmarks.

The [final manifest](preference-quality-2026-11-05/evaluation-verified-manifest.json) freezes source/data hashes and runner binary SHA-256. [Frozen source](../../../../docs/missing-evidence.md#missing-f163852e1dbf) and [final metrics](preference-quality-2026-11-05/evaluation-verified-metrics.json) identify the reported series. Later app-only expansion-control fixes did not change this package/data snapshot.

## Runtime and regression evidence

| Check | Result and boundary |
|---|---|
| PreferenceQuality | 20 Swift Testing functions passed, including parameterized positive text. Engineering embedding doubles test rules, fallback, cancellation and storage; they are not quality evidence. |
| Prior package regressions | VisitTiming 59/59, TripIntelligence 57/57, PreferenceLearning 29/29 passed. |
| iOS | Final signed v0.6 build 9 built and installed successfully. |
| Simulator UI | 7/7 passed on iPhone 18 Pro / iOS 27.2: three quality flows plus four previous preference/timing tests. Quality coverage includes source-specific combination, correction to no match, explicit like aspect, negation review, export, history/relaunch and tab preservation. |
| Physical iPhone | Final binary: actual E5, `comparison_completed`, 0.802 seconds. Mandatory coffee + preferred reading returned RBBJ, BDT café and Newsroom; only RBBJ has supported reading. No live map request in this smoke. |
| Actual MapKit on Mac | Three identity queries: RBBJ and café matched the same BDT provider pin; Newsroom returned no matching identity. This development run is recorded under policy v1; it is separate from the final v2 phone inference. |
| Static checks | Strict Swift formatting, shell syntax and Python syntax passed. |

The initial UI run passed 5/6 tests, with the new ranking expansion action failing; a targeted rerun still failed the like flow. The expansion was changed from a `DisclosureGroup` label to an explicit accessible button with visible expanded content. Two targeted tests and then the complete seven-test suite passed. Failure logs remain in the evidence directory. Device locking temporarily blocked the final rerun; after the user's unlock confirmation, final installation/inference succeeded. The attached smoke process was stopped after capturing its completed JSON; that termination is not an app crash.

The optional MapKit check is bounded to at most three sequential searches, 20 seconds each, without automatic retry. It checks supplied name words and a coarse Jakarta boundary. A provider identity match does not establish the exact branch, room facilities, admission or route feasibility; an absent result does not prove closure. Repeated scopes can cause repeated requests for one venue. The check does not silently alter the catalog or ranking. JSON/Markdown export includes current checks; previously saved ranking history is not retroactively enriched with them.

Evidence: [test and runtime directory](../../../../docs/missing-evidence.md#missing-52107c944fb7), [UI summary](preference-quality-2026-11-05/ui-summary.json), [screenshots](../../../../docs/missing-evidence.md#missing-d43d0f205ae3), [final iPhone JSON](preference-quality-2026-11-05/iphone/run.json), [console](preference-quality-2026-11-05/iphone/console.log), [preservation audit](preference-quality-2026-11-05/preservation.json). Of the 45 baseline source/config files audited, only the app entry point and project configuration changed; the generated Xcode project also incorporates the new files/dependency. The routing project was not modified.

## Reproduce and inspect

From the lab directory, obtain the pinned model assets if absent, then run:

```sh
python3 scripts/prepare-preference-model.py
bash scripts/test-quality.sh
bash scripts/run-quality.sh --all --out /tmp/c67-quality-model
bash scripts/run-quality.sh --all --baseline --out /tmp/c67-quality-category
bash scripts/run-quality.sh --case coffee-soft-reading --verify-map --out /tmp/c67-quality-map
```

`QUALITY_BUILD_PATH` can select an existing scratch directory. `--baseline` disables E5 but retains the same rules/candidates. Each output directory contains per-run JSON/Markdown plus `series-summary.json`. The summarizer expects the final-series layout (`model-verified` under its evidence argument); see `scripts/summarize-quality-evaluation.py`. The case file and final hashes must remain fixed when interpreting the recorded comparison. Regenerated runs receive new IDs and timings.

On iPhone, open **04 · Kecocokan**, choose **Kopi sambil membaca**, then **Bandingkan**. Inspect each method, source disclosure and candidates requiring verification. Use the explicit aspect menu for a like, or revise the structured controls and compare again. **Periksa maksimal 3 saran di MapKit** is a separate network action. `--quality-ui` selects isolated test storage; `--quality-smoke` runs the fixed coffee-mandatory/reading-preferred pipeline, emitting the completed run to the console.

## Decision and remaining work

Priority 2 is implemented and technically verified within this catalog. A sourced native eligibility layer is useful; the combined ranker remains an experiment with **no demonstrated improvement over category** here. Foundation Models are unnecessary for this specific pipeline, which does not establish replacement of all prior generative functions.

The main unresolved dependency is richer, maintained venue evidence. Nine venues cannot establish recommendation coverage across Jakarta. Unknown quietness, smoking exposure, prices, amenities, actual availability and changing access cannot be solved by increasing similarity alone. The next quality validation should add independently reviewed venues/cases and user judgments while keeping the baseline; record input, corrections, follow-up questions and task time under the same protocol. Current counters only instrument future observation and do not prove reduced burden.

Routing and visiting-time integration, real trip observation and a production data-maintenance workflow remain **not tested by this experiment**. No recommendation is automatically applied to the old itinerary, and no old planner storage is written.
