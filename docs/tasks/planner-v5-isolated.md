# Isolated Travelants planner v5

Status: Evaluated with synthetic Swift fixtures on macOS.

## Outcome

The C67PlannerV5 SwiftPM product accepts a resolved single-day PlanningInput, optional visit evidence and an injected directional ETA provider. It returns the fastest comparable verified schedule, a recommendation, at most one alternative, checked duration scenarios and source-bound context metrics. prepare and refine support one optional response round with the same routing cache and remaining budget. The caller supplies evidence and any model integration.

## Decisions and scope

- The baseline uses fixed bookings or traveller durations, then explicit estimates or the existing local target with a synthetic ±15-minute range. The search probes one variable duration at a time and checks event boundaries estimated from the selected timetable. These probes establish sensitivity for evaluated cases.
- The search starts with up to three distinct orders and expands to at most 12 evaluations per scenario once it finds a schedule, or 24 while searching for one. It shares limits of 72 ETA fetches and 500 candidate evaluations across initial planning and refinement. Sensitivity starts no further scenario after 54 quotes or 400 evaluations to leave room for refinement.
- Requests carry place IDs and the information needed. Facts about access, explicit traveller choices and model suggestions have separate answer types. An accepted answer triggers a fresh ranking over the updated input using cached exact quotes wherever possible.
- A trip uses UTC minute routing times and local calendar interpretation for preferred day parts. The caller supplies date-matched weather and astronomical evidence. Ranking currently uses precipitation probability over covered outdoor visits and attendance or overlap with requested solar events.
- Production wiring, network adapters and account state are outside this task. The experiment uses only synthetic fixtures.

## Acceptance and verification

- Source review covers exact-minute memoization, early conflict exit, opening and check-in constraints, endpoint legs, evidence coverage, sensitivity, and refinement validation.
- The prepared Swift Testing suite includes a shared synthetic v4.2 comparison and independent two-order enumeration. The reported timings are exploratory. Measure p50, p95, and completion rates across broader fixtures before claiming speed or quality gains.
- Swift syntax parsing and all nine v5 behavior tests passed, including the four parameterized museum-duration cases. The targeted command is `swift test --package-path packages/C67Backend --filter PlannerV5Tests`.

## Evaluation on 21 November 2026

The dedicated comparison used a debug SwiftPM build with Swift 6.4.2 on an arm64 Mac. Both planners received identical fixed durations, confirmed access, and the same directed ETA fixture. External AI was disabled. The timed interval starts when the planner begins and ends when it returns or reports a scheduling conflict. Each scenario used one warm-up pair and ten measured pairs, alternating which planner ran first. The independent oracle evaluates every permitted order and, for flexible departure, the 30-minute grid. It uses the same synthetic ETA function. The return deadline, dwell times and simulated provider delay are fixture parameters. Reproduce the comparison with `swift test --package-path packages/C67Backend --filter PlannerV5BenchmarkTests`. [Benchmark source](../../packages/C67Backend/Tests/Starter/PlannerV5BenchmarkTests.swift)

| Scenario | ETA requests, v4.2 → v5 | p50 ms, v4.2 → v5 | p95 ms, v4.2 → v5 | Drive minutes, v4.2 → v5 | Oracle |
|---|---:|---:|---:|---:|---:|
| Three, static | 18 → 17 | 0.76 → 0.23 | 0.94 → 0.25 | 33 → 33 | 33 |
| Four, traffic | 40 → 47 | 2.72 → 1.83 | 3.11 → 1.90 | 41 → 41 | 41 |
| Five, flexible departure | 68 → 66 | 96.11 → 54.37 | 97.15 → 57.28 | 48 → 48 | 48 |
| Six, traffic | 72 → 72 | 85.71 → 68.04 | 88.59 → 84.79 | 60 → 59 | 59 |
| Six, flexible with traffic | 72 → 72 | 676.93 → 369.00 | 755.48 → 377.16 | 60 → 60 | 59 |
| Four, traffic with 2 ms simulated ETA delay | 40 → 47 | 130.87 → 144.71 | 170.56 → 153.75 | 41 → 41 | 41 |
| Three, locked order with missed check-in | 4 → 1 | 0.92 → 0.09 | 1.08 → 0.11 | Conflict in both | Conflict |

The full C67Backend suite passed all 168 tests, including a repeat of the matched comparison. The table uses the dedicated run to reduce interference from other suites.

Each engine delivered a complete schedule on all 60 measured feasible attempts and rejected all 10 infeasible attempts. On the locked case, v5 returned a check-in issue after its first quote. v4.2 consumed all four legs and returned `V41_NO_SCHEDULE`. For six fixed-departure stops with traffic, v5 matched the oracle and v4.2 was one driving minute slower. With flexible departure, both were one driving minute above the oracle.

V5 reduced the median in all five zero-delay feasible scenarios. The four-stop case used seven more quotes, and adding the same artificial provider delay to both arms reversed its median result. With ten measured samples, p95 is the maximum and varies with machine scheduling. Flexible departure remains the slowest fixture even with zero provider latency. The fixed-duration benchmark isolates the search. Separate v5 behavior tests exercise duration sensitivity, evidence coverage, and reuse of cached ETA estimates after enrichment. The comparison leaves actual MapKit latency, weather quality, iPhone performance, and end-to-end time to review unmeasured.
