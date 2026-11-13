# Embedding incremental value — protocol v1

Written before any inference on this experiment's new corpus/cases, 5 November 2026 (Asia/Jakarta).

Decision: whether the existing pinned local E5 adds retrieval/ranking value beyond sourced native category rules, and beyond a lexical text baseline. This does not test user satisfaction or production readiness. Priority 3 remains unstarted.

Preserve experiments 01–04 and all original package data. Add a separately identified experiment using the existing E5 adapter, no model replacement, training, weight tuning or new routing.

## Inputs and comparisons

- Evaluator freezes its clock at one second after the latest source retrieval for reproducibility; `--live-clock` and the app use the current clock and retain expiry rules. A historical source clock is not current operational evidence.
- Dated real Jakarta venue/area cards, with manually paraphrased source-backed descriptions. Unknown amenities remain unknown. Known closure/expired-program records remain blocked.
- English queries and Indonesian UI, as previously agreed. Rank-test queries do not name their target venue.
- Author and freeze corpus, cases, relevance judgments, source references, methods and code before the first scored inference. No claim of independent or blinded relevance judgments: the developer also authors cases. The new set is prospective, not an external holdout.
- 24 ranking cases in 12 paired intent groups: literal and paraphrased wording. At least six additional safety cases cover structured avoids, combined same-area needs, unknown facts, closure, expiration and unconfirmed negation.
- Identical candidate eligibility for every method, using the existing QualityPipeline native gate. Text is a soft discovery direction, never proof of an amenity or operational availability.
- Category baseline: existing supported-soft-feature fraction. Lexical baseline: category-first ranking, with BM25 (k1=1.2, b=0.75) on the same sourced passages for category ties. Fixed stop-word list, no per-case synonyms or stemming.
- E5: category-first, cosine tie-break; combined: original 0.6 category + 0.4 normalized cosine. All methods receive the same confirmed profile/direction and documents. Existing E5 revision and query/passage prefixes remain fixed.
- Main evaluation hides venue names in text for all methods, to reduce name memorization; an unmasked secondary ablation is reported separately.

## Metrics and decision criteria

- Relevance 2 = directly supports the specific requested activity/topic, 1 = explicitly source-supported partial match, 0 = no supplied support. Each positive judgment cites its source and rationale. No negative judgments imply the real venue can never satisfy an activity.
- Primary: mean NDCG@3, with expected gain within exact score ties, so arbitrary alphabetical ordering cannot give category a lucky/unlucky result. Also record top-1 relevance, supported precision@3, per-case wins/ties/losses and actual ranked IDs.
- Compare E5 and combined to category AND lexical. Group the two related queries per intent for resampling; fixed-seed 5,000 cluster-bootstrap draws give descriptive 95% intervals. A small authored sample does not establish population generalization.
- A convincing bounded incremental signal requires >=0.05 mean NDCG@3 gain over lexical, positive lower bootstrap bound, and no native safety regression. Otherwise report mixed/no demonstrated gain; improvements only over category do not establish superiority to a competent text baseline.
- Run three independent runner processes for consistency/timing. Repeated same cases/model are correlated, not 3x sample size. Record corpus and query embedding counts, cache behavior, model metadata, hashes and stage durations. No cold/warm/device timing equivalence claim.
- Unit tests cover BM25, ties/metrics, provenance, safety, cancellation, fallback and storage. Build and observe the new iOS screen; run actual phone inference if accessible. Device unavailable/locked is reported separately from Mac/Simulator evidence.

## Deliverables

Frozen corpus/cases/provenance + runnable Mac evaluator + isolated in-app comparison + JSON/Markdown evidence + report and CBL checkpoint. Keep all failures and report both positive and negative findings. Human input burden, recommendation usefulness, broad Jakarta coverage and fact maintenance remain untested unless separately observed.
