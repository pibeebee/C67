# Relocation verification

Date: **5 November 2026 (WIB)**. These checks ran against the relocated publication copies. Original-location results remain in the dated application reports and are not counted as new runs.

Environment: Apple Silicon Mac, Xcode 27.2 (27B52), Apple Swift 6.4.2, Node 24.14.0 and Python 3.14.6. UI replay uses iPhone 18 Pro / iOS 27.2 Simulator. Minimum deployment declarations do not establish an iOS 26 runtime test.

| Check | Outcome |
| --- | --- |
| Model bootstrap / hash | PASS: fresh pinned download and all four asset size/SHA256 checks; subsequent `bootstrap.py --check` passed |
| Path/link/publication inventory | PASS: local links/packages and configured private-data patterns; 3,231 imported file hashes/dispositions verified; 22 decoded textual base64 JSON values also checked |
| Root Swift layout | PASS: pinned SwiftFormat 0.64.1; 246 Swift files including the new planner UI regression |
| CLI deterministic checks | PASS: TypeScript check, format check, 55 tests; no hosted provider calls |
| Shared packages and P3 suite | PASS: TripIntelligence 57, PreferenceLearning 29, VisitTiming 59, PreferenceQuality 40, TripIntegration 35 — 220 tests total |
| Native Weather/local harness | PASS: 100 XCTest cases and cross-process storage write/read |
| Native Jakarta harness | PASS: 26 XCTest cases; no live provider latency measured |
| Unsigned Simulator builds | PASS: Native Routing Lab, Foundation Lab and Trip Integration |
| Foundation Simulator replay | PASS: 9/9 UI tests, 0 failures/skips; [case results](relocated-foundation-ui.json) |
| P3 Simulator replay | PASS: 2/2 UI tests, 0 failures/skips; [case results](relocated-integration-ui.json) |
| Native planner UI regression | PASS: 1/1 test after splitting the view; confirmation, report navigation and invalid JSON rejection; [case results](relocated-native-ui.json) |

## Reproduction and evidence

From the repository root, run `python3 poc-journey/scripts/bootstrap.py` followed by `bash poc-journey/scripts/verify.sh` with `packages`, `cli`, `native` or `build`. The [handoff](../HANDOFF.md) includes the Simulator destination command for `ui`. New output goes to ignored `.verification/`, keeping historical evidence intact.

The completed local runs total **401 package/CLI/native test executions and 12 UI tests**, all passing, plus three unsigned builds. [Machine-readable local results](relocated-checks.json) retain native case outcomes and hashes of the local raw logs, with UI results in the three linked summaries above. These are test executions, not 413 independent user scenarios.

The final UI reruns used XcodeBuildMCP `test_sim` with the same project, scheme, Simulator, ad-hoc signing and disabled parallel testing. The preceding shell run was interrupted before a final result; it is not counted as a pass. Result bundles and raw build output remain local; the public case summaries and checksums record the completed runs. Existing MapKit deprecation warnings were not treated as failures or silently changed into source modernization.

The import checks are bounded static scans and actual fixture/build runs, not an exhaustive privacy or security audit. GitHub Actions separately checks publication/CLI, package/native fixtures and unsigned builds. Its results belong to the PR, not this local run.

## Clean-checkout and SDK compatibility corrections

The first GitHub run exposed two model metadata files that were incorrectly ignored, and compilation differences under Xcode 26.6 / Swift 6.3.3. The small `config.json` and `tokenizer_config.json` files are now committed; only the large model and tokenizer data are restored separately. A fresh local clone passed both publication checks and a fresh pinned bootstrap. The evidence validator also rejects an included artifact that is ignored or absent from the publication tree.

The maintained model adapter uses the SDK 26 `sampling:` initializer (available under a deprecated name in SDK 27). Both MapKit search adapters now hold cancellation in a main-actor object because SDK 26 does not declare `MKLocalSearch` Sendable. The affected shared-package suites were rerun locally after these corrections. Routing, ranking and prompts are unchanged. Original/publication hashes record these compatibility edits separately from the historical evaluated versions.

The native lab's copied project now uses object format 77, matching its declared preferred format, instead of Xcode 27's format 110. Its existing object types and deployment settings remain intact. This makes the imported project readable by Xcode 26; the original local project is preserved. CI builds run before the longer fixture suites so a project/SDK incompatibility is reported promptly.

SDK 26 also exceeded its type-checking budget for the old planner's combined form/dialog/sheet expression. The form and diagnostic-import sheet are now small computed views, with the same owning state, action bodies, dialog/sheet bindings and UI text. A focused `native-ui` regression exercises the synthetic confirmation/report flow and invalid JSON rejection in the existing separate test storage. The retained legacy group/diary UI suite is outside this regression's scope.

The verification wrapper now prints the final error output on failure, and CI retains logs from its hidden output directory. Earlier failed workflow attempts remain visible in [PR #10](https://github.com/pibeebee/C67/pull/10); follow the current head's checks for the final remote outcome.

No new live-provider or physical-device run is implied by this relocation. E5 use in Simulator is not Apple Foundation Models inference or physical-iPhone proof. Production C67 source and behavior are unchanged by this import.
