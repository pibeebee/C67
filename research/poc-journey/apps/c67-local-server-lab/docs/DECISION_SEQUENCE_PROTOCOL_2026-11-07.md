# Decision-sequence experiment — frozen before observations

Date: 7 November 2026, WIB. Scope: isolated local lab; original app/source preserved.

Question: does measuring quality and discovery first identify a useful next intervention, instead of adopting a new POI model on reputation?

1. Generate independent synthetic directed costs, FIFO time-dependent congestion, full-stay visit windows, 15-minute starts, return deadlines and missing-provider cases. Evaluate actual C and D code. Python independently enumerates every order (3–6 stops) under the same earliest-valid-start policy, audits returned legs and distinguishes oracle-unavailable from infeasible. These are not measured Jakarta road times.
2. Use development cases only to select a bounded alternative-validation policy if D has >5-minute or >5% elapsed gap, or misses an oracle-feasible case. Freeze that policy before the held-out split is run. Report both dev and held-out; no holdout retuning. Success requires zero hard violations, fewer material-gap/missed-feasible cases on holdout, and fewer ETA cells than C on median. Failure is a valid conclusion.
3. Profile live identity discovery for six existing pins and six places outside the integrated catalogue. Freeze query definitions before calls. Record returned field coverage without treating missing metadata as false or using the model as a fact source. Generic discovery queries are coverage observations, not human relevance judgments. If missing identity/facts are the blocker, defer reranker/model training and investigate that layer. No fabricated external-place itinerary.
4. Run a contemporary, bounded simulator HTTP campaign for supported catalogue inputs using the selected policy and D. ETA/WeatherKit/E5 remain real, same pins/date/constraints/pacing on both policies; preserve raw failures. A separate real-search run includes discovery in the timer. Fixed pins are labelled explicitly and excluded from any discovery conclusion. No current live C/D or external optimum guarantee.

Fixture split: deterministic generator, four stop counts, six cost/window families, two dev seeds and four held-out seeds = 48 dev and 96 held-out cases. Missing-provider cases included in denominator. No fixture is claimed representative of Jakarta. A seed split alone is not a city/domain generalization test.

Live budget: <=1000 HTTP provider calls, <=1200 ETA cells, single request at a time, original 1.2-second ETA start spacing; no pacing change mixed into policy comparison. Stop on 401/429, or two consecutive network/provider failures. Account remainder unknown. Temporary keep-awake only while running. No new servers/cloud/homelab, no cross-job ETA cache, no training on Apple data.

Primary metrics: hard violations; missed feasible (only when oracle has all costs); material-gap rate (>300s OR >5%); elapsed gap and travel/wait separately; oracle-unavailable separate; calls/cells; actual client latency; discovery identity coverage and metadata availability. Report failures and non-ready outcomes. Existing 5%/5min flags are engineering criteria, not established user acceptance limits. No p95/SLA claim from three repetitions. No field ETA accuracy or human recommendation relevance claim.

Original 66-file manifest and model identity are checked before/after. All policy, fixture and runner hashes accompany results. Optional model, road-engine, and pacing experiments are not automatic deliverables; the diagnostic branch determines whether they are warranted.
