# Local-first verification and dev/main integration

Status: Implemented; current enforcement is verified through GitHub settings readback
Owner: Giovan / Codex
Branch: `gi/dev-main-workflow` (initial policy published to `dev`)

## Authorized outcome

Use feature PRs to `dev` with local checks and review. Run a compact cloud integration gate only for same-repository `dev` -> `main` PRs. Keep full app/UI, database and PoC suites available manually. Preserve one approval and protection against force pushes/deletion. The user authorized applying this policy to reduce CI overhead while preparing UI/server integration and TestFlight. This policy does not authorize claiming a live deployment or release without evidence.

## Implementation and acceptance

- `integration`: validates promotion identity, contracts and fixtures, then runs planning type/format checks and synthetic/disposable PostgreSQL tests on Linux.
- `ios-smoke`: pinned Xcode 16.4 on standard Intel macOS, Swift formatting, shared package tests, app unit tests and two existing mock Home/planning/save UI cases. Failure logs/result bundles are retained for three days.
- Full verification and PoC workflows are manual. No automatic push workflow remains.
- `scripts/verify_local.sh` records local revision, working-tree state, toolchain and logs; smoke/full iOS modes retain result bundles. It never deploys or resets a database.
- Promotion-policy tests cover accepted dev/main requests and rejection of feature branches, forks named dev, wrong target/repository, missing identity and non-PR events.
- `dev` is the working default. Both long-lived branches retain PR review and conversation rules. Main requires only the new real check names; dev has no cloud check requirement. Merge commits support long-lived branch ancestry; feature PRs use squash by convention.
- PR 17 must be retargeted and reconciled with `dev`; this policy does not merge its feature changes into main.

## Verification and rollback

Read back default branch `dev`, merge/squash enabled with rebase disabled, PR/one-review/conversation protection on both branches, no required cloud checks on dev, and required `integration`/`ios-smoke` Actions checks with an up-to-date branch on main. Do not treat absent cloud runs as passing tests. No automatic CI is expected when publishing dev or updating a feature PR targeting dev. The first reviewed promotion runs the new gate on the merge result. Stable main retains its earlier application and workflow files until that promotion; new work starts from dev and inherits the new policy.

Local verification before publication passed on Xcode 27.2: four promotion-policy test methods covering eight accepted/rejected cases; workflow YAML parsing and trigger assertions; shell syntax; repository SwiftFormat (545 files); OpenAPI/fixture/seed checks; planning type/format checks and 21 tests; and 34 Swift package tests. The local script's `quick` mode completed successfully. No new full Simulator run or live-provider/database deployment is claimed for this workflow-only change.

The pre-change main-protection JSON was saved privately outside Git before changes. The original full test commands remain in the manual workflow. Roll back through a reviewed policy commit and the saved branch settings; never force-reset application work. Service setup, live UI wiring and TestFlight distribution remain separate acceptance work.
