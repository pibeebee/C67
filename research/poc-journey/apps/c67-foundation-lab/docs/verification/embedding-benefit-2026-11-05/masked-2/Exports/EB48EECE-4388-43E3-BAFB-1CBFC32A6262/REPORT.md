# Embedding benefit experiment
Case: dutch-reading-paraphrase; dataset: embedding-benefit-jakarta-2026-11-05-v1; policy: benefit-v1-bm25-1.2-0.75-combined-0.6-0.4.
Status: comparison_completed. Name-masked: true. Gate: true.
Direction: I am looking for novels from the Netherlands that I can browse in a language I understand.

| Method | Top 3 area IDs | Expected-tie NDCG@3 |
| --- | --- | --- |
| category | bdt-rbbj, bdt-silent, erasmus | 0.7103 |
| lexical | bdt-rbbj, bdt-silent, erasmus | 0.5000 |
| e5 | erasmus, bdt-rbbj, bdt-silent | 1.0000 |
| combined | erasmus, bdt-rbbj, bdt-silent | 1.0000 |

Authored relevance judgments; not an independent human assessment. Soft text is not a verified requirement. No routing, operational guarantee or reduced-user-burden claim.
Total: 0.006479978561401367 seconds; model stage: 0.005356907844543457.
Error: 