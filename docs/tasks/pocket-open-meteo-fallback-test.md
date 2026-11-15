# Task: Real Open-Meteo fallback weather context

Date: 2026-11-15. Status: Bounded test finished; real-weather pair incomplete due to transport timeout. Owner: Codex. Reviewer: Giovan.

The user explicitly authorizes Open-Meteo as the present fallback for WeatherKit,
superseding the earlier experiment's no-substitute-weather boundary for this
new run. Keep the prior evidence unchanged. No UI/app-flow changes, deployment,
catalog, Google API, ETA, operational-hour dependency, retries or output repair.

Use the two previously unspent real-weather slots: at most two new Luna calls,
with photography-priority and reading/food preferences against the same fetched
forecast. Obtain the five selected pins in one HTTP batch. Test date 2026-11-16
is a labelled system-suggested fixture date, tomorrow relative to the client date
in Asia/Jakarta, not a new required user input.

Verify actual API units, date/zone, requested versus returned grid coordinates,
hour coverage, no imputation and provider attribution before model calls.
Open-Meteo probability/amount are preceding-hour values, while cloud is
instantaneous at the provider timestamp. Preserve those semantics and convert
percent to fraction exactly once. Include precipitation intervals covering both
calculated light opportunities. Use explicit Indonesian daypart labels.

Reuse the existing fixed model prompt/output validator and independently bind
source values. Review raw answers for unsupported facts, stale timestamps,
forecast-as-observation wording and invented indoor alternatives. A live forecast
does not establish forecast accuracy, actual light or visit feasibility.

Evidence: [headless script](../evidence/pocket-open-meteo-2026-11-15/experiment.py).
Result: actual Open-Meteo HTTP 200 for five coordinates and seven source checks
passed. Two Luna attempts: photography case timed out (curl 28, no HTTP status),
reading/food case completed with valid IDs/source references and a manually
reviewed source-consistent answer. No retry or extra call. Exact real-weather
preference comparison remains incomplete; application fallback wiring unchanged.

[Full evidence and limitations](../evidence/pocket-open-meteo-2026-11-15/README.md).
