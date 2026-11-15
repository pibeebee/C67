# Pocket native integration

New Pocket itineraries use **reasonable, untimed Luna ordering** after preferences,
place selection and the optional main spot. The existing review, save and My Trips
screens remain the UI. See [the implementation task](tasks/pocket-reasonable-order-integration.md)
and [ADR 0010](decisions/0010-pocket-native-ui-integration.md).

## Selected places to recommendation

MapKit search retains selected identities, pins and available categories. Expanded
preferences become the traveller wishes. Search has no geographic allowlist or
selection cap; a region around the origin is a search hint. Search metadata does
not establish facilities, operating hours, entry rules or maximum stays.

The phone sends a lean request to authenticated `POST /v1/order`, then polls
`GET /v1/order/jobs/{requestID}`. Inputs are selected IDs/names/pins/categories,
preference prose, origin/default or edited endpoint, optional main/first stop,
manual-order constraint, app candidate date and timezone. It sends no provider key.
Tomorrow in the input timezone is the current app candidate for forecast context;
it is not an optimized date. No operating-hours or ETA lookup is required.

The maintained server retrieves optional Open-Meteo forecasts and calculates
Astral light opportunities. Luna returns every selected ID exactly once, activity
suggestions with inference basis, nullable visit-duration ranges, dayparts,
reasoning, tradeoffs, uncertainties and references to supplied context. The server
and phone validate identities, constraints, estimates and references. Bad model
responses fail explicitly; missing data is not repaired with invented facts.

The first forecast sample that covers departure can supply a rain probability near
the first stop. Precipitation applies to the preceding hour. Unsampled hours
remain unknown. Open-Meteo is the current fallback for this flow. Calculated solar
windows remain in the provider result. Luna explanations are hidden in the
itinerary.

The review uses on-device Apple MapKit driving ETAs and road distances from
the origin to the first stop and between stops. It starts at 08:00 on the
candidate day and uses each predicted departure for the next leg. Visit
durations use a user override, Luna's midpoint, or 30 minutes if unknown.
A leg with no ETA shows a six-minute default with no road distance. The user
can refresh missing estimates. Manual reorder keeps the original Luna
response and recalculates the route on device, reusing recent estimates
when the leg and estimated departure match. Edited departure times also
refresh MapKit locally. Behind the scenes lists estimates and available
sources. Legacy timed trips retain the existing schedule contract.

## Server connection and request lifecycle

Account opens Pocket settings for the base URL and read token. The token stays in
Keychain and must not be placed in `.xcconfig`. Changing server origin requires
credentials for that server. A successful settings save is not a connectivity test.

| Setting | Use |
| --- | --- |
| `C67_DATA_MODE = pocket` | Luna ordering, optional forecast/light context, local trips |
| `C67_DATA_MODE = mock` | Explicit synthetic in-memory UI flow |
| `C67_DATA_MODE = live` | Earlier Supabase/Node adapter |
| `POCKET_SERVER_SCHEME` / `POCKET_SERVER_HOST` | Initial URL defaults to `https://pocket.giovanc.com`. Use the ignored development override or Pocket settings for a local server. Release uses trusted HTTPS. |

The [maintained service](../server/pocket/README.md) owns the Luna key and performs
one provider attempt per new ordering job. Identical request IDs poll/resume the
same immutable result; changed input requires a new ID. A transient phone/server
connection loss preserves the request. Terminal generation failure and interrupted
server jobs require explicit retry with a new ID. Queued/running jobs are not
silently regenerated. The [HTTP contract](../contracts/api/openapi.json) separates
ordering from legacy research/advice and Supabase routes. No catalog endpoint is
used or served.

## Storage and verification

Trips/jobs/receipts and original commands use atomic protected local storage at
Application Support `PocketPlanning/trips-v1.json`. Pocket does not claim account
sync. Applying a reviewed proposal is idempotent; it cannot roll back a newer trip.

Run backend Swift, server Python, contract and targeted Simulator checks from
[verification](verification.md). `--pocket-integration-fixture` uses explicit
synthetic ordering data. Opt-in `--pocket-runtime-acceptance` seeds public selections
and calls the actual HTTP/Luna/environment path. The homelab HTTPS service and the Simulator UI are verified separately in the [deployment and itinerary evidence](tasks/pocket-homelab-itinerary-hifi.md). TestFlight and physical-iPhone acceptance are separate.
