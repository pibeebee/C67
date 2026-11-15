# C67 Foundation Lab

**Current app: v0.7, build 10.** New screen **05 · E5 — Nilai tambah E5** compares sourced category matching, BM25, category-first E5 and the original 60/40 blend. The first four experiments remain available; tab labels are shortened to **FM / Minat / Waktu / Cocok / E5** to fit on iPhone. Normal launch still selects tab 02.

## Try experiment 05 — incremental semantic value

1. Open **05 · E5**, choose **Parafrasa: sejarah uang**, then **Bandingkan empat metode**.
2. Compare the four lists and inspect **Lihat bukti**. Text describes a soft interest; it cannot establish an unknown facility, operational availability or route.
3. Try **Kategori sudah cukup: membaca hening**, the impossible coffee/reading/quiet combination, or unconfirmed negation. Use the picker for all 30 frozen cases.
4. Export JSON/Markdown or reopen a completed result from history. New history is isolated from older screens.

The new corpus has 19 area records across 16 real Jakarta venues. Twenty-four prospective authored ranking cases form twelve intent pairs; six further cases check native evidence rules. Corpus, judgments and algorithms were frozen before actual inference. Mean NDCG@3 was **0.4962 category / 0.8299 BM25 / 0.9770 E5 and blend**; E5 versus fixed BM25: **7 wins, 16 ties, 1 loss**. An untuned post-primary lexical variant reached 0.8423. These are authored source-relevance metrics, **not recommendation accuracy or user satisfaction**. See the [complete benefit report](docs/verification/EMBEDDING_BENEFIT_REPORT_2026-11-05.md), [frozen protocol](docs/verification/embedding-benefit-2026-11-05/PROTOCOL.md) and [metrics](docs/verification/embedding-benefit-2026-11-05/METRICS.md).

```sh
bash scripts/test-quality.sh
bash scripts/run-benefit.sh --all --out /tmp/c67-benefit-fresh
bash scripts/run-benefit.sh --all --baseline --out /tmp/c67-benefit-lexical
bash scripts/run-benefit.sh --all --unmasked --out /tmp/c67-benefit-unmasked
```

The existing E5 model assets are reused; run `python3 scripts/prepare-preference-model.py` if absent. CLI evaluation uses a frozen source clock by default; `--live-clock` enables current expiry checks. Three separate processes reproduce the primary series. `scripts/summarize-benefit.py` expects `masked-1`, `masked-2`, `masked-3`, `unmasked-1` under one evidence folder. Two diagnostic scripts independently check lexical sensitivity and Mac–iPhone differences.

`--benefit-ui` selects isolated storage and tab 05. `--benefit-smoke` runs one current-clock case; `--benefit-suite` runs all 30 at the frozen clock and emits JSON markers. The full iPhone 17 suite reproduced all case metrics and expected states, with some lower ranking differences. This is stored-catalog inference, not live MapKit, a human walkthrough or proof of reduced onboarding burden. Verification: **40 PreferenceQuality + 59 VisitTiming + 57 TripIntelligence + 29 PreferenceLearning tests**, and **9/9 Simulator UI tests** passed. Priority 3 remains unstarted.

## Preserved checkpoint — v0.6, build 9

Experiment **04 · Kecocokan** (now the short tab label **04 · Cocok**) compares category, local E5 embeddings and a fixed 60/40 blend using the same original sourced Jakarta area records. The [preference-quality report](docs/verification/PREFERENCE_QUALITY_REPORT_2026-11-05.md) retains its six-tie result and original runtime boundaries. Experiment 05 tests a different question with richer descriptions; it does not rewrite that result.

## Try experiment 04 — evidence-based preference matching

1. Open **04 · Cocok**, choose **Kopi sambil membaca**, then **Bandingkan**.
2. Inspect the three methods and sources. Mandatory requirements and avoids require evidence in the same area; unknown amenities do not count as satisfied. Coffee means permission to drink it in that scope, not guaranteed sales or availability.
3. Correct **Wajib / Diutamakan / Hindari / Tidak ditentukan**, or select a specific supported aspect under **Saya suka aspek…**. Compare again. Free text requires explicit review; negation is not silently interpreted as a reliable exclusion.
4. Optionally **Periksa maksimal 3 saran di MapKit**. This checks provider identity only, separately from the curated facility facts. Use history and **Siapkan ekspor** for dated JSON/Markdown.

The dated catalog contains 12 area records across nine real venues, with 11 source pages retrieved on 5 November 2026. It is manually curated, not live citywide discovery. Facts require review after seven days. The existing E5 assets are reused; run `python3 scripts/prepare-preference-model.py` if they are absent. This screen does not need Apple Intelligence or Foundation Models.

```sh
bash scripts/test-quality.sh
bash scripts/run-quality.sh --all --out /tmp/c67-quality-model
bash scripts/run-quality.sh --all --baseline --out /tmp/c67-quality-category
bash scripts/run-quality.sh --case coffee-soft-reading --verify-map --out /tmp/c67-quality-map
```

`--quality-ui` uses isolated test storage and selects tab 04. `--quality-smoke` runs actual local E5 for mandatory coffee/preferred reading against the bundled catalog; it does not call MapKit. Quality profiles/history are separate from previous experiments.

Final evidence: 20 new logic-test functions, 145 prior package tests and seven Simulator UI tests passed; signed build 9 completed actual E5 inference on iPhone in about 0.80 seconds. All 24 authored eligibility cases matched expected sets; 17 ran E5 comparisons. The six completed soft-preference comparisons tied on source-attribute coverage: **the blend has no demonstrated advantage over category here**. These are development cases, not human quality or input-burden validation. See the report for raw results, earlier failures and runtime boundaries.

## Preserved checkpoint — v0.5.1, build 8

Tab **03 · Waktu** tests sourced venue facts → visit-time options, with eleven real Jakarta facilities and optional actual MapKit/Open-Meteo context. The [original timing checkpoint](docs/verification/VISIT_TIMING_REPORT_2026-11-05.md) and [extreme regression follow-up](docs/verification/VISIT_TIMING_EXTREME_REPORT_2026-11-05.md) retain their distinct evidence.

The extreme follow-up adds 31 Swift Testing functions (59 total), a 1,155-combination published-rule matrix, 308 monotonicity comparisons and 200 concurrent save requests. Policy v2 tightens canonical dates, evidence links, partial/ambiguous context, ranking priority and history integrity; supported v1 runs remain historical records. Source facts and acquired fixtures were not changed to make tests pass.

~~~sh
bash scripts/test-visit-time.sh
~~~

## Try experiment 03 — sourced visiting times

Open **03 · Waktu**, choose venue/date and adjust the assumed duration/availability. Tap **Hitung** in the toolbar or **Hitung dari fakta**. For the two sourced outdoor venues, choose lower-rain/daylight/near-sunset and tap **Ambil prakiraan aktual & hitung**. Sources, dated rules, admission restrictions and unknown attributes are disclosed. History restores a dated run; export shares JSON/Markdown.

The catalog was checked on **5 November 2026**. Published-case buttons retain their dates. The application requires recheck after seven days and does not automatically renew facts. Missing hours remain unknown; a temporary-closure announcement overrides regular hours. A Friday check-in interruption constrains entry without inventing a whole-venue closure.

The timing package/runner use neither Foundation Models nor E5. Durations are planning inputs. Actual sunrise/sunset and hourly probabilities do not establish crowds, ideal stay or golden-hour quality. This screen does not calculate routes or insert proposals into the planner. Its forecast adapter uses Open-Meteo; the separate routing app's WeatherKit setup is unchanged.

~~~sh
bash scripts/run-visit-time.sh --live --venue gbk --goal nearSunset --out /tmp/c67-visit-time
swift test --package-path Packages/VisitTiming
python3 scripts/verify-visit-sources.py --out /tmp/c67-source-audit.json
~~~

The --timing-ui flag opens tab 03 with isolated history and real dated facts; --timing-smoke also runs actual providers for a fixed GBK/lower-rain brief. [Source and scenario provenance](docs/verification/VISIT_TIMING_REPORT_2026-11-05.md).

## Preserved checkpoint — v0.4, build 6

Tab **02 · Preferensi** connects the full workflow: local profile → fresh MapKit search in Jakarta → native filtering → E5 ranking → feedback → fresh search. See the [live-integration report](docs/verification/PREFERENCE_LIVE_REPORT_2026-11-05.md).

On normal launch, choose **MapKit langsung · Jakarta** (the default). Pick an interest or write a short direction, then tap the comparison icon or **Cari dan rekomendasikan tempat**. The app retrieves fresh places, displays up to three semantic suggestions alongside a category baseline, and discloses queries, source timestamps and unknowns. Like/dislike a result, then use **Cari ulang dengan preferensi terbaru**. The source-bearing place selection remains in the local profile even if the next search returns a different set of places. A liked/disliked place is excluded from future suggestions.

At most three activity queries are built from explicit interests, liked-place tags and recognized Indonesian/English activity words. When none of these identifies an activity, E5 can select bounded search intents; this is labeled as an unverified intent. Empty input uses general discovery. Explicit avoids constrain known tags; text negation remains unreliable and needs the avoids controls. These are activity searches scoped to Jakarta, not arbitrary raw user text sent to the provider.

MapKit results are interleaved, checked against the existing Jakarta boundary, deduplicated and required to have a broad category/name activity match before ranking up to twenty candidates. The two ranking methods use the same eligible candidates. Unknown venue amenities, opening hours, prices and quietness remain unknown. A top result does not guarantee all requested activities are available together at one venue.

Each query has a 20-second deadline and no automatic retry. Partial query errors remain visible; complete failure/empty search has an explicit state and a retry action. It never silently substitutes the old snapshot for a new search. If E5 fails, fresh candidates can still be reviewed with the category baseline. Historical runs are explicitly restored snapshots.

```sh
bash scripts/run-preference.sh --live --out /tmp/c67-preference-live
bash scripts/run-preference.sh --live --profile /absolute/path/to/profile.json --out /tmp/c67-preference-live-profile
python3 scripts/evaluate-live-preferences.py /absolute/path/to/preference-eval /tmp/c67-new-live-series
```

`--preference-live-smoke` runs a fixed profile through actual MapKit and E5 in the iPhone app, with isolated storage. `--preference-live-fixture` is an explicitly labeled replay provider for UI tests; it is not evidence of live search. `--preference-reset` clears the selected test profile at launch. Both the synthetic catalog and dated MapKit snapshot remain selectable for reproducing v0.3 experiments.

## Preserved checkpoint — v0.3, build 5

Two independent tabs preserve the experiment journey:

- **01 · Foundation:** the existing Foundation Models preference/place/time experiment, including the older itinerary-import lab. Its implementation, prompts and storage are retained.
- **02 · Preferensi:** the new local-profile and E5 embedding experiment, selected on normal launch. It does not require Foundation Models availability or a hosted AI endpoint. The new [verification report](docs/verification/PREFERENCE_LAB_REPORT_2026-11-05.md) records results and limits separately.

## Try experiment 02

The shared `Packages/PreferenceLearning` package uses ONNX Runtime 1.24.2 and Hugging Face Tokenizers 1.4.0. Pinned public E5 int8 weights and tokenizer total about 135.4 MB; they are bundled locally for this PoC and excluded from Git. Before building from a fresh checkout, run:

```sh
python3 scripts/prepare-preference-model.py
```

The script verifies the pinned revision and checksums. The runtime validates those assets again on load. If model loading fails, the category comparison remains available and the semantic result is explicitly absent.

1. Open **02 · Minat** (experiment Preferensi). Choose the labeled fictional catalog or frozen MapKit snapshot.
2. Pick interests, supply a short Indonesian/English direction, or like up to six places. One liked place is enough to try the profile flow. Empty input remains a general list, never a claimed personal recommendation.
3. Tap the comparison icon in the top toolbar or **Bandingkan rekomendasi**. Both methods use the same eligible candidates. Likes and dislikes remove that specific place from future candidates; avoids filter known attributes. Repeating a like does not inflate its weight.
4. Inspect category and semantic rankings, source disclosures and unknowns. Profile edits invalidate the result; history and JSON/Markdown export are under the history icon.

Profiles/history live in a separate `PreferenceLearning-v1` directory, with profiles separated by catalog. Reset affects that catalog's choices, preserving run history and experiment 01. Actual interactions here are explicit likes/dislikes in this screen; visits and selections in the old lab do not silently train this profile.

Semantic similarity is not a probability or proof of personal fit. **Negation in free text is not a reliable exclusion rule**: use the explicit avoids controls. Missing venue attributes remain unknown. No route, visiting-time recommendation or weather output is generated in this experiment. Rich fictional fixtures and thin real MapKit data must be interpreted separately.

```sh
bash scripts/run-preference.sh --out /tmp/c67-preference
bash scripts/run-preference.sh --learned --out /tmp/c67-preference-liked
bash scripts/run-preference.sh --snapshot --out /tmp/c67-preference-snapshot
bash scripts/run-preference.sh --cold --out /tmp/c67-preference-cold
bash scripts/run-preference.sh --baseline --out /tmp/c67-preference-baseline
# For authored profiles and frozen regression outputs:
python3 scripts/evaluate-preferences.py /absolute/path/to/preference-eval /tmp/c67-fresh-preference-series
```

`--profile <json>` accepts `LocalPreferenceProfile`. `--preference-ui` uses isolated app test storage while still running the real E5 model. `--preference-smoke` runs a fixed Indonesian coffee/reading direction against the fictional catalog in the iPhone app and emits `PREFERENCE_LAB_BEGIN/END`. It is a pipeline smoke, not a user study. Existing smoke flags select tab 01.

## Preserved experiment 01 — Foundation Models

A separate SwiftUI iPhone PoC and macOS runner for preference-first place and visit-time recommendations. Users can start without an itinerary, ask the app to find places, or select their own places. The previous itinerary-import experiment remains available under **Eksperimen**. This project does not calculate or change routes.

**Status:** v0.2, build 4, experimental. See the [new-flow verification report](docs/verification/RECOMMENDATIONS_REPORT_2026-11-04.md). The [original report](docs/verification/REPORT_2026-11-04.md) and its 72-trial evaluation describe the older itinerary-import pipeline, not the new flow. Valid structure and source references do not prove factual prose or recommendation quality.

**Physical iPhone follow-up, 2026-11-05:** build 4 completed actual local inference and live MapKit in 23.04 seconds, marking three recommendations. Four of seven model stages passed validation; the remaining three displayed fallback output. See the [device report and raw evidence](docs/verification/recommendations-iphone-2026-11-05/REPORT.md).

## Requirements

- Xcode 27.2 / Swift 6.4.2 were used for verification. Package tools version: 6.2.
- Deployment targets: iOS 26.0 and macOS 26.0. Actual token counting is available from 26.4; earlier 26.x runtimes use the framework's context-limit errors without a fabricated token count.
- An eligible device with Apple Intelligence enabled and its model ready for real inference. Runtime checks use `SystemLanguageModel.default` and `supportsLocale(en_US)`.
- The tested Mac supports English and reports Indonesian unsupported. UI controls are Indonesian; model instructions, free text and generated prose are English. No automatic translation or hosted-model fallback is configured.
- MapKit live search needs its own network access. Local model inference does not make route/search/weather data available offline.

## Open the iPhone app

Open `C67FoundationLab.xcodeproj`, select the `C67FoundationLab` scheme and your Simulator or development iPhone, then Run. The checked-in project is generated from `project.yml`; `xcodegen generate` recreates it. The existing development-team setting is used without changing the old routing project.

1. Choose **Belum · pilihkan untuk saya** or **Sudah punya tempat**. For the latter, search by name and explicitly select a result. Up to six places are retained with equal priority.
2. Pick experiences and pace, or skip them. Budget, destination character, transport, walking tolerance, avoids, date and an optional English direction are under **Preferensi tambahan**. Unknown preferences stay unknown; pace defaults to balanced. The explicit pace control overrides text-derived pace.
3. Tap **Temukan rekomendasi**. MapKit retrieves real candidates; native code filters Jakarta and duplicates. A fresh model task assesses each of up to six candidates and suggests a broad visit window; a separate task explains the result. Up to three discovery recommendations are marked. Own places are retained even when inference fails.
4. Review sources and unknowns. Generic activity timing is labeled separately from supplied opening/experience facts. No clock timetable, route, ETA or finish time is produced.
5. Use **Cari tempat alternatif** or **Ubah preferensi**. Input changes cancel and invalidate pending output. **Detail eksperimen dan ekspor** contains prompts, rejected output, durations, JSON/Markdown sharing and local history.

**Simpan pilihan sebagai profil awal** stores explicit preference controls only. Places, the English direction and excluded alternatives remain trip-specific. The service date resets to today's Jakarta date when loading a saved profile; historical runs and fixtures retain their dates. Recommendations use a separate `Recommendations-v1` storage subdirectory. History never applies changes to the routing app.

Budget, popularity/hidden-gem and walking/transport controls capture intent. Their compatibility cannot be verified from category and coordinates alone; the app explicitly records this limitation. They are not fake price, crowd or accessibility filters. Neither native category matching nor model prose verifies quietness or reading seats.

### Fixture and device-smoke modes

- `--fixture-ui`: isolated test storage, synthetic search, deterministic templates, no model inference. Use this for Simulator interaction checks. Labels retain fixture provenance.
- `--recommendation-smoke`: isolated test storage, fixed preference brief, actual local model and MapKit search for the new flow. Prints `FM_RECOMMENDATIONS_BEGIN` / `FM_RECOMMENDATIONS_END`. It is not a user walkthrough or proof of a real journey.
- `--live-smoke`: isolated test storage, built-in synthetic itinerary, fixed English direction and coffee/reading choices, actual local model and MapKit search. The app prints a `FM_LAB_SMOKE_JSON_BEGIN` / `FM_LAB_SMOKE_JSON_END` block after saving the result. This is an automated pipeline smoke test, not a physical-device user walkthrough or a real journey.
- Normal launch: direct MapKit search and the actual on-device model when available. No location permission is requested; search is scoped to Jakarta.

## macOS runner

From this directory:

```sh
bash scripts/run.sh inspect
bash scripts/run.sh recommend --out /tmp/c67-recommendations
bash scripts/run.sh recommend --known --synthetic-search --out /tmp/c67-known-places
bash scripts/run.sh recommend --fixture --out /tmp/c67-recommendation-fixture
bash scripts/run.sh recommend --input /absolute/path/to/brief.json --search-snapshot /absolute/path/to/recommendations.json --out /tmp/c67-replay
# Previous itinerary-import lab:
bash scripts/run.sh pipeline --fixture --out /tmp/c67-fixture
bash scripts/run.sh pipeline --live-search --text 'Coffee and reading, at a relaxed pace.' --out /tmp/c67-live
bash scripts/run.sh pipeline --baseline --live-search --text 'Coffee and reading, at a relaxed pace.' --out /tmp/c67-baseline
bash scripts/run.sh pipeline --input /absolute/path/to/routing-report.json --live-search --out /tmp/c67-import
bash scripts/test.sh
```

`run.sh` builds the shared package locally. `recommend` defaults to **live MapKit** and a disclosed coffee/reading example brief. `--synthetic-search` supplies fictional candidates while retaining real inference; `--fixture` disables inference too. `--search-snapshot` replays the frozen `search` field of a previous recommendation run, preserving provenance. `--known` uses three explicitly selected fictional places with sourced fixture facts. `--input` accepts `RecommendationBriefV1`. Examples are in `examples/recommendations/`.

Each model task uses a fresh session, greedy sampling, at most 800 output tokens, a 20-second deadline and no automatic retry. The new flow uses up to three sequential MapKit queries, interleaves category results, retains up to ten unique in-scope candidates and evaluates up to six. English-text extraction is skipped when text is empty. A native category/name check prevents positive discovery recommendations with no broad match to requested activities. It is a coarse gate, not evidence of amenities. Invalid source references, unsupported time-fact labels and conflicts with known opening windows are rejected. Raw rejected output is retained separately; templates never silently become model recommendations. Cancellation ignores late results.

When run inside an external coding-agent sandbox, macOS model services may report `ModelManagerError 1008` despite availability being reported as available. The verification used explicitly authorized execution outside that sandbox. Do not interpret such a transport/runtime error as a model-language quality score.

## Data contracts and boundaries

`RecommendationBriefV1` starts independently of a route. `PlaceAdviceOutput` assesses one supplied candidate, so the model cannot choose or invent a new place identity. `DiscoveryExplanation` summarizes supplied assessments. `RecommendationRunV1` stores the brief, all retrieved candidates, runtime, raw/displayed outputs, sources, selected IDs, errors, timings and counters. The compact model input omits retrieval timestamps to avoid confusing observation time with visit-time evidence; full provenance remains in the run and UI. The result contains no route legs or ETA.

The following contracts describe the retained itinerary-import lab:

`TripContextV1` normalizes a native routing report or a saved snapshot containing `acceptedReport`. A version-1 normalized context can also be imported. It contains the original service date, WIB zone, stops, legs, known constraints, evidence, provenance and conflicts. Imports are limited to 5 MB and six stops. Malformed IDs, dates, chronology, known outside-Jakarta coordinates and inconsistent complete routes are rejected. Incomplete routes retain unknown finish/duration.

The public Jakarta example preserves the original provider probe's service date and does not refresh its weather/ETA. The synthetic example supplies illustrative opening hours and a soft afternoon photography preference; its venue names and figures are not real observations.

The four output types are `PreferenceExtraction`, `CandidateAssessment`, `VisitWindowProposal` and `ItineraryExplanation`. None can commit, apply, skip or mutate itinerary history. Specific visit windows require relevant supplied time evidence and cannot contradict known opening windows. Baseline candidate selection is search order, not a claim of personal relevance.

`ExperimentRunV1` retains runtime, prompt version, direction, raw/displayed outputs, validation failures, timings and provenance. Storage is local under `Application Support/C67FoundationLab`; fixture/smoke modes use a separate test directory. Export is explicit. Input-submission and correction-round counters are session observations, not evidence of user benefit.

The Jakarta operational boundary is the same frozen geoBoundaries/OSM mask used by the routing PoC: vintage 2017, ODbL 1.0, not a current legal/survey boundary. Attribution and provenance are bundled in `BOUNDARY-LICENSE.md` and `boundary-source.json`, and displayed in the app. [geoBoundaries](https://www.geoboundaries.org/), [OpenStreetMap contributors](https://www.openstreetmap.org/copyright).

## Reproduce the new-flow regression series

```sh
python3 scripts/evaluate-recommendations.py /absolute/path/to/fm-trip-eval /absolute/path/to/live-recommendations.json /absolute/path/to/known-place-recommendations.json /tmp/c67-new-recommendation-evaluation
```

The destination must be new. This freezes source, binary, inputs and a live-search snapshot, then runs three development scenarios three times plus one deterministic comparison each. It is a small regression smoke series, not a new 24-case evaluation or an independent semantic assessment. Repeated greedy generations are correlated. User-input reduction needs observed user sessions.

## Reproduce the original English evaluation

```sh
bash scripts/run.sh inspect
# Obtain the executable path printed by a Swift build, then:
python3 scripts/make-evaluation.py /absolute/path/to/fm-trip-eval
python3 scripts/evaluate.py /absolute/path/to/fm-trip-eval /tmp/c67-new-evaluation
```

The output directory must be new. The suite contains 24 new English cases, six per capability, repeated three times in fresh processes/sessions. `oracle.json` is evaluator-only and is never sent to the model. Source/input/binary hashes are frozen before each series; subprocesses have a 25-second outer watchdog. All outputs and failures are retained.

The cases were authored and inspected during development; the final v3 series is a regression evaluation after examining v1 and v2, not a blind holdout. Greedy repetitions are correlated. Automated checks cover selected exact fields, references and textual proxies; every response still needs independent human review for factual support and usefulness. `human-review.csv` has separate rows for two reviewers.

All three evaluation series are preserved. V2 adds explicit uniqueness and non-padding instructions for candidate lists. V3 uses compact candidate inputs, retaining every candidate, fact, source and timestamp while leaving coordinate filtering/display to the app. Neither version repairs model output after generation. New end-to-end schedule validation, live weather retrieval, crowds/prices verification, automatic tool selection by the model and user-benefit validation are future work.
