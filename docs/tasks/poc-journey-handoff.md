# Task: Import the complete PoC journey for teammate continuation

Status: Implementation and local verification complete; remote PR delivery in progress
Owner: Giovan
Reviewers: C67 teammate review through the normal PR process; no reviewer assigned automatically
Branch: `gi/poc-journey-handoff`

## Outcome

A teammate can discover the current integrated experiment, run it from a new checkout, and understand the full itinerary/routing/weather/Foundation Models/embeddings research journey without private chats or the original Mac.

## Scope and dependencies

- New `poc-journey/` with four project roots, local packages/runners, tests, fixtures, reports, public-safe evidence and setup/verification scripts.
- Small root README/team handoff links and a separate PoC CI workflow.
- Preserve production app, backend, contracts, deployment state and unrelated feature checkout.
- User explicitly authorized implementation, commit, push and opening a PR. No merge, deployment, branch-protection change, private credential publication or shared-data mutation is included.

## References

[PoC README](../../poc-journey/README.md), [handoff](../../poc-journey/HANDOFF.md), [journey](../../poc-journey/JOURNEY.md), [root architecture](../architecture.md), [workflow](../ai/workflow.md).

## Acceptance criteria

- [x] Four runnable project roots and their important dirty/untracked source are included.
- [x] Model bootstrap, paths/local dependencies, public evidence/known gaps and script entry points are self-contained.
- [x] Relevant relocated tests/build/replay checks have actual results recorded.
- [x] Public file review excludes secrets, generated products and opaque device dumps; original and published hashes remain distinct.
- [x] Root checks and CI scope preserve production behavior.
- [ ] Commit/remote branch/PR are verified and linked in the handoff.

## Result and handoff

The [relocation verification](../../poc-journey/evidence/relocation-verification.md) records 220 package, 55 CLI, 126 native and 11 Simulator UI test executions passing, plus three unsigned builds. Pinned model bootstrap, public-file/link/package checks, imported hashes and root Swift layout passed. Original physical-device results are retained as historical evidence, not rerun or inherited automatically.

No production source, contracts, deployment configuration or unrelated feature checkout was changed. Original local sources remain intact. The scoped archive retains failed runs, marks unavailable external evidence and restores large model assets by pinned checksums rather than committing them.
