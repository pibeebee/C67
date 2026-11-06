# Follow-up diagnostics (after the primary results)

The primary frozen evaluation found higher E5 NDCG@3 than its fixed BM25 baseline. Before running further diagnostics:

1. Reproduce the Swift BM25 scores and tie metrics independently in Python. Then report two untuned lexical variants on the same existing cases: direction-only query on the same passages, and direction-only query on description text without native fact boilerplate. Keep category-first ordering and fixed BM25 parameters/stopwords. These are post-primary sensitivity checks, not new independent validation. No stemming, synonym dictionary, query-specific tuning or corpus changes. Report both, including whichever is strongest.
2. Run the entire 30-case frozen-clock suite on iPhone with the same pipeline, to detect device-dependent ranking changes hidden by a one-case smoke. This is a harness addition; do not change the frozen algorithm, corpus, labels or weights. Compare complete ranked IDs/metrics to Mac and disclose differences.
3. Shorten tab labels to stop the observed five-tab text overlap. Rerun all UI tests and inspect the resulting screenshot. Experiments and their internal screen content remain available.
