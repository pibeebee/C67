# ADR-0004 — Normalized immutable trip graph

Status: Implemented; CI/shared deployment verification tracked in the task.
Date: 24 October 2026.

## Decision

Keep seven existing RPC shapes unchanged. Add published get_rundown_route and authenticated create_trip_v3/get_trip_graph. Opt-in graph schema_version is 3. A graph contains one initial source/day (index 0), normalized stop occurrences and typed legs. Multi-day creation, multi-source merge and editing remain later contracts.

A privileged curated importer can supply optional route_template metadata on a source version. Strict validation binds stop details and leg endpoints to the existing ordered stop UUIDs. An explicit separate landing generates landing_to_first before between_stops; explicit first_stop landing points at that occurrence and creates no extra visit/transfer. Origin creates only an access leg. No name/coordinate deduplication chooses identity for the user.

Create V3 requires an explicit start basis: departure_origin requires a point and a known source landing; start_at_landing requires a known landing and retains no origin; unspecified retains no origin or inferred basis. This does not choose a default product policy. Coordinates are bounded reported/planning data, not presence evidence or verified route geometry. Optional labels and route fixture coordinates are synthetic.

Unknown location, dwell and leg duration remain null, and graph warnings make missing inputs explicit. No scheduler, provider request, ETA, zero-duration inference or actual-visit data is introduced. Only planned/not_started states are active. Source leg IDs/estimates are copied provenance, not a live route/provider guarantee.

Every creation API atomically populates owner-scoped trip_sources, trip_days, trip_stops and trip_legs. Existing trips backfill from their saved JSON with unknown source-route metadata; current source geometry cannot establish historical facts. Each copied stop has its own UUID plus source_stop_id. Composite FKs enforce aggregate/day/source boundaries. Child writes and graph-affecting root updates are blocked until an explicit revision-checked graph command exists; parent account/trip deletion still cascades through the graph.

The initial graph and root keep revision 1. Retries return identical graph IDs/data and compare API generation, version, instant, literal zone, explicit basis and JSONB origin. Existing V1/V2 generation checks reject adopting a V3 command. Source rows are share-locked during all creation paths so route metadata cannot change between source copying and graph insertion. One stable SQL projection reads the complete graph from stored rows with an explicit owner predicate and RLS.

## Consequences

Legacy JSON is retained as its original compatibility payload. It is not a second editable graph source. Public child writes, direct graph-field root changes and live rewriting from the creator are prohibited. Owner reads remain available through both safe Data API tables and the graph RPC. No public creator-authoring API, source deletion/rights policy or native integration is added.

Before shared deployment: verify all source/legacy stop arrays meet the existing UUID/title/contiguous-order contract, use a private backup and matching-image restore with persisted V1/V2 compatibility fixtures, then approve the exact new operational scope. Full recovery/edit receipts, expected_revision concurrency, journal-protected plan changes, multi-day scheduling and provider licensing remain separate work.
