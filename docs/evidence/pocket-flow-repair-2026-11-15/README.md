# Connected trip-flow repair — 15 November 2026

The final connected synthetic UI run passed all **16 tests** on **iPhone 18 Pro Max Simulator / iOS 27.2**. The separate live five-place UI run passed **1 test**, through real local-server Luna ordering, exact rename/save, all five saved places, trip start and manual first-arrival confirmation. No production deployment, commit or push.

## Changes

- Name replacement uses a trailing-edge tap and bounded backspace clearing, with empty-field and exact replacement checks. It handles horizontal text scrolling without relying on the contextual Select All menu, Command-A or Forward Delete.
- Itinerary Retry preserves the requested save name through `saveReviewedProposal(named:)`; a failed rename cannot silently retry by saving the old title.
- Added rename-failure/retry regression coverage and UI coverage for empty/too-long names, cancel/reopen and exact untimed rename. Extended the live acceptance assertions through trip start and arrival. Aligned the older opt-in live discovery test's timeout with the current Luna acceptance allowance.

## Executed evidence

| Layer | Result | Evidence |
| --- | --- | --- |
| App unit test definitions | 110 passed, 0 failed, 4 opt-in external tests skipped | [Initial app/UI log](initial-app-and-ui.log), [summary](initial-app-and-ui-summary.json) |
| Final synthetic UI | 16 passed, 0 failed, 0 skipped | [UI log](final-ui.log), [summary](final-ui-summary.json) |
| Final live five-place UI | 1 passed, 0 failed, 0 skipped | [UI log](live-ui.log), [summary](live-summary.json) |
| Client Swift package | 63 passed | [Package log](swift-package.log) |
| Pocket synthetic server tests | 39 passed | [Server tests](server-tests.log) |
| Contracts and fixture consistency | Passed | [Contract log](contracts.log) |
| Pinned SwiftFormat | All 662 files passed | [Formatting log](format.log) |
| Whitespace | Passed | `git diff --check` |

App unit counts refer to test definitions, not the extra executions of dynamically parameterized cases. The initial app/UI bundle also contains two failed UI cases; they are retained as failed evidence, then superseded by the complete final 16/16 UI run. The MCP wrapper timed out after 300 seconds during that initial run; Xcode completed and wrote its result bundle normally.

One new server ordering job succeeded. The server log records one Luna request start and completion: **104.884 seconds**, reported model **gpt-6-luna**, effort **max**, Responses protocol. This is elapsed server request time, not measured internal model-thinking time. The result preserves all five selected IDs, with five weather source records and ten calculated solar windows. [Server log](live-server.log), [actual ordering request/result](live-order-jobs.json), [machine-readable summary](summary.json).

The live harness supplies five fixed public test pins and an in-memory trip repository while using actual server/Luna processing. It does not establish real-world venue access, exact arrival times, route optimality, physical-device persistence, provider dashboard accounting or iOS 18 runtime acceptance. Persistent repository behavior is covered separately by package tests. No opening hours, ETA or missing facts were added to make this test pass.

## Screenshots

- [Live five-place review](live-five-place-review.png)
- [Saved trip with exact title](live-saved-trip.png)
- [Started trip and manually confirmed first arrival](live-first-arrival.png)

## Result bundles

- Final synthetic UI: `/private/tmp/c67-flow-final-ui-20261115.xcresult`
- Live UI: `/private/tmp/c67-flow-live-final-20261115.xcresult`
- App units and initial UI failures: `/private/tmp/c67-flow-repair-synthetic-20261115.xcresult`
- Corrected targeted UI: `/private/tmp/c67-name-trailing-edge-20261115.xcresult`

## Earlier failed attempts retained

[Initial targeted shortcut pass](initial-targeted-ui.log) was insufficient: [the broader run](initial-app-and-ui.log) exposed the same shortcut's unreliability. The [deletion diagnostic run](deletion-diagnostic-ui.log) showed suffixes remaining at the insertion cursor; Forward Delete had no effect. The [corrected two-case run](corrected-targeted-ui.log) and final full UI run use trailing-edge taps and exact assertions. No failed attempt is counted as a pass.
