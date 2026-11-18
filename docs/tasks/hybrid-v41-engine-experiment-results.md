# Hybrid v4.1 engine experiment results

Status: Done for the synthetic engine experiment and targeted test correction.
Owner: C67 engineering.
Branch: `gi/ui-audit-improvements`.
Date: 18 November 2026.
Baseline: `f865adf` with the locally prepared experiment tests.

## Outcome and authorized scope

Analyze the one failed experiment, correct code if it caused the failure, rerun only the failed method, and interpret the results. The failure was in the test's expected value. No production engine, persistence implementation, application code, or provider configuration changed.

The initial run passed 17 of 18 methods, or 26 of 27 parameter-expanded invocations. The corrected method passed on its own. All 18 methods therefore have passing observations across two runs. This is not a complete-suite rerun after the correction.

References: [preparation and scenario matrix](hybrid-v41-engine-test-preparation.md), [v4.1 workstreams](hybrid-v41-integration.md#six-implemented-workstreams), [tests](../../packages/C67Backend/Tests/Starter/V41EngineExperimentTests.swift), [repository](../../packages/C67Backend/Sources/Data/Planning/PocketPlanningRepository.swift), and [verification](../testing/verification.md).

## Failure cause and correction

`failedAccessDiagnosticsSurvivePersistenceWithoutAnotherSearch` supplies a 60-minute visit inside a five-minute confirmed access window. Rejecting this input with `V41_ACCESS_CONFLICT` is the expected engine behavior. That rejection was not the failing test assertion.

The original assertion required `restored.input == input`, where `input` was the raw request. Before creating a first-itinerary v4.1 job, `requestPlan` sets two internal working preferences:

- `reasonableOrdering = true` to dispatch the ordering workflow.
- `automaticFirstPlan = true` to identify the first-itinerary workflow. This flag does not replace the test's manual date or enable `usesAutomaticTripDate`.

The raw fixture leaves those two optional fields unset. The working input already differs from it before persistence; the original assertion could not establish a persistence defect. The original request remains in `job.command.input`.

The corrected test independently constructs the expected working input by setting only those two flags, then verifies:

- The completed job has failed with `V41_ACCESS_CONFLICT` and exactly that working input.
- The original command is intact before and after reopening.
- The restored working input equals the completed job's input, with the failure status, error code, and assessment unchanged.
- The affected place and `traveller_confirmation` source remain in the assessment.
- Route and model call counters remain zero throughout the scenario.

All corrected assertions passed. This supports the conclusion that the observed failure was caused by test code rather than data loss in the engine. The correction retains the strict input comparison across the actual persistence boundary.

## Results by workstream

| Workstream | Observed result | Interpretation |
| --- | --- | --- |
| Structured timing | Five parameter-expanded cases passed in the initial run. | Timing answers cross the Tokyo year boundary correctly, use a stable anchor, and retain legacy explicit dates. These cases support date-selection logic; they do not replay the original screenshot's inputs. |
| Diagnostics and recovery | Command retry/status checks passed initially; the corrected persistence method passed on its own. | Repeated commands/status reads do not acquire more routes, changed input with a reused request ID is rejected, and failed-job diagnostics and both input representations survive reopening. |
| Adaptive search and accounting | Seven cases passed initially. | Direction, minute, and command mode are isolated; unavailable quotes are scoped to one attempt; a shared date budget retains an earlier complete schedule; exhausted budgets stop dispatch; first/last and order locks remain enforced. Missing ETA alone does not justify moving the trip to tomorrow. |
| Duration review | Three parameter-expanded cases passed initially. | A shorter alternative requires an accepted minimum and remains a reviewable offer. The requested baseline still fails when it cannot fit. A booked session is never shortened. |
| Access and activity sessions | Three cases passed initially. | A visit must fit continuously inside one split opening interval, overnight access can originate on the previous day, and last entry remains binding even if the venue stays open. Regular hours still leave special-date access unverified. |
| Optional Luna | Seven parameter-expanded cases passed initially. | Missing durations do not bypass any of the three permission gates. Preference prose, coordinates, the main spot, or place-selection changes invalidate saved semantic context. Other supplied-duration scenarios use zero model calls. |

The authored synthetic scenarios meet their asserted behavior after correcting the persistence test. This is evidence for the six workstreams within the tested inputs, not a guarantee for all trips. This suite does not add a successful today-to-tomorrow fallback replay; the earlier fallback evidence is recorded separately in the [integration record](hybrid-v41-integration.md).

## Commands and observed evidence

Initial suite execution:

```sh
swift test --package-path packages/C67Backend --scratch-path /private/tmp/c67-v41-engine-tests-prepared --filter V41EngineExperimentTests
```

Build succeeded. The run reported 18 methods, one issue, exit 1; the one issue was the expected-value comparison above. Log: `/private/tmp/c67-v41-engine-tests-run.log`. An earlier sandbox attempt stopped before test execution because compiler-cache access was denied; the recorded run used the required cache access.

After correcting the test, only the failed method was executed:

```sh
swift test --package-path packages/C67Backend --scratch-path /private/tmp/c67-v41-engine-tests-prepared --filter failedAccessDiagnosticsSurvivePersistenceWithoutAnotherSearch
```

Build succeeded in 2.20 seconds. Swift Testing 2403 on arm64e macOS reported one test in one suite passed in 0.019 seconds, zero issues, exit 0. Log: `/private/tmp/c67-v41-engine-failed-test-rerun.log`.

`python3 scripts/swift_format.py --check` passed: zero of 674 Swift files required formatting. `git diff --check` and local references for the updated evidence documents passed. No other test method was rerun after the correction.

## Limits and handoff

Providers are synthetic fixed quotes or authored failures. No live Luna, MapKit, weather response, UI, Simulator, physical device, real venue replay, or human judgment was evaluated. Test execution time excludes live network latency and is not an application performance benchmark. The broader package and historical app suites were not rerun in this correction.

The remaining acceptance layer is a controlled provider and real-input evaluation with recorded date choices, route/model calls, user constraints, latency, and judged itinerary quality. No commit, push, deployment, or shared-state operation was performed.
