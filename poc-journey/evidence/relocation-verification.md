# Relocation verification

Date: **5 November 2026 (WIB)**. These checks ran against the relocated publication copies. Original-location results remain in the dated application reports and are not counted as new runs.

Environment: Apple Silicon Mac, Xcode 27.2 (27B52), Apple Swift 6.4.2, Node 24.14.0 and Python 3.14.6. UI replay uses iPhone 18 Pro / iOS 27.2 Simulator. Minimum deployment declarations do not establish an iOS 26 runtime test.

| Check | Outcome |
| --- | --- |
| Model bootstrap / hash | PASS: fresh pinned download and all four asset size/SHA256 checks; subsequent `bootstrap.py --check` passed |
| Path/link/publication inventory | PASS: local links/packages and configured private-data patterns; 3,231 imported file hashes/dispositions verified; 22 decoded textual base64 JSON values also checked |
| Root Swift layout | PASS: pinned SwiftFormat 0.64.1, 0/245 Swift files require formatting |
| CLI deterministic checks | PASS: TypeScript check, format check, 55 tests; no hosted provider calls |
| Shared packages and P3 suite | PASS: TripIntelligence 57, PreferenceLearning 29, VisitTiming 59, PreferenceQuality 40, TripIntegration 35 — 220 tests total |
| Native Weather/local harness | PASS: 100 XCTest cases and cross-process storage write/read |
| Native Jakarta harness | PASS: 26 XCTest cases; no live provider latency measured |
| Unsigned Simulator builds | PASS: Native Routing Lab, Foundation Lab and Trip Integration |
| Foundation Simulator replay | PASS: 9/9 UI tests, 0 failures/skips; [case results](relocated-foundation-ui.json) |
| P3 Simulator replay | PASS: 2/2 UI tests, 0 failures/skips; [case results](relocated-integration-ui.json) |

## Reproduction and evidence

From the repository root, run `python3 poc-journey/scripts/bootstrap.py` followed by `bash poc-journey/scripts/verify.sh` with `packages`, `cli`, `native` or `build`. The [handoff](../HANDOFF.md) includes the Simulator destination command for `ui`. New output goes to ignored `.verification/`, keeping historical evidence intact.

The completed local run totals **401 package/CLI/native test executions and 11 UI tests**, all passing, plus three unsigned builds. [Machine-readable local results](relocated-checks.json) retain native case outcomes and hashes of the local raw logs. These are test executions, not 412 independent user scenarios.

The final UI reruns used XcodeBuildMCP `test_sim` with the same project, scheme, Simulator, ad-hoc signing and disabled parallel testing. The preceding shell run was interrupted before a final result; it is not counted as a pass. Result bundles and raw build output remain local; the public case summaries and checksums record the completed runs. Existing MapKit deprecation warnings were not treated as failures or silently changed into source modernization.

The import checks are bounded static scans and actual fixture/build runs, not an exhaustive privacy or security audit. GitHub Actions separately checks publication/CLI, package/native fixtures and unsigned builds. Its results belong to the PR, not this local run.

No new live-provider or physical-device run is implied by this relocation. E5 use in Simulator is not Apple Foundation Models inference or physical-iPhone proof. Production C67 source and behavior are unchanged by this import.
