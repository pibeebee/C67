# Itinerary latency benchmark — 6 November 2026

This is an isolated test harness, not continued feature development of Trip Integration.
It compiles an exact copy of `IntegrationModel.swift` and uses the existing local
TripIntegration and PreferenceQuality packages without changing their source, catalogs,
routing policy, ETA pacing, or request budget. The normal app will be reinstalled after
the physical run. The same already-configured App ID is used for WeatherKit, but all
benchmark sessions and evidence live under `Documents/C67Performance/<new UUID>`.

## Cases fixed before the new runs

All plans use the existing dated source catalogs, Asia/Jakarta, tomorrow's date, on-demand
automobile, Bundaran HI return, actual E5, and WeatherKit without Open-Meteo fallback.
The benchmark does not claim the bundled source snapshot is an inspection of venue
conditions today. The known source-age policy is retained.

| Family | Selected destinations | Trip window | Durations | Repetitions / expected outcome |
| --- | --- | --- | --- | --- |
| N1 | Cikini | 09:00–19:00 | 60 min | 3 / ready |
| N3 | Cikini, BDT RBBJ, Erasmus | 09:00–19:00 | 60 min each | 3 / ready |
| N4 | N3 + Ragunan | 07:00–19:00 | 60 min each | 3 / ready |
| N5 | N4 + GBK | 07:00–19:00 | 60 min each | 3 / ready |
| REV5 | Extend final stop of accepted N5-R3 by 30 minutes | Same as baseline | Updated final duration | 1 / ready, same destinations, accepted baseline retained |
| MIX5 | N5 | 07:00–19:00 | Cikini 45, BDT 90, Erasmus 45, Ragunan 60, GBK 30 | 1 / ready |
| TIGHT5 | N5 | 07:00–13:00 | 90 min each | 1 / conflicted; 450 min of visits cannot fit 360 min |
| SIX | Automatic selection requests 6 unique venues | 07:00–19:00 | 60 min each | 1 / needsPlaces; no silently reduced itinerary |
| UNKNOWN | Cikini, mandatory Wi-Fi without evidence | 09:00–19:00 | 60 min | 1 / needsPlaces; no silent replacement |

There are 17 cases. Within each N family, R1 constructs a fresh pipeline/E5 object and
weather coordinator; R2/R3 reuse those objects. Neither condition guarantees an empty
OS/provider/disk cache. Each generation constructs a new routing service as production
does. Families have different destinations and, for N4/N5, departure times; this is a
scenario comparison, not an experiment isolating destination count as the only factor.
Execution order is fixed, not randomized; record thermal states and don't infer p95
or a population-wide SLA from three observations.

## Measurement and validity

- Use `ContinuousClock` from the call to the real app model's create/revise method until
  its work and proposal save finish. Polling adds between 0 and approximately 50 ms.
- Exclude compilation, installation, initial store load, acceptance, benchmark export,
  and audit work. Those are not itinerary generation latency.
- Save the complete proposal, recommendation review, location review and per-case result.
  Preserve failed/paused/censored cases with their actual elapsed times.
- Record production stage metrics, search calls, ETA calls, grouped weather fetches,
  weather cache hits, E5 metadata, selected set, conflicts and thermal state.
- A ready result only passes when the production audit passes, every selected destination
  remains, the requested number of stops is present, E5 metadata exists, and all weather
  groups are actual complete WeatherKit evidence. A quick failure is never a fast itinerary.
- REV5 must reference the accepted baseline and change exactly the intended duration.
- The 240-second per-case observation limit is a benchmark cancellation limit, not a hard
  provider-process guarantee. Report such observations as censored.

## Replay check

The same harness runs on Mac with the unchanged app model and actual E5, but explicitly
injected authored coordinates, time-dependent ETA and weather. Its clock is fixed to
6 November and plans 7 November; source check dates are not altered. This checks the
matrix and result validation before device execution. Its wall times omit actual network
latency and production ETA pacing, so they must not be presented as iPhone performance.

## Reproduction

Run `bash run-replay.sh <fresh-output-directory> <scratch-SwiftPM-directory>` from this
directory. Copy the original model and entitlement before XcodeGen:

```sh
cp ../c67-trip-integration/App/IntegrationModel.swift OriginalIntegrationModel.swift
cp ../c67-trip-integration/App/C67TripIntegration.entitlements Benchmark.entitlements
xcodegen generate
```

Build the `C67PerformanceBenchmark` scheme for a connected, unlocked iPhone using the
existing signing team. Install and launch explicitly, retrieve only the new benchmark
evidence folder, then reinstall and launch the original C67 Trip Integration app normally.
Do not publish raw device/build diagnostics or signing artifacts.
