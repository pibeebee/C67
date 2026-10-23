# Shared API contract

`api/openapi.json` is the authoritative OpenAPI 3.1 contract for the deployed starter, private trip reads and additive v2 model. Reusable schemas are defined inside that file; do not maintain a second schema source in `schemas/`.

| RPC | Input | Result |
|---|---|---|
| `list_rundowns` | Empty JSON object | Published synthetic rundown versions |
| `get_rundown` | `p_version_id` | One published version with ordered stops |
| `create_trip` | `p_version_id`, `p_starts_at`, `p_request_id` | Personal snapshot |
| `list_my_trips` | Optional `p_limit` (1–100, default 20), `p_cursor` | `TripPage`: items and nullable next_cursor |
| `get_trip_snapshot` | `p_trip_id` | Saved personal snapshot; foreign/missing IDs both return 404 |
| `create_trip_v2` | V1 creation inputs plus required `p_time_zone` | TripSnapshotV2 with source attribution, destination date and revision |
| `get_trip_snapshot_v2` | `p_trip_id` | Complete stored V2 projection, including legacy null zone/date |

All RPCs use POST under `/rest/v1/rpc/`. Send a client key in `apikey`. Creation and both private read RPCs additionally require a traveller JWT in `Authorization: Bearer …`. Studio Basic Auth is unrelated.

IDs are UUID strings. `Rundown.id` identifies a published **version**, not a mutable creator root. Stop order is zero-based. `starts_at` is an ISO 8601 timestamp with an explicit UTC offset; the UI formats it in the device's locale/timezone. A full trip timezone/calendar model is deferred.

Retry a create command with the same request ID, version and timestamp. Changing input with a reused request ID returns 409. Ownership comes from the verified session, never the body. Missing/unpublished versions return 404. Errors use the PostgREST envelope `code`, `message`, `details`, `hint`.

Fixtures in `fixtures/` are synthetic. `scripts/check_contracts.py` validates OpenAPI and fixtures; `scripts/sync_fixtures.py` refreshes the checked package resource. The same sync command updates the SQL seed; contract validation rejects drift in either copy.

UI, client and server owners review changes together. Contract version 0.2 adds private reads without changing the existing rundown/trip shapes. The Swift client still implements only the original three RPCs; new list/detail repository methods belong to the iOS data handoff.

## Private trip reads

Send `{}` for the first default-sized list page. Responses use `{"items": [...], "next_cursor": null}`; when the cursor is non-null, send it unchanged with the next request. Ordering is `starts_at DESC, id DESC`, including a UUID tie-breaker. This orders by the chosen trip start, not creation time. A cursor is account-bound, is not an authorization token and must be discarded on account switch. Each page is a live read; pagination does not freeze a changing list across multiple requests.

The detail RPC returns the stored `Trip` snapshot in one statement; it does not rebuild content from the creator version. Ownership is checked using both RLS and an explicit verified actor predicate. Missing/foreign IDs produce the same PT404 message. Invalid/null limits, malformed/foreign cursors and null detail IDs produce PT400. Non-finite trip starts are rejected by a database constraint so responses remain date-time values and generated cursors stay usable. Full trip revision/timezone models and editing remain later work.

## Trip model v2 (stage 3A)

OpenAPI 0.3 adds two opt-in RPCs; all five existing wire shapes and the catalog fixtures stay compatible. Both new RPCs require a traveller JWT. The old list remains v1-shaped; fetch v2 detail for additional metadata. Two new synthetic snapshot fixtures cover explicit and legacy-unknown destination time.

Create with an explicit IANA region/name (or UTC), not a numeric offset alone. The server retains the instant and zone and derives local_start_date (years 1–9999), including UTC/day/DST boundaries. An equivalent-offset instant is identical retry input; a different literal zone or API generation returns 409 for the same owner/request ID. Invalid/null zone/time returns PT400, missing/unpublished source PT404. Detail uses uniform foreign/missing PT404. Existing error/security envelopes remain unchanged.

TripSnapshotV2 includes schema_version=2, immutable source rundown/version/number, nullable time_zone/local_start_date, revision and planned status. Legacy snapshots have null zone/date. Revision starts at 1; retries do not increment it. No client update, expected_revision command, lifecycle transition or merge is enabled. See [ADR-0003](../docs/decisions/0003-trip-model-foundation.md) for migration and future-edit boundaries. V2 implementation/deployment evidence is recorded separately from the already-deployed v1 results.
