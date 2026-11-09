# TransJakarta-only capability boundary evaluation — v2

Status: Complete for the revised TJ-only testing scope.
Owner: Hendra / Codex

## Outcome and revised scope

The user narrowed the active evaluation to TJ only and requested more extreme, varied TJ cases. Version 2 replaces the earlier non-TJ cases, expands from 48 to 64 core scenarios, retains 1,000 direct-engine inputs and adds complete TJ source-pattern audits when the matching captured ZIP is supplied. All active motorized services belong to agency Tije. No new application router or production API is implemented.

## Implementation

- The test-only v2 manifest covers BRT corridors 1–14, non-BRT, Mikrotrans, Royaltrans, Transjabodetabek, Rusun and Bus Wisata. Route identities are checked against the pinned full source.
- Executable runtime probes cover single/one/two/three-interchange capability gates, calendars, midnight and last boarding, asymmetric return, six varied-duration visits, provider corruption, cancellation, provenance and persistence.
- A separate source auditor checks every TJ trip pattern with eight probes, without claiming application routing. It retains boarding restrictions, exact-times and calendar gaps and unverified interchange candidates.
- `verify.sh transjakarta` runs script tests and the active Swift suite. Raw evidence goes to fresh ignored directories. The v1 manifest, reports and earlier evidence remain unchanged.

## Acceptance and results

Read the [current protocol](../../apps/c67-trip-integration/docs/transjakarta/CAPABILITY-TESTS.md) and [TJ-only report](../../apps/c67-trip-integration/docs/transjakarta/TJ-ONLY-REPORT-2026-11-06.md). The evaluator must reject incomplete/contradictory results and distinguish runtime support, conflicts, gaps, injected provider failures and source-only availability. No public routing types, application behavior, commit, push, deployment or live-provider acceptance is changed or implied.


## Verified result

All 64 core cases matched expectations: ten feasible controls, 16 conflicts, 32 unsupported capability gates, four injected provider failures and two data/constraint gaps. The 1,000 engine variations produced 320 feasible bus legs and 680 expected conflicts without invariant defects. Complete-source auditing produced 5,552 observations across 241 TJ routes and 694 patterns; source gaps are recorded separately from runtime support. All 250 package test functions and 34 Python tests passed. Source hashes and the preserved v1 manifest were checked against their respective captured summaries. UI, live APIs and physical journeys are outside this verification.
