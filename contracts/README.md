# Shared API contract

`api/openapi.json` is the authoritative OpenAPI 3.1 contract for the first slice. Reusable schemas are defined inside that file; do not maintain a second schema source in `schemas/`.

| RPC | Input | Result |
|---|---|---|
| `list_rundowns` | Empty JSON object | Published synthetic rundown versions |
| `get_rundown` | `p_version_id` | One published version with ordered stops |
| `create_trip` | `p_version_id`, `p_starts_at`, `p_request_id` | Personal snapshot |

All RPCs use POST under `/rest/v1/rpc/`. Send a client key in `apikey`. Creation additionally requires a traveller JWT in `Authorization: Bearer …`. Studio Basic Auth is unrelated.

IDs are UUID strings. `Rundown.id` identifies a published **version**, not a mutable creator root. Stop order is zero-based. `starts_at` is an ISO 8601 timestamp with an explicit UTC offset; the UI formats it in the device's locale/timezone. A full trip timezone/calendar model is deferred.

Retry a create command with the same request ID, version and timestamp. Changing input with a reused request ID returns 409. Ownership comes from the verified session, never the body. Missing/unpublished versions return 404. Errors use the PostgREST envelope `code`, `message`, `details`, `hint`.

Fixtures in `fixtures/` are synthetic. `scripts/check_contracts.py` validates OpenAPI and fixtures; `scripts/sync_fixtures.py` refreshes the checked package resource. The same sync command updates the SQL seed; contract validation rejects drift in either copy.

UI, client and server owners review changes together. Contract version 0.1 is a starter interface, not the final product schema.
