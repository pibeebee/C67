# Travelants v5.1 app integration

Status: Implemented locally.

## Scope

The native Pocket itinerary uses v5.1 for new trips, route edits, date updates and replans. The existing job orchestration resolves dates, opening hours and optional consented semantic enrichment. Its shared route session reserves each external ETA against the persisted job budget, including retries and multi-date searches. Previously saved itineraries and already-issued jobs remain decodable with their recorded method.

Travellers can set the activity exposure from Trip options and Edit visit. Trip options also exposes the check-in buffer and extra travel allowance. Trip details shows check-in shortfalls, forecast values and sources, extra travel relative to the fastest checked schedule, and at most one alternative. WeatherKit provides available hourly temperature, UV and rainfall inputs. Open-Meteo can supply direct radiation and fill forecast gaps. The hourly decoder uses preceding-hour intervals for Open-Meteo UV and direct radiation.

## Verification

- SwiftPM, macOS arm64. System regressions include legacy proposal conversion, locked order, forecast request coalescing within a date, persistence and decoding, active replan arrival, cancellation and route budget after repository restart. The final full suite had 188 passing tests and one opt-in benchmark skip. It includes the smaller three-engine benchmark and deterministic extreme fixtures. The opt-in extreme benchmark passed separately.
- Xcode 27.2, iPhone 18 Pro Max Simulator, iOS 27.2. All 65 TripCreation tests passed. Three XCUITests passed and cover activity and tolerance controls with a missing forecast, save, reopening a saved trip and changing its departure date, and the optional-input path at accessibility text size.
- Actual provider smoke, same Simulator. A two-stop Jakarta itinerary through the real repository succeeded in **2.91 s** with **2 MapKit ETA requests**. The outdoor stop's feels-like temperature, UV and direct radiation were available from **Open-Meteo**. WeatherKit was not observed as the source of a usable series in this run. The test records one wall-clock observation. The provider fixture uses public pins and no account token.

Local result bundles are `/private/tmp/c67-v51-app-final.xcresult` and `/private/tmp/c67-v51-app-live.xcresult`. The initial engine-only baselines and quality tradeoffs are recorded in the [isolated planner report](planner-v51-isolated.md).

## Matched extreme benchmark after integration

Each cell shows median / p95 in milliseconds across 30 measured runs on the arm64 Mac. This benchmark compares the engines with synthetic inputs in SwiftPM debug mode.

| Six-stop workload | v4.2 | v5 | v5.1 |
|---|---:|---:|---:|
| No forecast, immediate ETA | 91.93 / 157.38 | 111.61 / 169.37 | 122.39 / 183.01 |
| Five-minute forecast, immediate ETA | 95.61 / 161.30 | 118.09 / 187.59 | 482.15 / 648.68 |
| Five-minute forecast, delayed ETA | 1,296.55 / 1,330.08 | 745.48 / 773.72 | 833.40 / 853.16 |
| ETA requests per run | 72 | 33 | 24 |

All three engines returned feasible itineraries throughout the matched benchmark. Their 38 minutes of driving matched the independent minimum. In the separate competing-reservations fixture, v5.1 reduced the worst buffer shortfall from 15 to 11 minutes compared with both engines. The dense forecast raised v5.1 computation time with an unchanged ETA count. The separate simulated network delay gave v5.1 a 36% lower median than v4.2. The live smoke covers one itinerary on Simulator. Repeated live latency, WeatherKit as the selected data source, and physical-device performance remain unverified.
