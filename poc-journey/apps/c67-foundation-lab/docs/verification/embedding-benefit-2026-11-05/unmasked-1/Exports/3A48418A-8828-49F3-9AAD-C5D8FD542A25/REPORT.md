# Embedding benefit experiment
Case: city-history-literal; dataset: embedding-benefit-jakarta-2026-11-05-v1; policy: benefit-v1-bm25-1.2-0.75-combined-0.6-0.4.
Status: comparison_completed. Name-masked: false. Gate: true.
Direction: I want to learn the history of Jakarta from prehistoric times through colonial rule.

| Method | Top 3 area IDs | Expected-tie NDCG@3 |
| --- | --- | --- |
| category | bahari, bi, dialogue | 0.2608 |
| lexical | sejarah, joang, bi | 1.0000 |
| e5 | sejarah, seni-rupa, bahari | 0.8262 |
| combined | sejarah, seni-rupa, bahari | 0.8262 |

Authored relevance judgments; not an independent human assessment. Soft text is not a verified requirement. No routing, operational guarantee or reduced-user-burden claim.
Total: 0.007261037826538086 seconds; model stage: 0.005886077880859375.
Error: 