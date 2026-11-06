# Embedding benefit experiment
Case: city-history-literal; dataset: embedding-benefit-jakarta-2026-11-05-v1; policy: benefit-v1-bm25-1.2-0.75-combined-0.6-0.4.
Status: comparison_completed. Name-masked: true. Gate: true.
Direction: I want to learn the history of Jakarta from prehistoric times through colonial rule.

| Method | Top 3 area IDs | Expected-tie NDCG@3 |
| --- | --- | --- |
| category | bahari, bi, dialogue | 0.2608 |
| lexical | sejarah, bi, joang | 0.9820 |
| e5 | sejarah, bahari, tekstil | 0.8262 |
| combined | sejarah, bahari, tekstil | 0.8262 |

Authored relevance judgments; not an independent human assessment. Soft text is not a verified requirement. No routing, operational guarantee or reduced-user-burden claim.
Total: 0.007339000701904297 seconds; model stage: 0.006027936935424805.
Error: 