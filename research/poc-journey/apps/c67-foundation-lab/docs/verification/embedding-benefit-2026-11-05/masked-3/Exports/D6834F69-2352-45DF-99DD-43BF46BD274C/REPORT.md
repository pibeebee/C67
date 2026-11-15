# Embedding benefit experiment
Case: dutch-reading-literal; dataset: embedding-benefit-jakarta-2026-11-05-v1; policy: benefit-v1-bm25-1.2-0.75-combined-0.6-0.4.
Status: comparison_completed. Name-masked: true. Gate: true.
Direction: I would like to read Dutch literature and translations into English.

| Method | Top 3 area IDs | Expected-tie NDCG@3 |
| --- | --- | --- |
| category | bdt-rbbj, bdt-silent, erasmus | 0.7103 |
| lexical | erasmus, bdt-rbbj, bdt-silent | 1.0000 |
| e5 | erasmus, bdt-silent, bdt-rbbj | 1.0000 |
| combined | erasmus, bdt-silent, bdt-rbbj | 1.0000 |

Authored relevance judgments; not an independent human assessment. Soft text is not a verified requirement. No routing, operational guarantee or reduced-user-burden claim.
Total: 0.052471041679382324 seconds; model stage: 0.050122976303100586.
Error: 