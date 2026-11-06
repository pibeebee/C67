# Incremental value of local embeddings — v0.7, build 10

Date: 5 November 2026, Asia/Jakarta. New screen: **05 · E5 — Nilai tambah E5**. Priority 3 was not started.

## Result and decision

The new experiment finds a **bounded incremental retrieval benefit for E5 when a soft direction paraphrases a source-backed activity or topic beyond the existing coarse categories**. It does not establish better recommendations for every profile, factual reasoning, user satisfaction or reduced input burden.

On 24 prospective authored ranking cases, mean expected-tie NDCG@3 was **0.4962 category, 0.8299 category + BM25, and 0.9770 category + E5 / the original 60/40 blend**. E5 beat the fixed lexical baseline on seven cases, tied on sixteen, and lost on one. The literal-query subset was almost tied; most additional value appeared in paraphrases. All six native safety cases behaved as expected.

A complete 30-case suite on the physical iPhone reproduced every case's recorded quality metric and all expected gates/states. Scores and some lower ranking positions differed between Mac and iPhone, so numerical and ordering identity across devices is not claimed.

The engineering recommendation is to retain native evidence rules and category scoring, with **E5 as an optional semantic tie-break after eligibility**, and a lexical fallback. The 60/40 blend did not outperform category-first E5 here; its weights are not validated as optimal. This closes the immediate question sufficiently to propose a bounded integration PoC next, while human relevance and data-maintenance validation remain open.

## Why this differs from experiment 04

The [previous experiment](PREFERENCE_QUALITY_REPORT_2026-11-05.md) measured coverage of supplied structured attributes and found six ties. That remains a valid finding. This follow-up asks whether text describing a more specific interest can distinguish places that share a coarse category, using richer supplied descriptions and a lexical comparison.

For example, both a maritime museum and a currency museum satisfy the coarse culture category. A direction about how people paid long ago should favor the published monetary collection even if it never says “numismatic”. This tests retrieval against given text, not the model discovering or verifying new venue facts.

E5's own [model card](https://huggingface.co/intfloat/multilingual-e5-small) specifies asymmetric query/passage prefixes and relative similarity ordering. The existing adapter preserves those prefixes, normalized 384-dimensional embeddings, the pinned model revision `614241f622f53c4eeff9890bdc4f31cfecc418b3`, and ONNX Runtime 1.24.2 CPU/int8. No model replacement, training or ranking-weight tuning was performed.

## Protocol, corpus and judgments

The [primary protocol](embedding-benefit-2026-11-05/PROTOCOL.md), implementation, corpus, queries and relevance judgments were [hashed and frozen](embedding-benefit-2026-11-05/manifest.json) before the first actual E5 inference on these new cases. The [frozen files](../../../../docs/missing-evidence.md#missing-a14bf40e081b) identify the evaluated version and runner binary. Mock-model engineering tests preceded the freeze.

The corpus has **19 area records across 16 actual Jakarta venues**. Twelve area records from experiment 04 are preserved in a new dataset snapshot; seven museum records add topic diversity. Source-backed English descriptions are manually paraphrased, with Indonesian UI. The new museum directory describes maritime, city-history, textile, puppet, visual-art and independence collections; the Bank Indonesia operator describes its monetary collection. See the [Jakarta government directory](https://www.jakarta.go.id/museum), [Bank Indonesia museum page](https://www.bi.go.id/en/layanan/museum-bi/default.aspx), [source audit](embedding-benefit-2026-11-05/sources.json) and [exact corpus/cases](../../Packages/PreferenceQuality/Sources/PreferenceQuality/Resources/embedding-benefit-v1.json).

There are thirteen distinct source URLs across retained and new records. Eight pages were fetched directly during this follow-up. Two new government/operator pages were read through the web tool after direct curl returned 403/reset. For those two entries, the stored hash explicitly identifies a **curation note, not downloaded source HTML**. Older MACAN, ASHTA and room-policy evidence is retained with its existing provenance. A rechecked old operator article does not establish current operation.

The 24 ranking queries form **12 intent pairs**, one literal and one paraphrased. Topics include currency, maritime heritage, fabrics, puppets, city development, independence, Dutch literature, focused reading, reading with a drink, historic coffee premises, creative publications and emerging artists. They are realistic authored scenarios, not recorded user requests. Positive judgments are grade 2 for direct source support and grade 1 for explicitly supported partial overlap, with source IDs and reasons. Unjudged candidates receive zero for this test; this is not proof that the real venue cannot meet the request.

The six safety cases cover same-area coffee/reading/quiet combinations, explicit avoids, unknown smoking status, known closure, expired programs and unconfirmed negation. Ranking cases mainly cover culture, reading and coffee; outdoor recommendation quality is not established by including park distractors in the catalog.

The same developer curated the data and authored the queries/judgments. This is a prospective frozen test, **not an independent blind holdout or human relevance study**. Six new records share a government source, and the paired queries share their intent. Public training-data overlap cannot be ruled out. The small set does not represent Jakarta.

## Comparison and metrics

All methods receive the same confirmed profile/direction and eligible records. The original native gate enforces required/avoided known facts within one area, source review age, known closures, expiry and identity exclusions. Text is a soft discovery direction and cannot convert unknown amenities into verified facts. For new museum cards, eligibility for discovery does not mean current admission is verified.

- **Category:** supported soft-feature fraction, as before.
- **Lexical:** category-first, BM25 tie-break with fixed `k1=1.2`, `b=0.75`, English stop words and no case-specific synonyms or stemming.
- **E5:** category-first, cosine tie-break using the supplied descriptions and native fact labels.
- **Combined:** unchanged experimental `0.6 × category + 0.4 × normalized cosine`.

The primary passages hide venue names, scope labels, addresses and IDs for every method. The UI still shows the resulting actual venue and sources. An unmasked secondary run is retained separately. This reduces direct name matching without eliminating possible curation or training-data bias.

NDCG@3 evaluates graded relevance near the top. Exact score ties use their expected gain over permutations, preventing alphabetical IDs from granting a lucky result to category. Supported precision@3 counts source-judged positive records divided by three; most cases have only one directly relevant record. Top-one relevance is a mean grade from 0 to 2. **None is a percentage of recommendation accuracy or user satisfaction.** An independent Python calculation reproduced every primary tie metric exactly and BM25 scores within floating-point error.

| Primary masked result | Category | Category + BM25 | Category + E5 | 60/40 blend |
| --- | ---: | ---: | ---: | ---: |
| Mean NDCG@3, 24 cases | 0.4962 | 0.8299 | 0.9770 | 0.9770 |
| Literal wording, 12 cases | 0.4962 | 0.9840 | 0.9855 | 0.9855 |
| Paraphrased wording, 12 cases | 0.4962 | 0.6758 | 0.9686 | 0.9686 |
| Supported precision@3 | 0.3380 | 0.4306 | 0.4722 | 0.4722 |
| Mean top-one grade, 0–2 | 0.6574 | 1.5000 | 1.9583 | 1.9583 |

E5 minus the fixed lexical baseline: **+0.1471 NDCG@3**, seven wins / sixteen ties / one loss. A fixed-seed 5,000-draw bootstrap over the **12 intent clusters** gave a descriptive interval **[+0.0475, +0.2591]**. This met the predeclared bounded-signal criterion of at least +0.05 gain, a positive lower interval and no safety regression. It is not population-level statistical validation.

Three separate Mac processes produced identical ranked IDs and expected states. Repeating the same cases/model does not create 72 independent ranking samples. Cached document encodings, concurrent build activity and varying process initialization prevent interpreting their times as a latency benchmark. Each process requested 27 query encodes and 167 document encodes; those adapter calls include cache hits.

After the primary results, a separate [follow-up protocol](embedding-benefit-2026-11-05/FOLLOWUP_PROTOCOL.md) specified two untuned lexical sensitivity variants. Querying only the direction, with or without native fact boilerplate, improved BM25 to **0.8423**. E5 remained **0.9770**: seven wins / fifteen ties / two losses, mean delta **+0.1347**. These use the same cases and are post-primary diagnostics, not independent confirmation. A stemmer, maintained synonym dictionary or finer structured taxonomy was not evaluated and could narrow the advantage. [Primary metrics](embedding-benefit-2026-11-05/METRICS.md), [JSON](embedding-benefit-2026-11-05/metrics.json), [sensitivity](embedding-benefit-2026-11-05/lexical-sensitivity.json).

## Examples, negative findings and device differences

For the paraphrase about historical payments and managing a nation's money, E5 ranked Museum Bank Indonesia first while the fixed lexical baseline missed it in its top three. Similar gains occurred for storytelling figures → puppet collections and a heritage home/shop → the documented old coffee shophouse. These are supplied descriptions matched to authored intent, not new facts produced by E5.

E5 lost the literal city-history case on NDCG: both methods put Museum Sejarah Jakarta first, but lexical retained a source-judged partial independence-history match in third position while E5 did not. The maritime paraphrase put the partially relevant city-history museum ahead of the directly relevant maritime museum. Scores are close, and higher similarity is not a reliable proof of meeting the whole request.

For the explicit silent-reading and reading-with-drink cases, native categories already carried the useful preference. All methods tied. E5 cannot determine noise, crowding, prices, seating, current opening or room permissions absent from evidence, and it is not a general negation interpreter.

The final 30-case iPhone suite passed **30/30 expected states/gates** and reproduced every case metric exactly. However, **12 full method/case rankings differed**, including **four top-three rankings across two cases**; E5 and combined count separately. Those differences involved lower-relevance ordering or equal-grade records, so this metric did not change. Maximum observed cosine difference was about **0.00373**. This illustrates the limits of treating aggregate metric parity as identical behavior. [Device comparison](embedding-benefit-2026-11-05/iphone-comparison.json), [phone suite](embedding-benefit-2026-11-05/iphone/series.json), [console](embedding-benefit-2026-11-05/iphone/suite-console.log).

The final physical target was iPhone 17 / iOS 27.0.1 (24A446). The first case in that suite took about 0.864 seconds inside the pipeline. This is a scripted inference suite over stored facts with a frozen source clock, not a physical UI walkthrough, service-latency benchmark or live MapKit search. The normal app comparison uses the current clock and keeps source-expiry checks. No new provider request or routing integration is included.

## Implementation and verification

The shared `PreferenceQuality` package adds Benefit contracts, BM25/tie metrics, a pipeline, isolated history/export and `embedding-benefit-eval`. The iPhone tab runs the same pipeline. Experiments 01–04 remain present, with unchanged prior package sources/resources. Existing tab labels were shortened to FM / Minat / Waktu / Cocok / E5 after observing overlap; internal screens remain intact. Normal launch still selects tab 02. New storage is `C67Benefit-v1`; harnesses use `C67Benefit-Tests`.

- **40/40** PreferenceQuality test functions passed: twenty new benefit tests plus twenty prior tests. Mock embeddings only establish engineering behavior.
- Prior regressions: VisitTiming **59/59**, TripIntelligence **57/57**, PreferenceLearning **29/29** passed.
- Signed v0.7 build 10 and Simulator builds succeeded. Two new UI flows passed, then the final complete Simulator suite passed **9/9**, including seven prior flows. [Final UI summary](embedding-benefit-2026-11-05/ui-verified-summary.json).
- Actual E5: three complete masked Mac runs, one unmasked ablation, and the final complete physical iPhone suite.

Initial failures are retained. A test first failed to compile because an integer `log2` literal was ambiguous. Dataset validation then exposed one missing candidate-to-source reference; it was fixed before freezing or any new actual inference, without changing judgments to fit model scores. A first complete UI run passed 8/9: the old quality test tapped an expansion control behind the floating tab bar. The captured hierarchy showed it remained closed. The test now scrolls controls above the bar and asserts expansion before inspecting the child. A new complete rerun verifies the correction. Direct source retrieval failures and the first CoreDevice connection/locked-device failures remain in the evidence; after Giovan unlocked the iPhone, the complete suite finished. After the complete `C67_BENEFIT_SERIES_END` result was captured, the attached devicectl session exited with code 1 and a CoreDevice/Mercury connection-invalidation error. The complete 30 results are retained; that transport termination does not establish an app crash or long-session device reliability.

See [verification directory](../../../../docs/missing-evidence.md#missing-28ff354bd3ad), [preservation audit](embedding-benefit-2026-11-05/preservation.json), and final UI logs/summary in that directory. No routing source, old planner storage, commit, push or publication was changed.

## Reproduce and try

From the Foundation Lab directory, prepare the existing pinned model assets if absent:

```sh
python3 scripts/prepare-preference-model.py
bash scripts/test-quality.sh
bash scripts/run-benefit.sh --all --out /tmp/c67-benefit-fresh
bash scripts/run-benefit.sh --all --baseline --out /tmp/c67-benefit-lexical
bash scripts/run-benefit.sh --all --unmasked --out /tmp/c67-benefit-unmasked
```

The evaluator defaults to the frozen source-snapshot clock; `--live-clock` uses current time and can legitimately reject expired facts. `--case currency-paraphrase` selects one case. `QUALITY_BUILD_PATH` can reuse a scratch build. Each run exports JSON/Markdown; `series.json` stores the complete series. The summarizer expects `masked-1`, `masked-2`, `masked-3` and `unmasked-1` under one evidence directory; repeats must be separate processes.

On iPhone, open **05 · E5**, choose a frozen case, then **Bandingkan empat metode**. Inspect per-method results, sourced descriptions and the labeled authored-case metric. History and JSON/Markdown export are available. `--benefit-ui` selects test storage; `--benefit-smoke` runs one current-clock case; `--benefit-suite` runs all 30 with the frozen evaluation clock and emits `C67_BENEFIT_SERIES_BEGIN/END`.

## What remains open

The useful supported role is semantic retrieval over richer supplied evidence, particularly when users phrase an interest differently from the text. A finer taxonomy or lexical expansion could also help. The experiment does not prove that E5 learns a person's preferences, removes onboarding choices, saves real task time or makes the best trip.

For a future priority-3 integration, retain the native gate and explicit unknowns, then pass optional ranked candidates to visiting-time and the already agreed routing engine. That integration still needs a shared, reviewed venue/area dataset and its own tests. Human relevance judgments, actual input/correction burden, broader venue coverage, fact refresh, memory/battery behavior and real trip observation remain untested here.
