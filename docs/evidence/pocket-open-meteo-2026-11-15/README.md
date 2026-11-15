# Real Open-Meteo fallback context

Date: 2026-11-15, Asia/Jakarta. No UI, app-flow edits, deployment, catalog, Google
API, ETA calculation, operational-hour dependency or automatic retry.

## Result

**Real forecast retrieval succeeded; the two-call Luna comparison was only
partially completed.** One Open-Meteo HTTP batch returned actual forecast data
for all five public selected coordinates. All seven source checks passed before
model calls. No synthetic weather replacement was used.

| Request | Outcome |
|---|---|
| C11 photography priority | Transport timeout, curl exit 28, HTTP `000`, 82.740 s; no complete model answer |
| C12 reading/food priority | HTTP 200, completed Luna response, 133.409 s; exact selected IDs and source references pass |

No retry or substitute model was used. The photography-priority real-weather
answer remains unverified, so there is no completed real-weather preference A/B
comparison. The completed answer demonstrates actual forecast-to-model input
integration for one scenario, not production reliability or forecast accuracy.

## Provider boundary and actual data

The user explicitly authorized Open-Meteo as the present WeatherKit fallback,
superseding the earlier no-substitute-weather condition for this new run. The
[previous WeatherKit status](../pocket-contextual-order-2026-11-14/phase-C-status.json)
remains a historical record: WeatherKit credentials were unavailable. This run
exercises configuration-based fallback selection; it does not test an
authenticated WeatherKit request failing and then automatically switching in the app.

Forecast target: **2026-11-16**, labelled system-suggested test date, tomorrow
relative to the client's current date 2026-11-15. Retrieved at
2026-11-15 04:34:13 Asia/Jakarta (21:34:13 UTC on November 14).
Preferences and origin/endpoint remain controlled fixtures; place IDs/names/pins
come from the earlier recorded selection. The successful order was:

**National Library → Tatemukai → Taman Bendera → Night market → Memorial Coffee.**

Raw forecast: [forecast-raw.json](forecast-raw.json). Exact request URL/retrieval
metadata: [forecast-fetch.json](forecast-fetch.json). Attribution: weather data by
[Open-Meteo](https://open-meteo.com/), CC BY 4.0.

API percentages are converted to fractions exactly once. Per provider
[documentation](https://open-meteo.com/en/docs), precipitation probability and
amount refer to the preceding hour, while cloud cover is instantaneous at the
timestamp. The adapter preserves both temporal meanings: precipitation interval
`T-1h..T`, cloud valid at `T`. Predicted amount zero does not imply probability
zero. The API returned requested-grid offsets of about 3.0–4.9 km; returned grid
coordinates are retained separately from requested pins. This is a model forecast,
not venue-specific weather observation.

Seven selected one-hour intervals per point are passed to Luna, not the full day:
05–06, 09–10, 12–13, 15–16, 17–18, 18–19 and 20–21 local. Period labels explicitly
use pagi/siang/sore/malam. Percent/amount/type/zone/location/range are checked;
missing values are rejected rather than filled. Context for both requests uses
the same immutable snapshot. A 30-minute local freshness policy is identified as
a test policy, not a provider-issued validity/forecast-initialization time.

Initial preflight correctly rejected insufficient single-hour coverage of the
evening solar window, which ends just after 18:00. The adapter included the next
already-fetched interval and verified contiguous union coverage. The original
HTTP snapshot was reused, without a second weather request or any model call
before this correction. Source references/numbers were not manufactured.

## Independent checks and manual observations

Seven source checks passed, including rejection of incorrect percentage units,
null probability and timezone, plus valid per-place context and immutable shared
snapshot. Both calculated solar opportunities are covered by precipitation
intervals; cloud remains an end-of-interval instantaneous forecast, not continuous
evidence throughout golden hour. Astral sunrise/sunset and Open-Meteo daily events
for the five pins differ by at most 19.435 seconds, within the predeclared 300 s
sanity tolerance. This does not validate actual visible golden light.

The completed answer was read against all actual source samples. It distinguishes
early/later morning predicted amounts where they differ, describes rain-bearing
later samples and preserves uncertainty. It does not assert indoor shelter,
operational facts, guaranteed dry conditions or promised arrivals. It avoids
selecting a solar window when photography is deprioritized. Broad daypart prose
still requires care because a sample is not a whole-period forecast.

The failed call produced no complete response. HTTP `000` is absence of a received
HTTP status, not a server status code. Curl exit 28 identifies a transport timeout;
the inherited transport did not retain stderr, so the exact connection stage and
upstream cause are unknown. Do not diagnose a specific Luna reasoning defect.

The completed response reports model `gpt-6-luna`, effort `max`, protocol
`responses`, status `completed`, and **18,202 tokens**. Usage/cost for the failed
call is unknown; do not represent that as the total usage for both attempts.

## Assessment

The combined experiments support starting a limited prototype integration of
order/activity/duration/context suggestions. They do not establish a reliable
production request path, actual venue availability, empirical duration accuracy,
forecast accuracy or stakeholder acceptance. Keep earlier duration/daypart issues
visible. Open-Meteo retrieval succeeded; request timeout handling remains a
material integration concern. No application fallback wiring was implemented.

Artifacts: [inputs](inputs.json), [call ledger](call-ledger.json),
[source checks](source-checks.json), [summary](summary.json),
[manual audit](manual-audit.json), [bound original source values](bound-source-values.json),
[C11 raw record](C11-photo-priority.json), [C12 raw record](C12-reading-food.json).

[experiment.py](experiment.py) fetches/prepares and runs; [summarize.py](summarize.py)
replays saved data offline. Existing credential transport is reused read-only,
without saving or exposing provider secrets. Prior experiment evidence is unchanged.
