# Three-place context itinerary pilot — 7 November 2026

**Code validation update.** Subsequent review reproduced and corrected cache-budget pruning, partial-batch decoding and search-coverage/auditor defects. The figures below describe the original executions. [Validation findings and before/after evidence](BENCHMARK_CODE_VALIDATION_2026-11-07.md).

The pilot now connects real Google Places context to independently searched Apple identities, exact-departure Apple ETA and WeatherKit in the isolated Mac lab. **A fresh-process named-place pipeline produced an itinerary in 9.76 seconds.** In repeated route-only comparisons, first-feasible took 6.00s, selective orders 12.00s and beam 22.71s, returning the same schedule. Giovan accepted that schedule against his stated brief. These are distinct observations, not a general accuracy score or a production SLA.

## User intent and experiment assumptions

Actual user brief: **“Taman sore; museum fleksibel; menunggu maksimal30 menit.”** The experiment interprets that limit as total waiting. Operator-authored assumptions: Sunday8 November 2026,11:00 departure/19:00 return deadline, origin/return Hotel Indonesia Kempinski, Museum Nasional90min, Museum Bank Indonesia60min, Lapangan Banteng60min, automobile. Meals, queues, ticket availability, last entry, reservations and entry/exit walking are not modeled.

The initial numeric proxy was a soft **visit-start15:00–16:00** preference. It was deliberately not a hard requirement because the user did not specify an exact start. This proxy is narrower than the actual intention subsequently confirmed by the user.

[Prospective protocol and disclosed amendments](CONTEXT_PILOT_PROTOCOL_2026-11-07.md). All evidence (original local evidence, omitted from this publication).

## Live result and human feedback

| Visit | Start–end WIB | Dwell |
| --- | --- | ---: |
| Museum Nasional |11:15–12:45|90min|
| Museum Bank Indonesia |13:15–14:15|60min|
| Lapangan Banteng park |14:45–15:45|60min|

Return approximately16:00:04. Travel64.03min, waiting26.03min, dwell210min; total trip300.07min. All requested stops and full dwell retained, total waiting below30min, return before19:00. The same itinerary appeared in all12 live plans, including the elapsed baseline and weather diagnostic. This live case therefore **does not isolate a benefit of preferences/context over the baseline**; that causal contrast is supplied only by controlled fixtures below.

Giovan was shown the actual times, waiting and assumed11:00 departure, then answered: **“Sesuai; taman14.45–15.45 masih memenuhi maksud saya.”** Feedback record (original local evidence, omitted from this publication).

This supports acceptance of **one presented itinerary by its actual user**. The question was informed and unblinded; no randomized comparison was possible between identical schedules, and no population accuracy or completed-trip claim follows. The raw run reports retain their pre-feedback `pending` placeholder; the separate feedback record is the subsequent review evidence.

The engine assigned15 minutes of soft start-time penalty because14:45 precedes15:00. The user accepted the visit as an afternoon experience. This is evidence that **proxy penalty and user dissatisfaction are different measurements**. Do not tune every user's meaning of “sore” from this one response; future preference representation should distinguish desired start time from time spent experiencing the place.

## Measured computation speed

Primary campaign: one shared in-memory place/weather acquisition, three repetitions per method, alternating method order, no cross-job ETA cache. Maximum24 new ETA calls per plan; same hard rules, scoring, candidate places and slot grid. Actual work differs, which is the tradeoff being measured.

| Adapted context strategy | Complete route processing median | ETA/pacing wall median | Actual ETA cells/run | Returned schedule |
| --- | ---: | ---: | ---: | --- |
| First feasible order |6.00s|5.98s|5|same|
| Up to3 selective orders |12.00s|11.97s|10|same|
| Joint beam order+slots |22.71s|22.68s|19|same|

ETA/pacing wall is measured inside the adapter, including the lab's1.2-second start spacing, not just Apple network service time. More than99% of route wall time was in that adapter for these methods. Local processing outside it was about0.02–0.03s. This supports ETA acquisition/pacing dominating this pilot; it does **not** establish an Apple-mandated throttle or show that public network time alone caused the delay.

The named-place **fresh-process control** measured a complete single result:

| Stage | Duration |
| --- | ---: |
| Independent Apple/Google named search and identity matching |4.176s|
| Google details, WeatherKit and attribution |0.371s|
| First-feasible route processing including ETA/pacing |5.201s|
| Complete CLI pipeline |9.757s|

Stages ran sequentially in this control; the small remainder is setup/output work. “Fresh process” means no application place/ETA cache was carried over; external provider caching was not controlled. This is **one** observation, not a distribution. No E5 retrieval, open-ended discovery, server HTTP/client persistence, simulator rendering or UI interaction is included. Do not compare9.76s directly to older simulator/catalogue benchmarks as identical inputs or as a demonstrated percentage improvement.

Primary acquisition took4.436s search +0.729s enrichment and was shared across11 plans; its138.834s complete duration is the **whole campaign**, not latency for one itinerary. Primary report (original local evidence, omitted from this publication), fresh-process report (original local evidence, omitted from this publication).

## Controlled evidence about decision quality

Independent Python fixtures generate directed FIFO travel, three stops,15-minute starts, opening sessions, dwell, return and30-minute total-wait cap. Six families cover flexibility, afternoon park, rain, split hours, tight deadline and quietness unknown. The evaluator enumerates all admissible orders and slots without importing the Swift planner/scorer. Its optimum is limited to that discrete synthetic model.

An initial48-case campaign/360 observations (seed671107) exposed budget starvation: beam spent its cap before validating continuation/return. All completed outputs satisfied hard rules, but it often missed a feasible result. Initial results/source are preserved under `initial/`.

The fix reserves continuation/return effort and reduces retained states according to remaining actual-call budget. A paired rerun on the **same initial cases** changes beam's feasible returns at cap12 from0/20 to19/20, and cap24 from9/20 to20/20. This supports improvement in budget use on those cases; it does not guarantee all feasible plans will be found. A declared cap smaller than stops+return now produces a truncated result with zero paid calls, rather than making a request that cannot complete minimum tour validation. One legacy test's expected call count was updated for this intentional preflight behavior.

A revised prospective seed671108,48 cases (24 development/24 holdout), also adds both morning-dry and afternoon-dry controls. No policy was tuned on this revised holdout.20 holdout cases are feasible and4 are independently infeasible under the model. High-budget ablation uses the same beam/rules:

| Method objective/context | Returned feasible /20 | Full-brief priority gaps | Matched independent priority+finish+travel score /20 |
| --- | ---: | ---: | ---: |
| Hard rules +elapsed |20|5|15|
| Add user time preference |20|2|18|
| Add available context |20|0|20|

“Matched score” is a model check, **not human accuracy**. Four quietness cases preserve unknown, so agreement there does not prove the place is quiet. Some afternoon cases cannot meet a zero-penalty start while respecting the wait cap; best known compromise is appropriate under that fixture model.

Weather isolation: on two held-out cases with dry-morning/wet-afternoon patterns, adding forecast changes outdoor exposure penalty from90 to10 on the declared0–100 rain scale while retaining hard constraints. Two other rain cases cannot avoid the high-rain exposure within all bounds. Live park forecast ranged0–3% rain probability, so live results do not prove weather changes ordering.

At equal **caps** (not identical actual expenditure), full context on the revised holdout gives:

| Policy | ETA cap | Returned feasible /20 | Priority gaps among returned | Matched full reference score /20 | Median actual calls across24 cases |
| --- | ---: | ---: | ---: | ---: | ---: |
| First feasible |12|19|3|5|7|
| Selective orders |12|19|3|5|10|
| Beam |12|20|2|12|11|
| First feasible |24|20|4|5|7|
| Selective orders |24|20|2|6|15|
| Beam |24|20|2|15|20|
| Beam |48|20|0|20|28.5|

Extra budget can change which feasible compromise is found; first-feasible is not a quality guarantee. The selective policy remains imperfect. These are new adaptations sharing the context evaluator, **not historical D/E rebenchmarked**. Data are authored stress controls, not representative Jakarta demand. Full fixture audit (original local evidence, omitted from this publication), independent reference (original local evidence, omitted from this publication), paired budget control (original local evidence, omitted from this publication).

## Place evidence and limits

All three venues are outside the old five-venue catalogue. Three Google searches/details and four independent Apple searches resolve authored aliases and Jakarta area gates; the operator/harness confirms the mapping, not the user or an entrance survey. Google coordinates do not construct Apple ETA requests. Internal IDs map explicitly to provider identities. Place-name search success is not open-ended recommendation recall.

- Museum Nasional: current Google Sunday window08–20 agrees with the [official profile](https://linktr.ee/museumnasionalindonesia). Activity scope is interior galleries; access/transfers are not classified.
- Museum BI: Google returns08–12 and13–15:30. The [operator's page](https://bicara131.bi.go.id/kunjungan/) itself lists differing general hours and group sessions. Returned13:15–14:15 fits the overlapping published ranges, but individual admission and session applicability are not proven.
- Lapangan Banteng: provider resolves an all-day clipped interval. Prototype aggregate formatting renders this as`00:00–00:00`, meaning next midnight, not a zero-length window. The [Jakarta jogging page](https://www.jakarta.go.id/index.php/page/taman-untuk-joging-di-jakarta) lists06–20 while the [operator directory](https://flona.jakarta.go.id/taman-24jam) categorizes24-hour parks.14:45–15:45 lies within the sampled common bounds; full park hours/access remain unconfirmed.

Five reviews per venue were received; accepted temporal hints: Museum Nasional0, Museum BI2, park0. Hints are not crowd measurements or public consensus, and they do not affect this user's non-quietness brief. No raw real Google review/details corpus was persisted. WeatherKit and required attribution were available; waiting/access exposure remains unknown. A separate rain-preference diagnostic correctly reports that uncertainty.

## Verification and resource boundary

-102 regular tests passed:34 existing XCTest +25 context +8 new pilot tests +35 Swift Testing;1 explicit fixture benchmark skipped in the generic suite by design.
-360 revised observations independently audited;4 deliberately corrupted fixture outputs rejected.360 initial and360 paired-control observations also audited. A final360-run same-fixture execution produced identical result objects (timers excluded); it is regression repetition, not360 new independent samples.
-11 primary live results +1 fresh-process result passed independent leg/departure/session/dwell/wait/return arithmetic audits. Five live corruption types were rejected for each report. Published-hour checks are consistency/support checks, not real-world venue or ETA accuracy. Rain penalty was not independently rederived from archived provider data because raw forecast/details were not retained.
-12 Google calls total,131 AppleHTTP calls total,117 ETA cells total, below the frozen12/360/240 limits. No auth/quota failure or automatic retry. No further paid calls are needed to reproduce the analysis of saved results.
-66 original source/input hashes unchanged; original PlannerEngine A–E unchanged. New targets, adapter/CLI/scripts, context request/search changes and one context-test expectation are isolated to the lab. No production app/server deployment, simulator/iPhone install, homelab, commit or publication.
-5H usage snapshots:14% used at start,20%,26%,29% during work; account-wide shared usage, not a precise task billing measure. Available budget did not require truncating the pilot. Final checkpoint is recorded in verification metadata.

## Decision supported now

For this user's specific accepted schedule, first-feasible is the cheaper observed choice; extra validation did not improve the returned experience. This does **not** select it as a universal default. The fixture comparison still shows quality losses under cheap search.

The next design question is how to express the intended experience faithfully—visit start versus overlap with an afternoon period, explicit waiting tolerance, unknown context—and when to spend extra ETA on a preference conflict. A risk-triggered expansion can be investigated later against fresh held-out briefs. No new model or server deployment is justified by this pilot alone.

## Reproduce

Analyze saved results without API calls:

```sh
python3 scripts/context-pilot-fixtures.py audit artifacts/context-pilot-2026-11-07
python3 scripts/audit-context-pilot-live.py artifacts/context-pilot-2026-11-07/live
python3 scripts/audit-context-pilot-live.py artifacts/context-pilot-2026-11-07/cold-single
```

Generate a **new** fixture directory/seed before a new campaign, build`context-pilot`, then run its`fixtures INPUT OUTPUT` command and audit the resulting`observations.json`. Live reproduction uses private existing`.env.local` through`python3 scripts/context-pilot.py live NEW_DIRECTORY` or`single NEW_DIRECTORY`; these incur real provider calls, choose tomorrow relative to invocation and may return different data. Do not overwrite these artifacts or treat8 November as a perpetual live date.
