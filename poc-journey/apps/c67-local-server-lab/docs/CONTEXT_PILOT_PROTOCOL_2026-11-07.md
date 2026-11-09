# Context pilot protocol — frozen before runs, 7 November 2026

Question: can a bounded planner respect stated wishes without excessive computational latency? User's actual brief: **park in afternoon, museums flexible, total waiting <=30 minutes**. Other briefs are developer-authored controls, not claimed user wishes.

Scope: local Mac CLI end-to-end pipeline, Jakarta/WIB, automobile, three confirmed places, tomorrow (8 November for a run today). No production UI/app integration, no homelab. Assumed pilot departure 11:00, return by 19:00; Museum Nasional 90 min, Museum BI 60 min, Lapangan Banteng park 60 min. Start preference 15:00–16:00 is a soft interpretation of “sore”, made explicit for review; waiting cap is hard. Meals, queues, admission and reservations not modeled.

## Freeze and limits

- Preserve original A–E source/fixtures; modify only isolated context engine/request and new adapters/pilot scripts. Snapshot pre-change source hashes.
- Google hard cap 12 calls (search/details), Apple campaign cap 360 HTTP/240 ETA cells, timeout inherited 25 seconds, single active request, existing ETA start pacing 1.2 seconds. No automatic paid retry. Stop auth/quota errors. No raw Google reviews/details corpus persisted.
- First verify fixtures and core suite; then one live dataset discovery/enrichment and bounded repeated routing. Maximum wall duration 25 minutes for live command; external timeout terminates it.
- Read account 5H usage at start, midpoint and end. Initial observed usage 14%, remaining86%; weekly remaining42%. These are shared account percentages, not time left or API budgets. Reduce expansion if remaining5H <=25%; checkpoint/report rather than spend through the limit. No commitment to consume the available balance.

## Controlled comparisons

Six families: flexible, park afternoon, outdoor rain, split operating sessions, tight deadline, quiet evidence missing. Generate fixed seeded development and held-out cases with three stops, independently generated directed/time-dependent FIFO travel, 15-minute visit starts and dwell. Preserve unknowns. Python evaluator independently enumerates all admissible orders and slots under its documented fixture objective; no import of Swift scorer or planner. Optimum applies only to these fixtures.

Ablation: same beam search/budget, hard rules+elapsed; then user goals; then goals+available context. Evaluate all outputs against the full declared brief, even when a method ignores part of it. Report hard violations, known-preference penalties, unknown goals, feasible misses, wait/travel/dwell/elapsed and processing time separately. Do not label these synthetic metrics human accuracy.

Strategy experiment after ablation: shared context/goals/rules; first feasible fixed-order scheduling, up to three selective orders, and joint beam order+slot. New adapted policies are **not historical D/E**. Shared actual-call cap grid; cache only exact from/to/departure within an operation. Report actual calls as well as caps, because equal caps need not imply equal spent budget. No tuning on holdout; any fix motivated by holdout requires a new holdout.

Negative controls: corrupt returned dwell, waiting, ETA or preferred-time penalties; independent auditor must reject. Include incomplete provider, too-small budget, hard preferred time, stale snapshots, unconfirmed identity and malformed/missing mapping tests. Unknown != impossible; search truncation != global infeasibility.

## Live and human evaluation

Independently search Apple and Google using authored names. Require an unambiguous alias/area match; retain identity evidence and reject unresolved choices. Verify sampled official hours/exposure, report disagreements without silently calling a schedule ground truth. Google coordinates never become Apple routing coordinates. WeatherKit context includes attribution and freshness; no fallback/invented forecast. Reviews remain weak indications; missing useful hints remain unknown.

Live primary: full actual brief versus elapsed baseline with identical known mandatory constraints; compare firstFeasible/selectiveOrders/beam within bounded caps. Alternate order for repeated methods, no cross-job ETA cache, one shared in-memory place/weather acquisition. Route processing includes ETA pacing; data acquisition and complete CLI execution measured separately. Three repeats if remaining budget permits; no p95/SLA claims.

Prepare randomized method-masked alternatives from actual outputs, ask user acceptance/reasons/corrections. Actual answers must be recorded separately; no simulated approval. Preparing cards does not complete human validation. Live audit checks returned leg continuity, dwell, departure, return, waiting and sourced bounds; this does not prove travel/venue conditions in the field.

## Sources inspected before run

- Museum Nasional official profile: https://linktr.ee/museumnasionalindonesia (Tue–Thu08–18, Fri–Sun08–20, Monday closed).
- Museum BI operator: https://www.bi.go.id/id/layanan/kunjungan-bi/default.aspx (08–16 Tue–Sun; other sources differ, report any conflict).
- Park operator directory https://flona.jakarta.go.id/taman-24jam ; Jakarta publications show conflicting historical hours, so use only common visit bounds and mark full operating schedule unconfirmed.

This protocol is prospective for this pilot. Existing results remain in their original reports; this file contains no new outcomes.

## Prospective amendment after initial fixture run, before revised run/live

Initial360 observations/48 cases (seed671107) are retained under `artifacts/context-pilot-2026-11-07/initial`. They exposed ETA-budget starvation in beam before final return validation. Fix reserves continuation/return effort and bounds retained states by remaining calls. This is an exploratory, evidence-driven change; initial holdout is no longer untouched for this revision. Revised evaluation uses a new seed671108 and retains all three methods/caps; no further policy tuning on its holdout. Rain controls now include both morning-dry and afternoon-dry patterns because the initial one-direction pattern did not isolate weather effect. This dataset extension is disclosed, not a retrospective claim about initial weather benefit.

## Prospective cold-pipeline control after primary live campaign

Primary live completed using6 Google calls/119 AppleHTTP/112 ETA cells, with data shared across11 plans. Route-only timings are not fresh end-to-end timings. Add exactly one fresh firstFeasible pipeline (3 Google searches+3 details,4 Apple searches, WeatherKit+attribution, cap24 ETA) in a new process, `single`. This consumes remaining6 Google allowance and stays below aggregate240-cell/360-AppleHTTP caps. Same day11–19/brief/dwell, fresh provider responses; identity/gap drift reported. This is a one-observation cold acquisition control, not a new performance distribution. It cannot establish a direct same-input comparison to earlier catalogue/simulator campaigns.
