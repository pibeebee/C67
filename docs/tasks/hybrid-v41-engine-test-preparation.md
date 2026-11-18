# Hybrid v4.1 engine test preparation

Status: Preparation complete; subsequent execution and correction are recorded in the [experiment results](hybrid-v41-engine-experiment-results.md).
Owner: C67 engineering.
Branch: `gi/ui-audit-improvements`.
Date: 18 November 2026.

## Outcome and scope

Prepare additional non-UI regression experiments for the six [v4.1 workstreams](hybrid-v41-integration.md#six-implemented-workstreams). Test bodies call the Foundation-only planner, route session, or repository with synthetic providers. They do not use a Simulator, real Luna, MapKit, network transport, or real venue data. Production engine and application behavior are unchanged.

[V41EngineExperimentTests.swift](../../packages/C67Backend/Tests/Starter/V41EngineExperimentTests.swift) contains 18 test methods and 27 invocations after expanding the parameterized arguments. This document records their preparation; the [results](hybrid-v41-engine-experiment-results.md) distinguish the first run from the targeted rerun. The existing 20 [v4.1 tests](../../packages/C67Backend/Tests/Starter/V41PlanningTests.swift) remain intact; their three reusable fixture helpers were moved to [V41TestSupport.swift](../../packages/C67Backend/Tests/Starter/V41TestSupport.swift).

## Prepared scenario matrix

| Workstream | Additional scenarios | Planned invocations |
| --- | --- | ---: |
| Structured timing | All four timing choices across the Tokyo year boundary with a stable retry anchor; explicit-date compatibility with old serialized preferences | 5 |
| Diagnostics and recovery | Failed access assessment survives repository reopening with affected place/source retained; repeated requests/status reads spend no extra budget, and changed input with the same ID is rejected | 2 |
| Adaptive search and accounting | Directed/minute/mode quote isolation; failed-quote retry isolation; shared cross-date limit keeps an earlier complete schedule; exhausted persisted budget; first/last locks with the main spot last; unavailable mandatory first leg; missing ETA does not trigger tomorrow fallback | 7 |
| Duration review | Exact duration with and without a user-accepted minimum; shorter alternatives retain source/date and require review; booked sessions cannot be shortened | 3 |
| Access and activity sessions | A continuous visit fits wholly within split weekly hours; previous-day overnight opening; last-entry cutoff despite the venue remaining open | 3 |
| Optional Luna | Three permission gates with missing duration; semantic cache invalidation for preference prose, coordinates, main spot, and selected places | 7 |

Providers return explicit synthetic 10-minute/1,000-meter quotes or authored failures. Calendar and schedule expectations use fixed offset-bearing dates. Counts, identity, diagnostics, hard constraints, and persistence are covered by the assertions. Regular hours remain unverified for special-date access.

## Acceptance criteria

- [x] Add behavior-focused tests for the engine and repository without UI dependencies.
- [x] Reuse existing fixture helpers and preserve the existing test bodies.
- [x] Validate syntax and compile/link the test target without executing it.
- [x] Execute the prepared cases after authorization, diagnose the failure, and rerun only the corrected method; see the separate results record.
- [ ] Assess live providers, physical devices, and human itinerary quality: outside this preparation task.

## Build-only validation

The following commands validate syntax and build the tests without invoking their bodies:

```sh
swiftc -frontend -parse packages/C67Backend/Tests/Starter/V41EngineExperimentTests.swift packages/C67Backend/Tests/Starter/V41TestSupport.swift packages/C67Backend/Tests/Starter/V41PlanningTests.swift
swift build --package-path packages/C67Backend --scratch-path /private/tmp/c67-v41-engine-tests-prepared --build-tests
python3 scripts/swift_format.py --check
git diff --check
```

The compile-only log is `/private/tmp/c67-v41-engine-tests-build-only.log`. This is compilation evidence, not a test result. See the dated entry in [verification](../testing/verification.md).

## Subsequent execution

The user later authorized execution of the additional experiment suite:

```sh
swift test --package-path packages/C67Backend --filter V41EngineExperimentTests
```

The first run passed 17 methods and failed one assertion in the persistence method. The test was corrected and only that method was rerun successfully. See the [experiment results](hybrid-v41-engine-experiment-results.md) for exact commands, cause, analysis, and logs. The full package, UI, and providers were not exercised by those runs. No commit, push, or deployment was performed.
