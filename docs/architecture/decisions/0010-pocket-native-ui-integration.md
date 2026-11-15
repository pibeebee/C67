# ADR 0010: Connect the native UI to Pocket Engine

> Superseded on 14 November 2026: the user removed geographic restrictions and catalog dependence, and required request-time web research plus Luna on the native first-itinerary path. See [the runtime implementation](../tasks/pocket-runtime-visit-resolution.md). Earlier behavior and checks below are historical.

Status: Accepted — user requested pulling origin and connecting the existing UI on 12 November 2026.

## Current amendment — 15 November 2026

The user authorized integration of reasonable Luna ordering after the bounded
capability tests. New Pocket itineraries use asynchronous `/v1/order` jobs.
All selected IDs must appear exactly once; no catalog, geographic gate, six-stop
cap, opening-hours research, ETA matrix or timed solver is required. The server
supplies optional Open-Meteo context and Astral light windows; Luna suggests
activities, duration ranges, dayparts, reasoning and source references. Unknown
estimates stay null. Numeric weather/light facts come from bound provider/code
records, not model prose. No substitute result is generated after failure.

The existing native cards show untimed recommendations, preserve edits and save
locally. Renaming does not regenerate the model answer. Jobs retain request IDs
across reconnection; failed model operations require explicit new requests.
Legacy timed trips keep their existing path and strict HTTP DTOs. The stored
`feasible` flag means the untimed proposal is usable by the review/apply flow;
it does not establish travel or venue feasibility. Tomorrow is an app candidate
for forecast retrieval, not a model-optimized date or guaranteed visit schedule.
WeatherKit REST, new Hi-Fi adjustments and shared deployment are separate work.
See [integration task](../tasks/pocket-reasonable-order-integration.md).

The older decisions below describe historical timed planning behavior.

## Context

The Hi-Fi UI uses C67Domain planning interfaces. Its earlier live adapter calls the Node Planning API. The separate Pocket Engine Lab implements the Apple-first replacement: local matching/validation, an independent catalog, Apple routing/weather and constrained Luna advice. Integration must not silently invoke the earlier planner or treat missing evidence as known.

## Decision

Extract the Foundation-only core into `packages/PocketEngine`, preserving provenance/tests. C67Domain stays independent of provider SDKs; C67Data implements `PocketPlanningRepository` and platform/transport adapters. Views/Presenters retain their planning interfaces with structured preference and connection capabilities. Default Debug/Release mode is `pocket`; explicit `mock` and legacy `live` remain available.

Amendment approved on 14 November 2026, refined after user feedback: the creation UI opens preferences, recommendations, a main-spot/duration survey, then directly attempts planning. The separate Confirm trip screen and route have been removed. Planning uses the existing draft defaults/options; it never invents a missing origin, venue availability, or AI consent. Missing origin offers a focused starting-point sheet, while the existing availability/consent review remains conditional. See the [follow-up](../tasks/jakarta-discovery-direct-processing.md).

Recommendations are session-only native MapKit searches in non-mock modes; discovery does not submit a planning job or require trip dates, origin configuration, catalog connectivity or Luna. Expanded preferences currently produce deterministic search terms; E5 integration remains separate. Unrelated labels produce separate queries whose results are interleaved, not one venue required to satisfy every label. The temporary discovery scope is a 60 km radius around central Jakarta: MapKit receives a required enclosing region and results are filtered by coordinates plus country when supplied. An overseas user/origin cannot move the discovery area overseas. This is a product radius, not an administrative Jakarta/Jabodetabek boundary. Search results are suggestions, not verified matches or evidence of facilities/access. Empty or failed queries remain visible as warnings, with retry and manual search available.

Selection has no UI count limit and survives refresh/back navigation. The existing planning contract still accepts at most six places; after the survey an unsupported request is blocked with an inline explanation without shortening the selection. Older retained destinations outside the discovery radius are likewise preserved but cannot be submitted. Pocket's narrower itinerary-area validation is unchanged; broader search coverage does not establish route support. Routing/solver expansion is deferred. Only labels supported by the existing engine taxonomy are forwarded in its structured label field; the expanded answers remain in the creation draft and preference prose. The older catalog-based suggestion endpoint and its coverage rules remain available to other callers, but are no longer used by this UI flow.

The solver checks sourced availability or personal confirmation for the trip date, full durations, waiting, timing, deadline, last stop and optional return leg. Reordering preserves order. After consent, Luna selects from immutable local options and its choice is revalidated. Invalid IDs/models and transport errors never fall back to an invented itinerary. Explicitly disabling Luna selects the local planner.

Trips/receipts are written atomically to protected local storage. Pocket does not claim account sync or Supabase persistence. Provider/write keys stay on the server and the read token stays in Keychain. Release connections require HTTPS; redirects are refused. No shared deployment or TestFlight upload is part of this change.

### First itinerary amendment

Pocket now checks the selected places against the available catalog after the optional main-spot screen. It searches a bounded set of hours and dates for a car trip, suggests durations and validates the route through the default or edited endpoint. It can propose a verified subset and report exclusions. If evidence blocks every stop and the traveller can resolve the gap, the UI offers a trip-specific confirmation. The first proposal uses local scheduling without Luna. Scope and test evidence are recorded in [the implementation task](../tasks/pocket-first-itinerary.md).

## Consequences

Default UI planning no longer depends on the Node Planning API. Pocket read/advice endpoints use separate server/auth scope in the authoritative OpenAPI document. Legacy HTTP rejects Pocket-only options rather than stripping them. Bundled identities do not establish current opening/access facts. Real server connectivity, coverage, WeatherKit provisioning, oldest supported runtime and physical-device/release acceptance remain separate verification layers.
