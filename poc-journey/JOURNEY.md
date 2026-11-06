# Experiment journey

This is a synthesis of the [CBL record](docs/source-records/CBL.md), retained project documentation, and captured technical evidence. Giovan directed the work and tested on his device with coding-assistant support; the initial external Foundation Models report is a teammate contribution. No participant outcomes are invented.

| Stage | Question and experiment | Result / decision | Continue reading |
| --- | --- | --- | --- |
| Hosted AI and research CLI | Can a model turn places and researched context into a feasible itinerary? | Keep audited AI/research attempts and their limitations; external providers and backend continuity became concerns | [CLI history](apps/ai-trip-planner/LEGACY_AI_README.md) |
| Deterministic CLI | Can scheduling/routing work without a hosted model? | Deterministic place/route/weather pipeline; preserve unsupported transit and infeasible results rather than fabricate travel time | [CLI v4](apps/ai-trip-planner/README.md) |
| Native routing | Which search strategy balances quality and provider cost? | Lock adaptive hybrid: validated baseline, selective insertion/multi-start local search, real final ETA validation | [Routing lab](apps/native-routing-lab/docs/NATIVE_ROUTING_LAB.md) |
| Native local/active lifecycle | Can accepted plans survive edits, failure and relaunch without a team backend? | Local persistence and reviewed manual active-trip proposals; keep version/cancellation/destination invariants | [P2 report](apps/native-routing-lab/docs/verification/NATIVE_TRIP_REPLANNING_P2_2026-11-04.md) |
| Jakarta and weather | Can real place identity and provider failures be handled honestly? | Jakarta/motor limits clarified; Open-Meteo fallback and separate Weather Lab; auth failure retained, later device success labeled by its evidence | [Jakarta](apps/native-routing-lab/docs/verification/JAKARTA_ROUTING_FIX_2026-11-04.md), [Weather Lab](apps/native-routing-lab/docs/verification/WEATHER_LAB_2026-11-04.md) |
| Initial teammate FM exploration | Can Apple's model replace the backend/action layer? | Unsupported Indonesian locale and weak action correctness on that setup; later schema correction separated adapter faults from model behavior | [Original teammate report](docs/source-records/foundation-models-teammate-report.md) |
| Foundation Lab | Can four small guided tasks assist preferences, discovery, time windows and explanation? | Model can assist bounded English tasks; native validation/fallback essential; no unsourced claim of a place's best time | [FM report](apps/c67-foundation-lab/docs/verification/RECOMMENDATIONS_REPORT_2026-11-04.md) |
| Preference fallback | Can structured local preferences and embeddings work without generative FM? | Source-supported gates, MapKit search, deduplication and optional E5 run locally | [Live preferences](apps/c67-foundation-lab/docs/verification/PREFERENCE_LIVE_REPORT_2026-11-05.md) |
| Feasibility priority1: time | What factual data can justify visit windows? | Published schedules, entry pauses and full-stay rules; forecast/solar advice remains conditional; extreme tests retained | [Timing](apps/c67-foundation-lab/docs/verification/VISIT_TIMING_REPORT_2026-11-05.md), [extreme tests](apps/c67-foundation-lab/docs/verification/VISIT_TIMING_EXTREME_REPORT_2026-11-05.md) |
| Feasibility priority2: quality | Does E5 add value beyond evidence/category/BM25? | First quality comparisons did not establish superiority; a later paraphrase study found bounded retrieval value with correlation/automation limits | [Quality](apps/c67-foundation-lab/docs/verification/PREFERENCE_QUALITY_REPORT_2026-11-05.md), [benefit study](apps/c67-foundation-lab/docs/verification/EMBEDDING_BENEFIT_REPORT_2026-11-05.md) |
| Feasibility priority3: integration | Do preferences, source-backed time, real ETA/weather and proposal state agree? | Actual three-place plan, +30m revision and impossible-deadline refusal; live Cikini English-name failure fixed with branch-scoped regression tests | [P3 full report](apps/c67-trip-integration/docs/VERIFICATION_REPORT_2026-11-05.md) |

## Decisions retained

- Core trip planning must remain usable without a team-operated AI backend. That does not mean online Maps/Weather services have become offline.
- Foundation Models never owns unchecked ETA or writes to the accepted itinerary. Native code owns constraints and reviewed state transitions.
- Missing information remains unknown; no silent substitution of duration, weather, source, branch or user-selected destination.
- Without a main destination, user selections have equal priority. New places remain proposals requiring review and schedule validation.
- Structured gates and E5 serve different roles. A high semantic rank cannot supply missing hours or satisfy an unsupported hard preference.
- Real API success, synthetic replay, source inspection, build success and user-reported success are different evidence layers.

## Numbering and historical integrity

Native lifecycle P0/P1/P2A/P2B belongs to an earlier roadmap. The later recommendation feasibility priorities1/2/3 mean sourced time, preference quality and whole-flow integration. Do not equate the two P2 labels or describe P3's pre-trip +30m action as active-trip tracking.

Earlier reports remain dated records, including failures. Publication redacts machine/private metadata and compacts compiler noise; original and published hashes are recorded separately. Where an earlier full source snapshot or external result bundle is unavailable, the gap is stated rather than reconstructed as a successful run.

## Next learning question

The current evidence supports bounded technical integration. It does not establish that recommendations consistently match real people with minimal effort. A next task should choose explicit user/relevance measures, broader sourced place coverage, latency/request budgets or real-trip reliability, and collect new evidence before changing production scope.
