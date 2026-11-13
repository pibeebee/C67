# Task: Compare routing access correctness and itinerary runtime

Status: Ready for review — local/synthetic evidence complete; live/field gaps explicit
Owner: Hendra Irawan
Reviewers: Pending human assignment
Branch: codex/routing-access-benchmark
Baseline: main 0a06e1d (PR #13, including editor safety follow-up)

## Outcome

Provide an isolated CLI comparison of Apple pins, independently sourced access points with Apple, Google Place ID routing, and local Valhalla, including the shared TransJakarta planner. Separate endpoint coverage, reference consistency, routing latency, itinerary feasibility and provider prerequisites.

## Scope and dependencies

- Allowed: Context Lab benchmark targets/tests/docs, a narrow shared TJ walking provenance extension, maintained-source ledger and deterministic verification wiring.
- Keep editor state, live in-session storage policy, production APIs and application defaults unchanged.
- Local Colima/Valhalla and OSM processing are authorized. Google live was subsequently excluded by the user because it is paid and not needed for this MVP evaluation; it is disabled even when a key is present. A separately authorized future campaign retains a 200-request / 1,000-element cap including failures. No provider retry loop.
- Credentials remain private. No commit, push, PR, deployment, GTFS refresh or field study.
- [Current Context Lab](../../apps/c67-local-server-lab/README.md), [safety checkpoint](../../apps/c67-local-server-lab/docs/ITINERARY_EDITOR_SAFETY_2026-11-10.md), [evidence policy](../../evidence/README.md), [workflow](../../../../docs/ai/workflow.md).

## Acceptance criteria

- [x] Four provider variants, isolated benchmark state and explicit missing-prerequisite outcomes.
- [x] Public/mode-specific access selection; no POI pin relabelled as verified entrance.
- [x] Shared planner final validation, fixed-order/optional/return/wait rules and shared TJ direct/transfer rules.
- [x] Revision-aware cache, bounded calls, cancellation, stale-result protection and partial-matrix tests.
- [x] Two cafes per eight Jakarta areas, source provenance and honest reference/field coverage.
- [x] Paired synthetic and available local observations with report, no fabricated provider latency. Apple configuration is missing; Google live is explicitly excluded.
- [x] Package, Python, evidence, format, portability and application-build checks.

## Result and handoff

Execution results are in the [new routing report](../../apps/c67-local-server-lab/docs/ROUTING_BENCHMARK_RESULTS_2026-11-10.md): 1,002 synthetic observations and 96 real local graph routes. A directed-road adversary exposes 14 minutes of schedule regret despite faster calculation; application defaults are not changed. Entrance references and observed ETA accuracy remain unverified. Historical reports and immutable publication hashes remain unchanged. Hosted CI is not inferred from local verification. Commit/push/PR were not performed.
