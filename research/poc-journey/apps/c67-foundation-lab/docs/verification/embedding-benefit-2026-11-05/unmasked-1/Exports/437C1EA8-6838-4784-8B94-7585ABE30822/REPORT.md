# Embedding benefit experiment
Case: community-art-literal; dataset: embedding-benefit-jakarta-2026-11-05-v1; policy: benefit-v1-bm25-1.2-0.75-combined-0.6-0.4.
Status: comparison_completed. Name-masked: false. Gate: true.
Direction: I want an art space supporting emerging artists and community collaboration.

| Method | Top 3 area IDs | Expected-tie NDCG@3 |
| --- | --- | --- |
| category | dialogue, seni-rupa, wayang | 0.7103 |
| lexical | dialogue, seni-rupa, wayang | 1.0000 |
| e5 | dialogue, wayang, seni-rupa | 1.0000 |
| combined | dialogue, wayang, seni-rupa | 1.0000 |

Authored relevance judgments; not an independent human assessment. Soft text is not a verified requirement. No routing, operational guarantee or reduced-user-burden claim.
Total: 0.0070160627365112305 seconds; model stage: 0.005517005920410156.
Error: 