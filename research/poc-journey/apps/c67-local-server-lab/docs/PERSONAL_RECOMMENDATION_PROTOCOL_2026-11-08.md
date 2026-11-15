# Personal recommendation PoC — target and prospective verification

Written 8 November 2026 (WIB), before the Simulator campaign. Local Mac lab only. Existing integrated app and other workspaces are preserved. This document records user decisions; it does not imply that a benchmark or human evaluation has passed.

## Accepted target

1. Recommend candidate places, let the user select them, then compute an itinerary.
2. Selections distinguish required visits and optional interests. Required visits cannot disappear silently.
3. Ask area, date and available time before recommending. First scope is one account owner.
4. Keep onboarding to explicit interests and pace; automatically reuse that profile on each trip.
5. Permit candidates with incomplete information, clearly labelled. Unknown hours are not invented opening intervals.
6. Learn from interactions, but only refine sourced facets within explicitly chosen interests. Cross-interest priority changes need explicit confirmation.
7. Keep a diverse list across available selected interests. Lack of evidence may limit representation.
8. LLM is mandatory. Use free models only; show errors/retry, never silently replace failed LLM output with category/E5 output.
9. Target about 20 seconds from submit to first selectable candidate list; itinerary computation is a separate timer.
10. If a free LLM approach does not help, this experiment has not met the quality goal; the LLM requirement is not silently removed.

## Implementation boundaries

- Server: Swift/Vapor, Google Places, area WeatherKit context, OpenRouter adapter, recommendation evidence validation, existing exact-departure Apple routing and new optional-subset wrapper.
- Device: persisted profile/events, pinned original E5 runtime, candidate matching, selection, explicit independent Apple identity confirmation, itinerary UI.
- Actual E5 execution is reported by model revision/runtime; CLI contract probes do not claim device inference.
- Server recommendation sessions expire after 19 seconds; client cancels the whole two-request operation at 20 seconds. First row appearance is recorded separately from decode/application time. No automatic retry resets that deadline.
- Initial operational bounds: Jakarta pilot, at most 9 acquired candidates, up to 6 displayed/selected places. Area is search context, not a verified subdistrict geofence. This is not a whole-city optimum claim.
- Real provider facts remain ephemeral in server/UI memory. No raw Google reviews are acquired or archived by this new normal path. Derived technical observations and source IDs are retained locally for audit; no publication is requested.
- Key stays in ignored `.env.local`. The original CLI `.env` is preserved. The app contains only its existing local service connection token.

## Explicit experimental policies

- Provider types supply broad category/facet support. Name alone is not proof of quietness, suitability for work or ideal visit duration.
- Area weather is sampled at an independently searched Apple area pin. It is not a verified venue-specific forecast and is not a hard exclusion for an unspecified user rain tolerance.
- LLM ranks all supplied candidates and returns IDs/reason codes/evidence IDs; code checks exact coverage, IDs, hours claims and source ownership before enforcing diversity. UI reasons are generated from validated structured claims, not unchecked model prose.
- The old E5 runtime is reused; the old learnedWeights policy is not reused. Shown events record actual card appearance, not all unseen returned cards. Open/save/select add small bounded facet affinity; skip/remove are recorded but not treated as dislike. No model weights are retrained. These learning weights are unvalidated policy, not demonstrated preference accuracy.
- Current optional subset policy compares explicit contextual penalties first, optional count second, finish time third; up to 12 subsets share one exact-departure ETA cache/budget. Required-only is attempted first when relevant. Bounded search/omissions are disclosed, never a global infeasibility proof.
- Pace does not silently prescribe waiting/dwell. UI displays and permits review of initial 60-minute dwell and 30-minute total waiting, which are engineering defaults, not inferred user preferences. Automobile/return-to-origin are disclosed pilot bounds.
- Missing mandatory hours produce an unresolved/conditional plan, not a fabricated complete timetable. Optional omissions retain reasons. Last entry, reservation availability, real access and queues remain additional-data gaps.

## Evidence already available before campaign

- Existing 7–8 November dynamic-context campaign: 54 controlled observations and 16 live plans; its results remain unchanged.
- Initial new package suite: 14 tests pass, covering within-interest learning, duplicate events, unknown hours, false LLM reasons, diversity, no LLM fallback, stale inputs, fixture/live separation, optional visits and shared ETA cap.
- Initial provider contract probes are development evidence: Liquid rejected a request; Xing hit 429; Nemotron returned zero-cost structured JSON but made an hours-label error. Stronger validation is mandatory. A subsequent server fixture contract request succeeded; it explicitly omitted device E5.

## Frozen campaign questions and cases

### Recommendation

- Authored profile: coffee/culture/outdoors, balanced. This is synthetic operator input, not a newly elicited personal profile from Giovan.
- Controlled inputs: balanced fixture and unknown-hours fixture, two repetitions each in the same app process to expose first-load versus reuse. Real E5 and real zero-price LLM; places/hours synthetic. Development controls, not untouched human holdout.
- Live input: Gambir Jakarta, Tuesday 10 November 2026, 09:00–19:00 WIB, same profile, three repetitions in one process without changing explicit interests. Facts/weather refreshed each recommendation; E5 may reuse its local passage cache. Actual model/provider/token counts/cost and every failure are retained.
- Primary timing: first row visible; also report submit→decode/apply, acquisition, E5 and LLM. Do not double-count overlapping stages or add one shared setup to every repetition.
- Success requires actual LLM success, zero reported model cost, allowed IDs, fact-supported reason codes, explicit unknowns and attempted category diversity. Under-20 seconds is separately evaluated; no p95/SLA or population accuracy from these small samples.

### Selection and itinerary

- Normal UI: inspect a candidate, choose required/optional, confirm its independent Apple match, select origin, review duration/waiting and compute live itinerary.
- Verify required IDs exactly once, no foreign visits, full dwell, exact leg departure arithmetic, opening-session containment, total waiting, deadline and return identity. Optional omissions must be explicit.
- Controlled tests force insufficient time, closed required place and a small combined ETA budget. Synthetic feasibility is not live traffic ground truth.
- Actual Apple selection names/addresses and pin differences are observed in UI evidence. Nearest pin is not field entrance verification.

### Profile and failure behavior

- Normal onboarding; interest/pace persistence after relaunch; event/facet persistence without adding categories.
- Invalid context is visible and cannot produce candidates. Unit controls inject actual recommendation-provider failure and forged/stale data, verifying no non-LLM fallback.
- Existing context weather/hours scenarios remain regression controls. Old manual screens are available under `--context-legacy` and Lab.

## Reporting and decision

Report implementation, controlled correctness, live provider operation, user fit and field validity separately. Human ranking/acceptance has not been newly supplied while the user is away; it remains pending and cannot be inferred from a UI test. Retain failed attempts, test fixes and bounded-search outcomes. All code/docs remain local; no commit, push or deployment is part of this task.

Historical source: [dynamic campaign](DYNAMIC_CONTEXT_SIMULATOR_RESULTS_2026-11-08.md). Blind-spot background: [BLINDSPOT.md](../../../docs/source-records/BLINDSPOT.md).

## Development amendments before final campaign

- A section-level accessibility identifier overrode child button IDs; the section identifier was removed. Actual UI results existed, but the harness could not locate them. Initial failed/interrupted xcresults are retained.
- A first live UI attempt read a previous candidate list as a new repetition. Actual saved records showed only two live requests, despite three loop iterations. Final harness waits for a new recommendation UUID; labels ending `:v2` identify the final campaign. The invalid-context negative case is not pooled as a live-provider failure.
- Diversity allocation now takes rounds across explicit interests, with LLM ranking within each round; learned facet signals cannot simply consume the remaining slots for one interest. Two additional policy tests cover allocation and empty explicit profiles.
- Independent audit normalized the case of the origin prefix as well as its UUID. A prior audit failed on string casing; actual return identity was unchanged and matched.
- The first live run overlapped part of the package regression run; it remains development evidence. Final provider measurements run after package tests finish.

- Visual identity review invalidated the development itinerary: Google Museum Sejarah Nasional (inside Monas) was matched by the automated harness to Apple Jakarta History Museum (Fatahillah), about 4,720 m away. Arithmetic passed but venue identity did not. This itinerary is excluded from final E2E evidence. Server and UI now reject nonfinite/negative or >500 m identity separation as a conservative pilot guard, not proof of same entrance. The normal UI supports an alternate independent Apple query. Final UI operator case chooses another issued museum rather than accepting this mismatch; `:v3` labels identify the final campaign. Identity names, addresses and separation are exported for independent review.

- A second visual review found a near-identity mismatch: TOMORO COFFEE Stasiun Gambir was routed to Kompormie Gambir about 41 m away. Distance alone is insufficient. Both server and UI now require distinctive name support after removing generic/address tokens, in addition to <=500 m. This conservative lexical policy can reject legitimate aliases and still is not field identity proof. A boundary/name regression covers this observed pair. The final operator case selects issued Kopi Kenangan, Taman Pandang Istana and an independently matchable museum.
- Free LLM HTTP 502 was observed. Normal UI scrolls errors into view and offers retry without fallback. The final harness allows one explicit user-style retry per case and records every attempt separately, including failures. Labels ending `:v5` identify this final campaign; earlier recommendations remain development/availability evidence and earlier mismatched itineraries are quarantined.

- The final name+distance guarded campaign is labelled `:v5`. Every explicit retry is a separate stored attempt; the live operator selection is limited to places actually present in that issued shortlist. Fixed names in this UI scenario are test choices, not an engine catalogue or recommendation whitelist. Runtime Google discovery remains dynamic.

### UI amendment v6
The v5 recommendation operations succeeded, but full-row XCTest taps could hit whitespace in plain card labels; a live request tap also did not trigger an operation. Cards now have a full rectangular hit area, operator taps target the leading content, and completion observes the new UUID on any instantiated card rather than assuming index 0 is instantiated. All v5 attempts remain retained; v6 is the final functional campaign.

### UI amendment v7
v6 passed profile persistence and invalid-input UI controls. A partially obscured recommendation button was reported hittable but did not start a new request. The operator helper now scrolls controls fully inside the safe viewport, and a timed-out waiter cannot return success on an old UUID. The issued coffee choice is Loko Cafe (Kenangan was not guaranteed in the six-place shortlist); this remains a scenario choice, not an engine filter. Final live run v7; v6 controlled observations retained.
