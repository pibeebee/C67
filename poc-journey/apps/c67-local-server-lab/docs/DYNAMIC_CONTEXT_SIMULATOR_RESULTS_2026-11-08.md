# Dynamic places, weather and opening hours — Simulator results

Executed 7–8 November2026 on the booted iPhone18ProMax/iOS27.2 Simulator, Xcode27.2, debug build, Mac-local loopback service. No homelab, production deployment, commit or physical-device validation. Source/final checks and retained execution logs are in the artifact directory (original local evidence, omitted from this publication).

## Result

The installed **C67 Context Lab** supports runtime Google place search and place selection, including GBK, without adding a venue to a Swift catalogue. Users explicitly confirm an independently searched Apple candidate and provide dwell, exposure and preferences. Google details supply operating sessions; WeatherKit and exact-departure Apple ETA feed scheduling. Provider keys remain on the Mac. Jakarta geography and1–6stops remain pilot bounds. The previous integrated app is preserved under its different bundle ID.

The wider campaign completed **54 controlled observations (18scenarios×3)** and **16live plans**:12primary observations plus four single-run diagnostic controls. Valid hard rules and matching user wishes are reported separately.

## Live benchmark

The table measures request submission through complete decode on the Simulator, after dynamic selections are prepared. It includes fresh per-plan weather acquisition and routing. **It excludes prior place search/prepare, user decision time, server startup/build time.** Route-only timing is separate. Each primary cell has3alternating15/5grid runs, exact ETA cache scoped to that plan, max64ETA calls, all requested visits retained, full dwell, return<=19WIB and total waiting<=30minutes. The single-run selective/beam controls are diagnostic, not equivalent repeated benchmarks.

Live date: **Tuesday10November2026**. Three stops depart11WIB; five stops depart09WIB. Three=National Museum90min, Bank Museum60min, Lapangan Banteng60min. Five additionally includes Arts/Ceramics Museum60min and Jakarta History Museum60min. Independent Google/Apple identity review selected the history museum at TamanFatahillahNo1 from four same/related-name results. Venue exposure is operator-declared, not inferred from ratings. Park preferred-start15–16 is a declared **soft operationalization**, stricter than the earlier user acceptance of14.45–15.45. This campaign has no new human approval of the outputs.

| Method | Stops | Grid | n | Client median (range), s | Route median, s | ETA calls/run | Waiting, min | Park visit | Preferred-start penalty, min |
|---|---:|---:|---:|---|---:|---|---|---|---:|
| beam | 3 | 15 | 1 | 22.203 (22.203–22.203) | 22.014 | 19 | 19.63 | 14:45–15:45 | 15 |
| beam | 3 | 5 | 1 | 39.523 (39.523–39.523) | 39.421 | 33 | 29.93 | 14:55–15:55 | 5 |
| firstFeasible | 3 | 15 | 3 | 8.395 (7.810–8.423) | 8.301 | 7,7,7 | 11.97 | 13:00–14:00 | 120 |
| firstFeasible | 3 | 5 | 3 | 27.572 (27.502–27.586) | 27.472 | 23,23,23 | 26.93 | 11:40–12:40 | 200 |
| selectiveOrders | 3 | 15 | 1 | 12.613 (12.613–12.613) | 12.437 | 11 | 11.97 | 13:00–14:00 | 120 |
| selectiveOrders | 3 | 5 | 1 | 27.529 (27.529–27.529) | 27.428 | 23 | 26.93 | 11:40–12:40 | 200 |
| firstFeasible | 5 | 15 | 3 | 9.534 (9.115–9.559) | 9.318 | 8,8,8 | 27.00 | 15:15–16:15 | 0 |
| firstFeasible | 5 | 5 | 3 | 26.391 (26.387–26.438) | 26.274 | 22,22,22 | 13.13 | 15:00–16:00 | 0 |

All16returned complete candidates and passed an independent arithmetic/operating-session audit. They remain `candidate_with_unknown_preferences`: weather during waiting/transfers and some contextual access information remain unmodeled. A complete candidate is not a claim of global optimum or full user accuracy.

### What the live comparison means

- **Three-stop first-feasible misses the afternoon request**: grid15 puts the park13.00; grid5 puts it11.40. Fine slots do not repair a method that stops after finding a feasible order.
- **Selective three-order search also misses it.** Its rotations omit the useful National→Bank→Park ordering. It is not a reliable quality escalation for this case.
- **Beam recovers National→Bank→Park**:11.15–12.45→13.15–14.15→14.45–15.45 with15minute starts, waiting19.63min. The park time matches the prior accepted example; this is consistency with earlier feedback, not new user validation. Grid5 moves the park to14.55–15.55 but costs39.52s and almost all waiting budget29.93min. Neither proves that a15.00start is globally infeasible.
- **Five stops first-feasible/grid15 is useful here**: Bank09.30–10.30→Arts10.45–11.45→History12.00–13.00→National13.30–15.00→Park15.15–16.15, waiting~27min, client median9.53s. Grid5 reduces waiting to13.13min and gives Park15.00–16.00, but median26.39s.
- ETA adapter wall accounts for more than99% of route wall in each primary live group. It includes network, token handling and the lab’s deliberate1.2second start spacing. This is **not** evidence of an Apple-mandated1.2second throttle. More fine-grid candidate branches cause22/23ETA queries vs7/8on coarse starts.

### Acquisition cost

Operator setup made six dynamic searches and six preparations for the origin and five destinations. Sum of those measured Mac-client requests: **5.712s**. This is a shared setup measurement, not a cold Simulator itinerary latency. GBK search/prepare was separately exercised and timed in the Simulator app. Adding a shared setup total to every live median would double-count it; a complete fresh-search user journey was not repeatedly benchmarked.

## Controlled weather and opening-hours benchmark

All controls traverse the Simulator→HTTP→same Swift context planner path, but use explicit **synthetic** hours/weather and fixed travel. Three-stop travel is15min per leg; five-stop travel is137s per leg. These CPU/control latencies cannot substitute for live provider latencies. Deadline18WIB, dwell60min/stop, waiting30min, beam12, max96synthetic ETA calls except the budget control.

| Scenario | n | Client median, s | Route median, s | Candidate runs | Sample order | Result |
|---|---:|---:|---:|---:|---|---|
| dry | 3 | 0.1876 | 0.1808 | 3/3 | gallery 09:15 → museum 10:30 → park 11:45 | candidate |
| rain_morning | 3 | 0.2114 | 0.2043 | 3/3 | gallery 09:15 → museum 10:30 → park 12:00 | candidate_with_unknown_preferences |
| rain_afternoon | 3 | 0.1951 | 0.1910 | 3/3 | gallery 09:15 → park 10:30 → museum 11:45 | candidate |
| rain_indoor | 3 | 0.1865 | 0.1829 | 3/3 | gallery 09:15 → museum 10:30 → park 11:45 | candidate |
| weather_missing | 3 | 0.2048 | 0.1999 | 3/3 | gallery 09:15 → museum 10:30 → park 11:45 | candidate_with_unknown_preferences |
| weather_stale | 3 | 0.2085 | 0.2017 | 3/3 | gallery 09:15 → museum 10:30 → park 11:45 | candidate_with_unknown_preferences |
| exposure_unknown | 3 | 0.2064 | 0.2029 | 3/3 | gallery 09:15 → museum 10:30 → park 11:45 | candidate_with_unknown_preferences |
| early_close | 3 | 0.0548 | 0.0518 | 3/3 | museum 09:15 → gallery 10:30 → park 11:45 | candidate |
| late_open | 3 | 0.0598 | 0.0566 | 3/3 | gallery 09:15 → park 10:30 → museum 12:00 | candidate |
| split_session | 3 | 0.1151 | 0.1116 | 3/3 | museum 09:15 → gallery 10:30 → park 11:45 | candidate |
| closed | 3 | 0.0085 | 0.0012 | 0/3 | — | needs_context |
| hours_stale | 3 | 0.0071 | 0.0011 | 0/3 | — | needs_context |
| required_conflict | 3 | 0.0114 | 0.0011 | 0/3 | — | needs_context |
| tight_deadline | 3 | 0.0132 | 0.0038 | 0/3 | — | no_candidate_within_search |
| eta_unavailable | 3 | 0.0061 | 0.0014 | 0/3 | — | incomplete_travel_data |
| budget_cut | 3 | 0.0065 | 0.0021 | 0/3 | — | no_candidate_within_search |
| five_grid15 | 3 | 0.0249 | 0.0216 | 0/3 | — | no_candidate_within_search |
| five_grid5 | 3 | 1.5046 | 1.4954 | 3/3 | exhibit 09:05 → gallery 10:10 → library 11:15 → museum 12:20 → park 13:25 | candidate_with_unknown_preferences |

- Morning rain moves the park to12.00; afternoon rain moves it earlier to10.30. Moving the activity indoors removes its visit rain penalty. The score uses the maximum hourly probability across the **whole visit**, not only arrival.
- Early close/split sessions move the museum first; late opening moves it last. A visit cannot straddle the midday closure. Closed, stale-hours and mandatory-time conflicts block before any ETA call. Unknown weather/exposure remains unknown, rather than becoming dry/indoor.
- Fixed-travel five-stop/grid15 has no physical schedule within30min waiting; grid5 does. An independent exhaustive reference confirms this fixture-specific distinction. Live grid15 nevertheless succeeds: finer slots are an option, not a universal requirement.
- The budget-cut control has a physically feasible schedule, but a declared two-call budget cannot validate a four-leg tour; it returns an explicitly truncated search with zero paid effort. A search cutoff never proves global infeasibility.

## Validation and corrections

**112 package tests passed; one opt-in live-provider test skipped.** Controlled audit:54/54 records,33complete candidates, all candidate weather penalties and finish times match the independently enumerated fixture optimum. The remaining21are declared blocking/cutoff controls; the physically feasible budget-cut cases are distinguished. Six deliberately corrupted outputs (dwell, wait, rain score, deadline, status and return identity) are rejected. Live audit checks every selected ID exactly once, full duration, exact departure/leg arithmetic, returned opening sessions, waiting, return, totals and preferred-start penalties.

A development regression exposed partial-beam ranking that rewarded leaving an outdoor goal unvisited. The correction adds an optimistic remaining-goal bound while retaining complete-candidate scoring and hard rules. The initial failing test is retained in `tests.log`; this is development-driven improvement, not untouched holdout validation. Legacy visit-request decoding retains its15minute default; the new app explicitly offers5minute starts.

Other fixes during integration: bundle the ignored local connection resource correctly; preserve benchmark checkpoints across app relaunches (observed12→14→16records); retain client-error400instead of masking it as provider502; dismiss the search keyboard and scroll lazily rendered Form rows before selection assertions; display actual opening intervals, unknowns, bounded-search warnings and unmet time preferences. Build/test attempts and their failures are retained instead of silently discarded.

UI evidence includes54controlled runs, live GBK search/preparation/selection, both live trip sizes and both diagnostic methods. See screenshot manifests and `.xcresult` bundles in the artifact directory. The final installed build is the separate C67ContextLab app.

## Recommendation and limits

**Use first-feasible/grid15 for the tested five-stop case; use beam/grid15 for the tested three-stop afternoon-priority case.** Choose5minute starts when the reduction in waiting or improved time fit justifies more computation. Three-order selective escalation did not solve the observed quality miss. These data justify a future context-aware escalation gate, but automatic first-feasible→beam escalation is **not implemented** here. The app exposes the methods and warns about unmet preferences.

The new dynamic path reads operating schedules and real forecast, but does not supply complete public sentiment, measured crowding, last-admission/reservations, field access verification, parking/transfer/waiting exposure or observed traffic ground truth. No LLM judging or automatic visit-duration inference was added. Google’s returned park24hour interval is provider evidence, not an independently confirmed gate-opening schedule.

Historical figures remain their original experiments. New live date, provider snapshots, identity review, slot configuration, budget and policy differ from older campaigns; **do not interpret old0/3 vs new3/3as a controlled algorithm-only improvement**. The clean comparisons here are paired15vs5within each live size and the one-variable controlled fixtures. n=3is descriptive; diagnostic controls have n=1.

The authenticated local Mac service remains available for the installed Simulator app. Prepared place identities expire15minutes after preparation; search/confirm again when expired. See [ContextHarness usage](../ContextHarness/README.md) for start/stop, rebuild and normal interactive use.

## Resource accounting and final state

All live attempts, including the final UI selection retry, consumed **18 Google calls,309 Apple HTTP calls and266ETA cells**, below declared campaign bounds60/900/720. The final HTTP negative checks returned401/400/400/400 and consumed no provider effort. Raw generated place-selection/context files were removed after export; sanitized technical observations remain. The final app was relaunched on the existing Simulator and the loopback service remains running for interactive use.

Final account snapshot:21percent of the5Hwindow remained. No further live expansion was started; evidence and reports were finalized.
