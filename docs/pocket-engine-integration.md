# Pocket Engine in the native Hi-Fi UI

Home -> preferences -> recommendations -> main spot -> optional duration -> trip configuration. Recommendations use native MapKit in non-mock modes and explicit synthetic search in mock mode. The later visit review -> itinerary -> save/start/history path retains `PocketPlanningRepository` in Pocket mode. See [ADR 0010](decisions/0010-pocket-native-ui-integration.md), the [flow change](tasks/recommendations-first-flow.md), and earlier [planning verification](tasks/pocket-ui-integration.md).

## Inputs and evidence

Q1 retains seven themes and the expanded searchable preference vocabulary. This creation flow goes directly from Q1 to recommendations, bypassing the older Q2–Q7 sequence. Deterministic English search terms bridge the new UI; E5 matching is not connected yet. Each load/refresh rotates through up to four queries, with up to twelve results per query, interleaving and deduplicating the session results. Refresh reruns search and may return the same places; it is not guaranteed pagination. Results use the existing origin as a region hint, or central Jakarta when no origin is available (a 45 km region hint, not a DKI boundary or exhaustive coverage).

Selections and their display metadata remain in the creation presenter across refresh/navigation. There is no selection count cap, and the recommendation batch is not submitted to the planner or saved as a derived catalog. Selected places can proceed to the main-spot survey without waiting for refresh. The later itinerary path still accepts one to six places and existing Pocket area/time rules. Larger selections remain intact but cannot yet be submitted for itinerary creation. Engine requests carry supported themes/labels, attribute conditions, one-day WIB window, walking/driving, waiting allowance, last stop and return choice.

Unknown hours/access do not become verified. A traveller can confirm a checked window for this trip date; it stays personal. Preferred, required exact and not-before timing are distinct. Visit start is separate from route arrival; waiting is not counted as travel. Return travel counts toward finish-by when enabled. Prose wishes are not verified guarantees. Japanese cuisine is not inferred from an Apple restaurant category.

## Server connection

Account opens Pocket settings. Enter the server base URL and read token. The token stays in Keychain and is never displayed or put in `.xcconfig`. An empty token keeps the existing token only for the same server origin. Saving is not a connectivity check.

| Setting | Use |
| --- | --- |
| `C67_DATA_MODE = pocket` | Local matching/solver, Apple services and Pocket catalog/advice transport |
| `C67_DATA_MODE = mock` | Existing synthetic, memory-only UI flow |
| `C67_DATA_MODE = live` | Earlier Supabase/Node adapter, not Pocket |
| `POCKET_SERVER_SCHEME` / `POCKET_SERVER_HOST` | Initial server URL; Debug defaults to localhost:8792, Release needs HTTPS |

Release may set `POCKET_SERVER_SCHEME = https` and `POCKET_SERVER_HOST = <deployed host>` in ignored `Production.local.xcconfig`. Provider keys, `POCKET_WRITE_TOKEN` and the read token must not go there. Enter the read token in Pocket settings. The new recommendation UI does not need this connection; default Luna planning still requires a working server and consent. Other existing engine discovery callers can still use the independent catalog and Apple search.

The app consumes authenticated `GET /v1/catalog` and `POST /v1/advice/visits`, documented in [OpenAPI](../contracts/api/openapi.json). The separately maintained Pocket Engine Lab `Server/server.py` needs HTTPS deployment in the server-setup task. Luna request model is `cx/gpt-6-luna(max)`; reported aliases are checked. Origin coordinates/provider keys are absent from the advice payload. Model metadata does not prove upstream internals.

## Storage and verification

Trips/jobs/receipts live in Application Support `PocketPlanning/trips-v1.json`, atomically written with iOS protection. Source facts retain freshness checks; Apple search is not promoted into the independent catalog. Apply retries cannot overwrite newer active-trip revisions.

Use the [local verification modes](coding-conventions.md), `swift test --package-path packages/PocketEngine` and `swift test --package-path ios-backend`.

`PocketEngineUITests` uses DEBUG-only `--pocket-integration-fixture` for the older planning integration: real core/adapter/UI, synthetic venues, ETA and model transport. This fixture does not replace the new MapKit recommendation searcher; use explicit mock mode to avoid live discovery. On 14 November, the follow-up [non-UI verification](tasks/recommendations-first-flow.md) passed Debug/Release compilation, 36 hosted presenter/preference tests, 47 backend tests and 12 core tests. Creation unit expectations were updated. UI tests and render checks were explicitly excluded; existing UI suites are not acceptance evidence for this revision. Normal Pocket mode has no transport fallback.
