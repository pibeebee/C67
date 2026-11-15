# Embedding benefit experiment
Case: colonial-coffee-paraphrase; dataset: embedding-benefit-jakarta-2026-11-05-v1; policy: benefit-v1-bm25-1.2-0.75-combined-0.6-0.4.
Status: comparison_completed. Name-masked: true. Gate: true.
Direction: I would enjoy a cup in a heritage building that used to be a home and shop.

| Method | Top 3 area IDs | Expected-tie NDCG@3 |
| --- | --- | --- |
| category | bakoel-cikini, bdt-cafe, bdt-rbbj | 0.5327 |
| lexical | bdt-cafe, bakoel-cikini, newsroom | 0.6309 |
| e5 | bakoel-cikini, bdt-cafe, newsroom | 1.0000 |
| combined | bakoel-cikini, bdt-cafe, newsroom | 1.0000 |

Authored relevance judgments; not an independent human assessment. Soft text is not a verified requirement. No routing, operational guarantee or reduced-user-burden claim.
Total: 0.009572982788085938 seconds; model stage: 0.008239030838012695.
Error: 