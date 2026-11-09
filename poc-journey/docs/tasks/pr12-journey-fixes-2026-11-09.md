# Task: preserve main and repair the Journey contribution

Status: Ready for review; remote CI pending at commit time
Owner: Giovan, implementation assisted by Codex
Reviewers: repository maintainers
Branch: `gi/pr12-journey-fixes`, fast-forward update of PR #12's existing branch

## Outcome

Make the teammate's Journey PoC contribution reviewable and reproducible while retaining current main for the original application and unrelated standalone PoC UI. Preserve the existing Journey/shared-engine work and historical evidence.

## Scope and dependencies

- Allowed: Journey Showcase, its tests/docs, necessary shared TripIntegration engine/resources, the publication development ledger, and PoC verification support.
- Preserve main: production UI/backend/contracts, Context Lab application, Foundation Lab standalone App/UITests, and Trip Integration diagnostic App/UITests.
- Fix the Live new-trip embedding reset and the Showcase view compilation problem observed on the CI toolchain.
- Data: authored replay inputs and verified pinned public model assets; no live provider calls or shared deployment.
- External actions authorized: repair and update existing PR #12 with a normal fast-forward commit/push. No force push, merge, branch-protection change, remote database change or provider call is part of this task.

## References

- [Contribution assessment](../poc-consolidation-assessment-2026-11-09.md)
- [Journey guide](../../apps/c67-journey-showcase/README.md)
- [Evidence policy](../../evidence/README.md)
- [PR #12](https://github.com/pibeebee/C67/pull/12)

## Acceptance criteria

- [x] Unrelated application files match the fetched current main; required shared-engine additions remain.
- [x] New Live trips preserve E5 and Demo trips retain explicit replay behavior, including mode switches.
- [x] The refactored origin/area/spot UI retains its interaction and accessibility identifiers.
- [x] Journey Simulator unit/UI tests and relevant deterministic checks pass locally.
- [ ] The updated PR head passes the full remote checks, including the previously failing native job.
- [x] Evidence hashes and documentation describe the scoped contribution without rewriting historical claims.

## Verification plan

Use `scripts/verify.sh` for package/publication checks, the pinned Swift formatter, a dedicated Simulator for Journey tests, and the remote CI toolchain for the original compiler regression. Record local and CI evidence separately. Use a fresh ignored output directory and preserve failed runs.

## Result and handoff

- Restored eight standalone Foundation Lab/Trip Integration App/UITest files to main `72a8c9575e079be4ad7cebed26c3d8ae5c5ff640`; production and Context Lab source also match that main. Required shared-engine changes remain.
- New Live trips preserve E5; the added regression covers Demo/Live switching and restored Live drafts without calling a provider.
- Split the destination-preferences result builder into smaller sections and concrete area/spot row views. Kept labels and accessibility identifiers. Local compilation is verified; the CI-specific compiler regression requires the remote check below.
- Added `verify.sh journey-models` and its portable dispatch test; the native CI job now runs Journey model/geometry tests on an available Simulator.
- Local Xcode 27.2 / iPhone 17e iOS 27.2 Simulator: **27 tests passed, zero failed/skipped**, comprising 19 model/geometry tests and eight UI tests. This includes origin/area/required-spot flow, maps, persistence, export, large text and the Live E5 regression.
- Python: **55 tests passed**. Pinned SwiftFormat: **365 files checked**, no formatting changes needed. Publication: **3,415 imported copies / 12 maintained changes** validated; portability: **3,538 files** checked. Git whitespace check passed.
- Evidence: local result bundle `/tmp/c67-pr12-journey-fixed.xcresult`, summary `/tmp/c67-pr12-journey-summary.json`, log `/tmp/c67-pr12-journey-fixed.log`. Raw outputs are not committed. Historical consolidation reports are preserved as earlier evidence.
- Remote verification: follow [PR #12 checks](https://github.com/pibeebee/C67/pull/12/checks) for the updated commit; the failed original run remains available as historical evidence. Local Xcode 27.2 success alone does not establish Xcode 26.6 compatibility.
- No real-provider call, physical-device acceptance, production deployment or merge is claimed. The existing Context Lab LLM-reason validation error is outside this task.
