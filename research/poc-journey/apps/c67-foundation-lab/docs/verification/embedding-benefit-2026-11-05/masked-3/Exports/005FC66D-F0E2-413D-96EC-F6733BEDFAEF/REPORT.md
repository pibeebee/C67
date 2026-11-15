# Embedding benefit experiment
Case: creative-coffee-literal; dataset: embedding-benefit-jakarta-2026-11-05-v1; policy: benefit-v1-bm25-1.2-0.75-combined-0.6-0.4.
Status: comparison_completed. Name-masked: true. Gate: true.
Direction: I want specialty coffee with design publications and a creative community.

| Method | Top 3 area IDs | Expected-tie NDCG@3 |
| --- | --- | --- |
| category | bakoel-cikini, bdt-cafe, bdt-rbbj | 0.5327 |
| lexical | newsroom, bdt-cafe, bakoel-cikini | 1.0000 |
| e5 | newsroom, bdt-cafe, bakoel-cikini | 1.0000 |
| combined | newsroom, bdt-cafe, bakoel-cikini | 1.0000 |

Authored relevance judgments; not an independent human assessment. Soft text is not a verified requirement. No routing, operational guarantee or reduced-user-burden claim.
Total: 0.014378070831298828 seconds; model stage: 0.010091066360473633.
Error: 