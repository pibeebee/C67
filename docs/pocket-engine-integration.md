# Pocket Engine in the native Hi-Fi UI

Home -> preferences -> confirmation -> recommendations -> visit review -> itinerary -> save/start/history uses `PocketPlanningRepository`. See [ADR 0010](decisions/0010-pocket-native-ui-integration.md) and [verification](tasks/pocket-ui-integration.md).

## Inputs and evidence

Q1 retains seven themes; Refine interests exposes the same 62 labels with search. Requests carry themes, refinements, attribute conditions, Jakarta Selatan/Kemayoran area, one-day WIB window, walking/driving, waiting allowance, last stop and return choice. Discovery can start without a required place. A recommendation list needs at least three eligible matches and all chosen interests represented.

Unknown hours/access do not become verified. A traveller can confirm a checked window for this trip date; it stays personal. Preferred, required exact and not-before timing are distinct. Visit start is separate from route arrival; waiting is not counted as travel. Return travel counts toward finish-by when enabled. Prose wishes are not verified guarantees. Japanese cuisine is not inferred from an Apple restaurant category.

## Server connection

Account opens Pocket settings. Enter the server base URL and read token. The token stays in Keychain and is never displayed or put in `.xcconfig`. An empty token keeps the existing token only for the same server origin. Saving is not a connectivity check.

| Setting | Use |
| --- | --- |
| `C67_DATA_MODE = pocket` | Local matching/solver, Apple services and Pocket catalog/advice transport |
| `C67_DATA_MODE = mock` | Existing synthetic, memory-only UI flow |
| `C67_DATA_MODE = live` | Earlier Supabase/Node adapter, not Pocket |
| `POCKET_SERVER_SCHEME` / `POCKET_SERVER_HOST` | Initial server URL; Debug defaults to localhost:8792, Release needs HTTPS |

Release may set `POCKET_SERVER_SCHEME = https` and `POCKET_SERVER_HOST = <deployed host>` in ignored `Production.local.xcconfig`. Provider keys, `POCKET_WRITE_TOKEN` and the read token must not go there. Enter the read token in Pocket settings. Unconfigured discovery can use bundled independent identities and Apple search; default Luna planning still requires a working server and consent.

The app consumes authenticated `GET /v1/catalog` and `POST /v1/advice/visits`, documented in [OpenAPI](../contracts/api/openapi.json). The separately maintained Pocket Engine Lab `Server/server.py` needs HTTPS deployment in the server-setup task. Luna request model is `cx/gpt-6-luna(max)`; reported aliases are checked. Origin coordinates/provider keys are absent from the advice payload. Model metadata does not prove upstream internals.

## Storage and verification

Trips/jobs/receipts live in Application Support `PocketPlanning/trips-v1.json`, atomically written with iOS protection. Source facts retain freshness checks; Apple search is not promoted into the independent catalog. Apply retries cannot overwrite newer active-trip revisions.

Use the [local verification modes](coding-conventions.md), `swift test --package-path packages/PocketEngine` and `swift test --package-path ios-backend`.

`PocketEngineUITests` uses DEBUG-only `--pocket-integration-fixture`: real core/adapter/UI, synthetic venues, ETA and model transport. It is visibly synthetic, not live provider or recommendation-quality validation. Normal Pocket mode has no transport fallback.
