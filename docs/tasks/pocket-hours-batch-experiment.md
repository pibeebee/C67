# Pocket opening-hours batch experiment

## Implementation

The authenticated `POST /v1/hours/batch` request accepts one to six selected Apple Place IDs. Pocket verifies the session once, deduplicates IDs, and returns a result for each unique ID. The batch uses at most two simultaneous provider lookups, with eight slots shared by the hours endpoints in a Pocket process. A slow lookup can use the remaining budget while its neighbours finish. At the 90-second batch deadline, the response includes completed lookups and temporary errors for unfinished items. HTTP 502 allows one retry within budget. A batch lookup maps HTTP 429 to `rate_limited` and observes the provider's `Retry-After` cooldown.

Pocket uses separate connection pools for Supabase Auth and the hours provider. The iOS transport reuses a session with cookies disabled. v5.1 reuses the operation's lookup results across schedule candidates. An unsupported batch path returns the client to the older single-place lookup. Rate limiting, authorization errors and transport failures stay distinct from that compatibility signal. Hours are transient.

## Reproduce locally

- Run `python -B -m unittest discover -s server/pocket/tests -q`, `swift test --package-path packages/C67Backend`, and `python scripts/check_contracts.py`.
- Run `python -B server/pocket/tests/benchmark_hours.py` for the matched HTTP experiment.
- Start `python -B server/pocket/tests/benchmark_hours.py --serve-simulator` on the Mac for the optional iOS Simulator case `C67UITests/PocketEngineUITests/testOpeningHoursExperimentTimeToItinerary`. It uses local ports 18791–18793.

The HTTP harness invokes Pocket's real handlers through loopback with synthetic upstreams. Each simulated Auth request takes 10 ms and each provider lookup takes 20 ms. A creates HTTP clients per request, B reuses clients with the single-place endpoint, and C sends one batch with reused clients. Fresh and warmed runs rotate variant order and collect 30 samples per cell. At four users each sample measures the time until all four clients have their results. The workload uses a mix of valid hours and 404 for three and six stops. The harness verifies full payload equality and call counts for every sample. The synthetic connection setup and local CPU contention affect absolute times, especially when A creates several clients concurrently.

For six distinct IDs, the measured request counts per itinerary are **6 Pocket / 6 Auth / 6 provider** for A and B and **1 Pocket / 1 Auth / 6 provider** for C. The Swift repository regression compares itinerary output from single and batch requests and checks that a confirmed stop is excluded and duplicates are fetched once.

## Matched HTTP timings

Median / p95 in milliseconds across 30 runs per cell.

| Users | Places | Connections | A | B | C |
|---:|---:|---|---:|---:|---:|
| 1 | 1 | cold | 61.77 / 75.44 | 37.74 / 40.81 | 37.68 / 51.95 |
| 1 | 1 | warm | 63.51 / 68.99 | 37.91 / 40.47 | 37.75 / 51.61 |
| 1 | 3 | cold | 176.40 / 201.89 | 78.60 / 105.42 | 60.37 / 73.39 |
| 1 | 3 | warm | 171.21 / 194.63 | 77.75 / 83.49 | 63.58 / 75.86 |
| 1 | 6 | cold | 332.24 / 368.92 | 116.71 / 137.83 | 86.90 / 90.76 |
| 1 | 6 | warm | 331.02 / 418.83 | 122.69 / 136.18 | 92.64 / 104.49 |
| 4 | 1 | cold | 260.01 / 317.53 | 39.39 / 53.51 | 42.56 / 58.30 |
| 4 | 1 | warm | 282.30 / 340.14 | 39.25 / 48.10 | 40.49 / 57.44 |
| 4 | 3 | cold | 1213.37 / 1571.33 | 97.52 / 133.51 | 71.83 / 101.57 |
| 4 | 3 | warm | 1293.65 / 1561.96 | 86.94 / 113.32 | 67.40 / 90.18 |
| 4 | 6 | cold | 2997.66 / 3901.16 | 137.39 / 204.65 | 97.80 / 137.45 |
| 4 | 6 | warm | 3566.27 / 3932.49 | 133.49 / 140.84 | 94.64 / 100.85 |

Batching improves the median relative to pooling alone in every three- and six-place cell. For one place it offers no clear median gain. The multi-user baseline is particularly sensitive to the CPU cost of creating clients in the local harness.

## Simulator and regression checks

The iPhone 18 Pro Max Simulator on iOS 27.2 displayed an itinerary in all three variants. With three stops, the XCTest clock measured **2.85 s for A, 2.97 s for B, and 2.84 s for C**, once per variant. The clock includes tap automation and accessibility polling. This run verifies the app flow and gives an approximate end-to-end latency. A repeatable improvement in time to review is still unproven.

The initial UI fixture used limited daily hours and reached a schedule conflict. The final UI fixture uses all-day hours for places with evidence, plus a provider 404. The initial four-user benchmark hit a loopback connection reset. The runner was rerun for all four-user cells after raising the fixture's listen backlog to 32.

Pocket had 70 passing Python tests. SwiftPM had 190 passing tests and one opt-in skip. The OpenAPI and fixture check passed, and the existing v5.1 outdoor review/save XCUITest passed separately. The HTTP benchmark and the Simulator use synthetic upstream responses. Production latency and device performance remain unmeasured in this experiment.
