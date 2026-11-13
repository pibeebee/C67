# PR 17 compatibility and CI repair

Status: Ready for dev review under the local-first integration policy
Owner: Giovan / Codex
Branch: `Feat/itinerary-polish-reorder`

## Outcome and scope

Make the itinerary reordering and control polish in [PR 17](https://github.com/pibeebee/C67/pull/17) reviewable against main after PR 16 was squash-merged. Preserve the manual-order contract and the real drag, recalculation and saved-order assertions. The user authorized repairs, commits, pushes and approval when verified; merging and service deployment are separate actions.

References: [reordering behavior and service boundary](itinerary-stop-reordering.md), [UI completion](hi-fi-ui-completion.md), [verification](../testing/verification.md).

## Observed failures and changes

- The older SDK compiles the existing native button/material fallbacks. The iOS 18.5 Home test exposed extra native padding around the add button; its fallback label now leaves room for that padding while preserving the accessible target.
- The iOS 18.5 drag test started a drag but did not change stop order. A wider drop region and the legacy item-provider drop API alone did not resolve the failure. Giving the gesture time to lift, moving slowly and holding over the destination before release resolved the focused iOS 18.5 test. Its original ordering and save assertions remain intact.
- The menu helper no longer waits twice after a successful first open. The coordinate fallback and failure assertion remain.
- Starter checks cancel superseded PR runs, bound the iOS job to 30 minutes and preserve the Simulator log and result bundle on failure. `pipefail` preserves the test exit status when logging through `tee`. Required job names and test selection are unchanged.
- Production style and iOS checks use the standard `macos-15-intel` runner. The iOS job explicitly selects Xcode 16.4 so changing runner architecture does not silently replace the older-SDK compatibility check. Local iOS 27.2 checks still cover Apple Silicon. The separate Journey PoC runner is unchanged.
- The temporary focused diagnostic workflow was removed after the successful iOS 18.5 check, avoiding a duplicate macOS test job on subsequent pushes.

## CI duration evidence

[Run 43197926095](https://github.com/pibeebee/C67/actions/runs/43197926095) used Xcode 16.4 / iOS 18.5 on `macos-15`. The iOS job lasted 18 minutes 1 second; the UI suite itself took 589.7 seconds. Only the reorder scenario failed, with two assertions reporting the same unchanged order. The shared package passed 36 tests; app unit tests passed. Separate focused runs also showed substantial variability before UI execution, so build and Simulator startup cannot be treated as constant overhead.

The changes above reduce redundant waiting and superseded work; no fixed percentage speedup is claimed. Splitting UI suites would need a separate comparison of elapsed time, duplicate build cost and total macOS minutes before adoption. The PoC workflow is already path-filtered and is not triggered by this production UI PR.

In [run 43233299843](https://github.com/pibeebee/C67/actions/runs/43233299843), the ARM style job was cancelled after 15 minutes 2 seconds without executing any steps. Its annotations state that a hosted runner could not acquire the job and warn of macOS ARM capacity constraints. The iOS job also waited about five minutes before starting. This is a runner-allocation failure, distinct from a test failure. Both production macOS jobs were therefore moved to the [documented standard Intel label](https://docs.github.com/en/actions/reference/runners/github-hosted-runners); [the Intel image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md) includes Xcode 16.4 and iOS 18.5 Simulator. This avoids the affected ARM pool, without claiming a guaranteed queue time or faster test execution.

## Verification and handoff

- Repository SwiftFormat and whitespace checks passed during repair.
- The revised drag gesture passed locally in mock mode on iPhone 17e / iOS 27.2, including recalculation and saved-order verification. The related creation unit tests and Home/creation UI suites then passed 26/26 tests in 283.6 seconds with the updated menu helper.
- [Focused run 43231744897](https://github.com/pibeebee/C67/actions/runs/43231744897) passed on the older CI runtime, iOS 18.5 / Xcode 16.4, in 6 minutes 37 seconds. This result verifies the drag and save scenario, not the complete app suite.
- The earlier full-cloud gate was superseded by the user-approved [dev/main policy](dev-main-ci-policy.md). PR 17 targets dev with local evidence and review; only promotion to main requires `integration` and `ios-smoke`. The cancelled full runs are not counted as passing verification. Full regression is available manually and remains a pre-release check.
- After merging the policy into the feature branch, application/client/server/contract sources were byte-identical to `3f03dd1`. The new local quick check passed four promotion-policy tests, 22 planning tests, 36 Swift package tests, contracts and formatting. This reconciliation did not rerun or claim a new full Simulator suite.
- Physical-device interaction, manual VoiceOver and live planning-service acceptance are outside this verification. The updated planning service must be deployed before live manual reordering is available; incompatible responses remain rejected.
