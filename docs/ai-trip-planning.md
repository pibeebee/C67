# Personal AI trip planning

Updated 30 October 2026. The bounded repository implementation follows [ADR-0008](decisions/0008-ai-trip-planning-direction.md) and [ADR-0009](decisions/0009-personal-planning-implementation.md). [Implementation evidence](tasks/ai-trip-planning-implementation.md) distinguishes code/build checks from shared deployment and real-provider validation.

## User flow and MVP choices

The traveller supplies one to six places, an explicit origin, visit durations, preferences, departure and finish-by instants, an IANA destination time zone and walking/driving mode. A trip spans at most 24 hours; an individual duration is bounded to 24 hours and may make the complete plan infeasible. Finish-by means the end of the final visit; a return-home leg is added only by explicitly selecting such a destination.

AI suggestions are optional candidates. Selecting one adds it to the draft; requesting suggestions never changes a saved plan. The hosted model proposes up to three orders, the scheduler checks orders and travel arithmetic, and the model selects/explains an evaluated candidate. The final result preserves every selected place. An infeasible proposal explains the conflict and cannot be applied. It never silently drops places or extends the deadline.

The native flow provides input editing, place search, requested current location, a marker map, source/context disclosure, proposal review, save, My Trips and active controls. Start is distinct from manual arrival. Arrival, completion and extension are manual commands; no GPS-presence or photograph authenticity claim is made. Directions open Apple Maps.

## Computation and sources

`server/planning/` is a separate Node/TypeScript API plus leased-job worker. Production has no npm runtime dependency. It calls an explicitly configured hosted model through an OpenAI-compatible endpoint, Apple Maps Server API for ETAs/search, WeatherKit REST for hourly/daily context and attribution, and a bounded read-only public HTTPS site reader. The default model endpoint is OpenRouter; an API key and model must be explicitly selected. No model is self-hosted.

The scheduler enumerates at most 720 orders over a directed matrix, ranks travel time and soft arrival-window penalties, then rechecks up to six shortlisted orders at their candidate departure times. Up to 72 route lookups, four concurrent matrix requests, two model calls (one for suggestions), 20-second provider requests, one website per selected place, two redirects, 128 KiB page responses and 6,000-character extracts bound the work. A job has a nine-minute processing budget, renewable 120-second leases and a ten-minute queue/lease lifetime with at most three attempts. This bounded search does not prove a globally optimal time-dependent route or the quality of an AI explanation.

Weather includes available hourly rain/cloud/temperature/condition context and daily sunrise/sunset. Sunset alone does not establish an exact golden-hour experience or unobstructed visibility. Unavailable/out-of-horizon/stale data remains explicit. Weather attribution includes provider legal links and an Apple Weather mark URL displayed by iOS. Browser data is untrusted evidence, never commands. The text reader pins a checked public DNS address, rejects local/private targets, credentials and non-HTTPS URLs, and does not execute JavaScript, log in, search the whole web or guarantee opening-hour truth.

Apple Maps traffic-aware ETA is an estimate, not a raw congestion feed. Forecast range, routing modes/coverage, venue identity, attribution, provider terms and onward transfer to a model need real-provider acceptance before distribution. Route caching is request-local; Maps access tokens expire and branding assets are cached in the provider adapter. Source extracts/estimates persist inside private job/proposal/event records rather than a shared provider dataset; production retention and permitted storage need an explicit policy.

## Persistence and active changes

The independent `personal_planning_trips` aggregate needs no creator/version ID. Private durable jobs store validated input/results. User RPCs derive ownership from verified traveller sessions; worker RPCs require service identity and a current lease. Direct writes are revoked. Receipt checks, trip locks and revision checks protect application and manual events; no model/network work runs inside these transactions.

A replan binds to the original input and current revision. While active, the server derives remaining visits. At a manually confirmed stop it holds that stop first and uses its remaining dwell time. En route it uses a supplied position no older than 30 seconds on the client, the last completed stop, or the initial origin. No automatic arrival or background tracking occurs.

Johan may extend D, request recalculation, review the changed arrival at C and choose whether to apply it. Preferred windows are soft preferences, so C remains present even if golden hour is missed. Completed visit rows and manual event history remain intact. A changed trip revision invalidates an outstanding proposal. Proposals expire after 15 minutes; replaying an already applied job returns its original response without another mutation. After an arrival/extension, the accepted future timeline remains an estimate until a new proposal is reviewed/applied.

The client persists the exact pending planning command per API/account in local preferences before submitting it; resume/retry uses the same request ID. This is recovery of one pending command, not a full offline trip store or durable outbox for every action. Account transitions clear private presentation state and session tickets reject late responses. Apply/event retries retain request IDs during the running app session.

## Compatibility and remaining decisions

OpenAPI 0.6 adds Planning HTTP and owner/worker RPC operations and four synthetic fixtures. Existing paths/schemas, creator-version payloads, migrations, original fixtures/seed and journal protection keep their meanings. The legacy catalog remains a developer example. Photo/journal/album integration, destination edits within an existing personal trip, skip/partial completion, undo, multi-day/transit, automatic recalculation and background presence remain separate work.

The code and synthetic verification do not deploy the new migration/service, provision Apple keys, select a paid model or establish actual factual support, cost, latency and user value. See [backend setup](../server/planning/README.md), [team handoff](team-starter.md) and the task evidence for the exact checks run and unresolved acceptance layers.
