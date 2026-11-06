# Embedding benefit experiment
Case: city-history-paraphrase; dataset: embedding-benefit-jakarta-2026-11-05-v1; policy: benefit-v1-bm25-1.2-0.75-combined-0.6-0.4.
Status: comparison_completed. Name-masked: true. Gate: true.
Direction: Help me understand how this city developed from early settlements into the capital.

| Method | Top 3 area IDs | Expected-tie NDCG@3 |
| --- | --- | --- |
| category | bahari, bi, dialogue | 0.2608 |
| lexical | sejarah, bahari, tekstil | 0.8262 |
| e5 | sejarah, bi, tekstil | 0.8262 |
| combined | sejarah, bi, tekstil | 0.8262 |

Authored relevance judgments; not an independent human assessment. Soft text is not a verified requirement. No routing, operational guarantee or reduced-user-burden claim.
Total: 0.006862998008728027 seconds; model stage: 0.005505084991455078.
Error: 