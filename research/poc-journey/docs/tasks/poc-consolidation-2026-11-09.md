# Task: Consolidate Journey POC on current main

Status: Ready for review
Owner: Hendra / Codex
Reviewers: Repository maintainers
Branch: codex/poc-journey-consolidation

## Outcome

Provide one cloneable POC workspace based on main, with Journey Showcase as the primary user UI and Trip Integration as its shared engine. Preserve the original checkout and historical experiment evidence.

## Scope and dependencies

- Consolidate the existing local POC implementation, guides, evidence validation and CI. No new trip behavior or production integration is introduced.
- Base: main `48d7139ebb008f0ad06e9f9ef2dbb0f1fe7cc2b8`. Its POC tree matches the source checkout's committed baseline `433ac4e0f32ca81da6103e95fd77b9a396afa778`.
- Source: existing local POC changes on `772f4cb6cb077e26594f77889f442e6cb30ba2f7`. TripSense, unrelated evaluations and private configuration remain in the original checkout.
- Authorized actions: fetch main, create an isolated worktree/branch, copy scoped changes, edit consolidation files and run local deterministic checks. No commit, push, PR, deployment, shared database mutation or new GTFS acquisition.

## References

- [POC guide](../../README.md), [handoff](../../HANDOFF.md), [architecture](../../../../docs/architecture/architecture.md).
- [Custom origin/area behavior](journey-custom-origins-and-areas.md), [map behavior](journey-map-controls-and-roads.md).
- [Evidence policy](../../evidence/README.md), [consolidation report](../consolidation-report-2026-11-09.md).

## Acceptance criteria

- Showcase, TJ direct/transfer routing, maps, custom origins/areas/required spots, persistence and exports remain available through the existing shared packages.
- Original import hashes and historical reports remain unchanged. Reviewed maintained-source changes are explicitly registered; unregistered changes and archival tampering fail verification.
- Package, Python, TJ offline, CLI/native, native build and three-app Simulator suites pass with explicit synthetic evidence.
- The original checkout's HEAD, branch, status, index checksum and all inventoried file hashes remain unchanged.

## Verification plan

Run bootstrap checksum verification; verify.sh packages, cli, native, transjakarta, build and ui; Python script tests; evidence, portability/link, scoped formatting and whitespace checks. Use a new ignored `.verification/consolidation-20261109/` directory. Record exact test results and missing prerequisites separately from the 6 November evidence.

## Result and handoff

- Implemented: primary Showcase entry point; shared engine ownership; imported local POC features; immutable import manifest with 20 reviewed maintained-source ledger entries; portable CI/runner validation; quality focus and UI navigation corrections.
- Checks: 265 package test functions, 51 Python, 55 CLI, 126 native harness tests, four native builds, 64 expected TJ capability cases, 1,000 departure/access inputs and 5,552 source observations passed. App/UI coverage is 39 unique cases across full-suite runs and targeted corrections; exact bundle provenance is in the report.
- Preservation: the original checkout audit verified all 3,771 pre-existing files, HEAD, branch, index and status entries. Resume checks confirmed copied source hashes. Exact status equality has one unrelated new icon-archive directory, which was retained untouched and excluded from the new worktree.
- Evidence: fresh outputs and machine-readable summaries live in ignored `.verification/consolidation-20261109/`. The original import manifest, historical results and source dates are unchanged.
- Limits: no remote CI execution, live-provider/device acceptance, production port or feed refresh was performed. Historical unsupported TJ cases remain explicit.
- Next owner: repository maintainers review the local diff and select any later publication or product-integration work.
- Commit/push status: not performed. No deployment or shared database mutation.
