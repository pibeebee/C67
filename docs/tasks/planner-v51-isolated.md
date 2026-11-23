# Isolated Travelants planner v5.1

Status: Evaluated with synthetic Swift fixtures on macOS.

## Use

Instantiate `PlannerV51(route:)` in the `C67PlannerV5` product. Pass the same `PlannerV5Input` to `PlannerV5` and `PlannerV51` for a controlled comparison. Both entry points support initial planning and one refinement with the shared per-job ETA cache and search budgets. The default check-in target is 15 minutes. Override it per trip with `checkInBufferMinutes`. The existing extra travel allowance defaults to zero.

Supply date-matched outdoor weather as one series per indicator and visit. Each series declares its source identifier and carries half-open validity intervals. The indicator fixes the units to °C for apparent temperature, W/m² for direct irradiance, or UV index. A threshold switches the comparison from a time-weighted average to the integral above that threshold. The integral uses indicator units multiplied by minutes. For instance, 20 minutes at 34 °C with a threshold of 30 °C gives 80 °C·minutes. UV describes conditions at the location, including for an activity with known shelter. Direct irradiance requires credible evidence of direct exposure.

## Selection

Keep existing hard constraints and the user's time preferences. Among equivalent viable schedules inside the extra travel allowance, minimize the largest check-in shortfall and then the sum of shortfalls. Compare outdoor conditions and existing context goals at the same shortfall level. With competing environmental changes, the fastest schedule at that buffer level is the reference for discretionary improvements. Each weather comparison uses complete, matching-source coverage for both visits. Incomplete or mixed-source data produce unavailable readings or unavailable deltas. The result includes the fastest checked schedule, the recommendation, up to one trade-off, per-session buffers, and per-visit conditions with structured deltas.

Flexible departure uses check-in and weather interval boundaries as search hints. Candidate schedules still require exact-minute ETA validation. Selection covers checked candidates under the same search limits as v5.

## Regression fixtures

`PlannerV51Tests` contains synthetic fixtures for matched v5 and v5.1 inputs, a three-minute versus 15-minute buffer, multiple sessions, strict wait and detour limits, cooler midday conditions, indoor and sheltered activities, a UV trade-off, missing UV coverage, and competing buffer and heat goals. The suite also runs matched check-in and outdoor fixtures through v4.2, v5, and v5.1.

## Synthetic evaluation

The dedicated SwiftPM debug run on an arm64 Mac passed nine test methods in two suites. The full C67Backend suite then passed all 176 tests across eight suites and reproduced both matched context outcomes. All engines used the same access windows, durations and synthetic directional ETA provider, with external AI disabled. The routing benchmark rotates engine order and uses one warm-up and ten measured rounds per scenario. Those scenarios measure routing with fixed durations and no outdoor forecast. Two separate fixtures exercise the effect of the v5.1 ranking inputs.

| Matched fixture | v4.2 | v5 | v5.1 |
|---|---|---|---|
| Check-in buffer | 3 min, 7 min driving | 3 min, 7 min driving | 15 min, 9 min driving |
| Outdoor visit | 15:10, 10 min driving | 15:10, 10 min driving | 12:05, 10 min driving |
| ETA requests in each fixture | 4 | 4 | 4 |

The outdoor fixture makes the noon park visit cooler than the afternoon visit. The selected noon interval has an apparent temperature of 29 °C, direct irradiance of 200 W/m² and UV index 3. The afternoon interval has 34 °C, 600 W/m² and UV index 6. In a separate v5.1 regression, the afternoon UV index is 1. The faster-ranked itinerary stays selected and v5.1 offers the cooler, higher-UV option as the alternative. The test also verifies that missing UV coverage leaves a comparable temperature signal available.

Each triplet below is v4.2 / v5 / v5.1. The routing reference independently enumerates permitted orders and the 30-minute departure grid in flexible cases.

| Scenario | Median ms | p95 ms | ETA requests | Driving min | Reference min |
|---|---:|---:|---:|---:|---:|
| Three, static | 0.73 / 0.22 / 0.25 | 0.85 / 0.26 / 0.29 | 18 / 17 / 20 | 33 / 33 / 33 | 33 |
| Four, traffic | 2.55 / 1.71 / 1.81 | 2.74 / 1.79 / 1.88 | 40 / 47 / 47 | 41 / 41 / 41 | 41 |
| Five, flexible | 94.50 / 53.59 / 54.80 | 95.94 / 55.41 / 56.52 | 68 / 66 / 66 | 48 / 48 / 48 | 48 |
| Six, traffic | 84.00 / 67.44 / 69.51 | 85.46 / 68.25 / 71.52 | 72 / 72 / 72 | 60 / 59 / 59 | 59 |
| Six, flexible with traffic | 654.30 / 363.65 / 371.99 | 776.17 / 399.27 / 409.93 | 72 / 72 / 72 | 60 / 60 / 60 | 59 |
| Four, traffic and 2 ms simulated delay | 127.86 / 148.56 / 148.10 | 133.27 / 150.52 / 152.52 | 40 / 47 / 47 | 41 / 41 / 41 | 41 |
| Locked order, missed check-in | 0.66 / 0.06 / 0.06 | 1.21 / 0.11 / 0.19 | 4 / 1 / 1 | Conflict / conflict / conflict | Conflict |

All three returned a schedule in all 60 feasible measured attempts and rejected all 10 missed-check-in attempts. With no artificial delay, v5.1 was 17%–66% faster than v4.2 at the median and roughly 2%–10% slower than v5. In the 2 ms delay fixture, the seven extra ETA requests contributed to a 16% higher v5.1 median than v4.2. The median with delayed ETA was very close to v5. With ten samples per arm, p95 is the sample maximum. The experiment measures synthetic scheduling on macOS. Live MapKit and weather, iPhone latency and real travel outcomes remain unmeasured.

Reproduce the dedicated run with `swift test --package-path packages/C67Backend --filter 'PlannerV(5Benchmark|51)Tests'`. [Three-engine benchmark](../../packages/C67Backend/Tests/Starter/PlannerV5BenchmarkTests.swift) · [Context fixtures](../../packages/C67Backend/Tests/Starter/PlannerV51Tests.swift)

## Extreme synthetic evaluation

The dedicated SwiftPM debug run on an arm64 Mac passed eight correctness tests and the opt-in benchmark. The subsequent full package run finished with 184 passing tests and the already measured benchmark skipped by default. The matched workload uses six places with a fixed first stop, flexible minute-level departure, two reservations, a cumulative wait limit, a last-entry cutoff, directional traffic and a required return. The dense forecast adds three indicators in five-minute intervals for two outdoor visits. The delayed arm applies a repeatable 3–18 ms sleep per ETA request before returning the same quote. Each row uses one warm-up and 30 measured runs per engine in rotating order with a fresh planner and route cache. The table reports v4.2 / v5 / v5.1 in that order.

| Scenario | Median ms | p95 ms | ETA requests |
|---|---:|---:|---:|
| No forecast, immediate ETA | 91.93 / 110.40 / 121.79 | 113.40 / 119.72 / 131.65 | 72 / 33 / 24 |
| Dense forecast, immediate ETA | 90.97 / 109.87 / 454.26 | 105.43 / 131.61 / 482.18 | 72 / 33 / 24 |
| Dense forecast, delayed ETA | 1121.96 / 616.41 / 754.60 | 1144.03 / 638.64 / 851.54 | 72 / 33 / 24 |

All engines returned valid itineraries in 30 of 30 measured runs per arm. The independent enumeration found nine feasible order and departure combinations. The benchmark recommendations reached its 38-minute driving minimum with eight and one minutes of actual check-in buffer. Their shortfalls against the 15-minute target were seven and 14 minutes. The base quality fixture reported identical weather scores across the three engines.

In a separate two-reservation fixture, v5.1 matched the best attainable worst and total shortfall at 11 and 11 minutes. V4.2 had 15 and 26 minutes, with the same 31 minutes of driving as v5.1. V5 had 15 and 15 minutes with 20 minutes of driving. The fixture explicitly allows up to 11 additional minutes of driving. The weather fixtures verify a 31.5 °C apparent-temperature average and a 65 °C·minute excess integral for a short heat spike, plus comparable temperature with invalid UV coverage and a trade-off across two outdoor visits. All engines recovered from a missing directed ETA when another route was available. All three stopped at 72 requests in the budget fixture before finding the only fully quoted itinerary, whose departure falls between the regular departure seeds.

V5.1 made 67% fewer ETA requests than v4.2 and 27% fewer than v5 in this workload. With immediate responses, the benchmark median for v5.1 increased by about 332 ms when the dense forecast was added, with the same request count. Its search adds forecast boundaries as candidate hints, a plausible contributor that the benchmark does not isolate. With synthetic ETA delay, v5.1 was 33% faster than v4.2 and 22% slower than v5 by median. These measurements cover one synthetic workload on macOS. Live MapKit, live forecasts and iPhone end-to-end latency require separate measurement.

Reproduce the benchmark with `C67_RUN_EXTREME_BENCHMARKS=1 swift test --package-path packages/C67Backend --filter PlannerExtremeTests`. [Extreme comparison suite](../../packages/C67Backend/Tests/Starter/PlannerExtremeTests.swift) · [Independent reference](../../packages/C67Backend/Tests/Starter/PlannerExtremeFixtures.swift)
