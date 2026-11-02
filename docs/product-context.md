# Product context

Updated 30 October 2026 from the user's explicit direction and authorized repository implementation. See [ADR-0009](decisions/0009-personal-planning-implementation.md) and [task evidence](tasks/ai-trip-planning-implementation.md) for the local code and its verification/deployment limits.

## Current product direction

A traveller brings places they want to visit, preferences, a date, departure time and finish-by time. AI produces recommendations for optional additional places, visit order and timing, informed by location, routes, weather and place information. Recommendations can be recalculated during the trip. The traveller controls destination additions, replacements and omissions.

The underlying journey remains continuous with the earlier concept: intention → plan → visits → adjustments. The main change is the trip recommendation/planning engine. Recommendations no longer depend on creator-authored rundowns or someone's previous visit.

The selected framework focus is MapKit, Core Location and WeatherKit. AI is accessed through a backend API rather than a self-hosted model. The backend is intended to use a browser to research place context. The repository now includes a Node orchestration service, an OpenAI-compatible model adapter, Apple REST adapters and a bounded public-site text reader. A paid model/credentials, actual coverage and data-policy acceptance remain unconfigured/unverified.

“Full AI” refers to who produces recommendations. User input, provider estimates, sourced place facts, AI interpretation and actual events remain different types of evidence. Browser retrieval does not establish factual correctness by itself.

## Johan and active recalculation

Johan likes coffee and reading and has moved from Jogja to Jakarta for Academy activities. He already wants to visit a coffee shop in Cipete. He may select additional AI suggestions, then request an ordered plan for his time window. This is a design scenario, not a validated persona or field observation.

During the trip he wants to stay longer at D, while C is recommended around golden hour. Recalculation should explain the impact on arrival at C, the experience window, remaining visits and the finish-by time. Missing the preferred light does not automatically cancel C. Johan chooses whether to leave, stay or change destinations.

## Confirmed boundaries and open decisions

- Confirmed: user-selected places/preferences/date/departure/finish-by; optional additions; AI recommendations; recalculation during a trip; user control over destinations.
- MVP implementation choices: one to six places, explicit visit durations/origin, at most 24 hours, walking/driving, finish-by at the end of the last visit, reviewed proposal/apply and manual event-triggered recalculation. See the planning document for numerical/tool bounds.
- Open: actual provider capability/data policy, model choice and real cost/quality, automatic recalculation cadence, undo, multi-day/transit and expanded source strategies.
- Photos/albums, upload presence, completion/skip/partial trips, creator merge and public contributions have not been re-scoped for this engine. Existing implementations retain their current policies until separately changed.
- HealthKit/MusicKit are outside the currently selected framework focus. Walkability and non-mainstream places are not universal trip restrictions.

## Current implementation boundary

C67 now defaults to personal planning inputs, reviewed proposals, My Trips and manual active-trip changes. It includes domain/data adapters, a separate planning service/worker, OpenAPI 0.6 fixtures and an additive SQL aggregate. Mock output is synthetic; live providers are implemented as adapters but not acceptance-tested or deployed by this batch.

Existing creator/version data, Discovery, Auth/session, graph/query and private journal/media boundaries remain intact. New personal planning does not weaken journal guards or invent source identities. The new SQL/service deployment is pending; existing homelab evidence covers the previous implementation only.

## Sources and handoff

Read [AI trip planning target](ai-trip-planning.md), [ADR-0008](decisions/0008-ai-trip-planning-direction.md), [architecture](architecture.md) and [roadmap](server-roadmap.md). The source research workspace is `/Users/giovan/Documents/ChatGPT/C6 - Pisang Besar Balaraja`; its `CBL.md` and 29 October context/flow/engine/validation documents record the same direction in Indonesian.

The original [source manifest](source-manifest.json), older ADRs, source checksums and deployment/test evidence remain historical records. They do not assert that the new engine has been implemented or evaluated.
