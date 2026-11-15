# Itinerary editor + TransJakarta — 9 November 2026

## Outcome

Local implementation on `codex/context-itinerary-editor`, based on consolidation commit `3995a6a` including main `72a8c95`. Context Lab supports pre-departure replace, reorder, delete and add with draft → calculate → compare → apply. Accepted versions and an editable draft persist atomically; a restored preview cannot be applied until recalculated. Old versions use their original place identities for display/maps.

The Context planner retains manually edited order and optional-stop subsequences. Automobile remains the default for legacy JSON. TJ uses a small public facade over the existing Trip Integration planner, REST walking evidence, direct service/one transfer and attributed shape geometry. The trip waiting cap includes transit waiting on the final return. Elapsed arithmetic counts that wait once inside travel.

## Verification

The final local checks use Xcode 27.2 (27B52), Swift 6 mode, macOS 27.2 and iPhone 17 Pro / iOS 26.4.1 Simulator. Commands run from the repository root; shell invocations use the local RTK proxy. Raw evidence is under `.verification/editor-20261109/`.

| Check | Actual outcome | Boundary |
| --- | --- | --- |
| `swift test -j 4 --package-path poc-journey/apps/c67-local-server-lab` | 125 XCTest cases: 124 passed, 1 intentional benchmark skip; 35 Swift Testing cases passed | Includes old Context/recommendation/sunset and linked integration tests; the benchmark skip requires explicit original fixture/output paths |
| `swift test --package-path poc-journey/apps/c67-trip-integration/Packages/TripIntegration` | 81 Swift Testing cases passed | Shared TJ direct/transfer, feed, geometry, service/calendar and existing Journey routing regressions; parameterized inputs are not added again to this count |
| Python discovery under `poc-journey/scripts` | 55 tests passed | Importers, capability classification, evidence validator and runner |
| ContextHarness Simulator build/test host | Build passed; seven model regressions passed | Request identity, effective rain input, persistence failure, stale preview, no-op bindings, timeout and restart recovery |
| Editor UI acceptance | All 3 cases passed together with the 7 model cases in `EditorDeliveryAcceptance.xcresult` | Synthetic venues, time evidence and schematic map data; no live routing/discovery/judge requests |
| Showcase unsigned Simulator build and full Simulator tests | Build passed; 18 app tests and 8 UI tests passed (26/26) | Local Xcode 27.2 build; not a new hosted-CI result |
| Offline TJ capability evaluator | 64 cases matched expected outcomes; 1,000 synthetic sweep inputs completed; zero audit errors | 320 feasible and 680 expected access/service conflicts in the sweep. Core cases include unsupported legacy-schema gates, provider faults and missing data |
| Local HTTP route probe | Health 200; unauthenticated preview 401; authenticated preview without provider configuration 503 | Confirms actual routing/auth/configuration boundary, not successful live planning |
| Evidence/portability/format/whitespace | Passed: 3,415 publication copies, 33 ledger changes, 3,554 portable files, formatter check and Git whitespace check | Immutable publication manifests and historical hashes retained |

### Paired edit campaign

Sixteen cases ran the production fixed-order planner through the synthetic revision harness: replace first/middle/last, reorder, delete, add, too-short deadline, and zero waiting allowance, each with automobile and TJ. All sixteen matched their expected applicability. Thirteen were applicable; three correctly rejected the requested revision. The zero-wait automobile control remained feasible, whereas the TJ case failed because boarding waiting cannot be removed.

| Mode | Cases / expected matches | Applicable | Median local calculation | Maximum leg evaluations |
| --- | --- | --- | --- | --- |
| Automobile | 8 / 8 | 7 | 416.39 ms | 25 |
| TJ + walking | 8 / 8 | 6 | 315.18 ms | 25 |

The three-stop control used 20 minutes synthetic driving or 60 minutes synthetic TJ travel. Deleting a stop reduced that to 15/45 minutes; adding a fourth increased it to 25/75 minutes. The three-stop TJ control contained 20 minutes total transit waiting, already included in travel. Every applicable result retained all required destinations in edited order, preserved return travel, and satisfied elapsed = travel + venue waiting + dwell. These are deterministic arithmetic/behavior observations; they are not provider latency or a realistic travel-speed comparison.

### Review and corrections

A fresh read-only review found three important issues and one related display problem: an initial response could use mutable stops/settings, effective rain preferences were not captured, failed writes could leave displayed/editable versions different, and accepted TJ waiting omitted boarding/transfer time. These were corrected with immutable request snapshots and response checks, effective input capture, a persistence success gate, and total-wait display. Focused app tests cover the corrections. No independent re-review is claimed after the fixes.

A first map-test query matched the inherited main-screen map identifier; the editor preview now has a distinct identifier. UI automation was tightened to bring lazy-list controls into a safe visible area and wait for the specific revision preview. No-op date bindings must not invalidate a pending request; that behavior has a model regression. Historical failed bundles remain local evidence instead of being overwritten. The focused corrected map case passed against the unique preview identifier, followed by a combined 10/10 app/UI run. Omission explanations and optional-place carry-over through successive revisions also have direct package regressions.


## Evidence boundaries and remaining limits

- Provider credentials are absent in this worktree. No Google Places, Apple REST, WeatherKit REST or OpenRouter live acceptance is claimed for the editor. The generated local RunConfig is inert and used only for fixture UI tests.
- UI fixtures use synthetic places, travel and schematic geometry; Apple basemap tiles can still load. Shared TJ engine/adapter tests and the existing capability suite separately exercise static feed rules. None establish field accuracy or passenger satisfaction.
- Maximum six unique destinations, Jakarta, one future day, return to origin, one mode per itinerary, and at most one TJ transfer. MRT/KRL and arbitrary multimodal selection are not implemented.
- GTFS is the existing snapshot, with its freshness/service constraints; it is not refreshed by this task. Headways and the authored transfer buffer are estimates. Waiting/access/transfer weather exposure remains unknown.
- Refresh requires a successful search for the same identity and explicit Apple confirmation. A missing alias or restarted service does not silently bypass identity checks. The user can retain historical versions while recovering service/configuration.
- Recommendation-derived additions must have a valid recommendation proof on the same date/time context. Manual choices/history are not relabelled as fresh personal rankings. The regular recommendation E5/LLM pipeline is preserved. Revision previews retain the valid ordinary schedule and reassess moments without an additional mandatory LLM call for manually chosen places.
- The earlier remote Showcase build crashed in the Xcode 26.6 compiler. Local verification uses the installed newer Xcode and does not establish a green remote CI run.
- Simulator results contain a SwiftUI/UIKit toolbar hierarchy warning from the inherited nested-sheet UI. The selected flows passed, but this warning and broad accessibility/physical-device behavior need further acceptance.
- The inherited server keeps at most 30 simultaneously prepared places; repeated refresh/replacement can reach that limit before expiry. Recovery retains the draft and requires a fresh service/session rather than silently bypassing checks.
- This verification checkpoint did not include a production port, backend deployment, database migration, commit, push or new PR.

## Final local checkpoint

`EditorDeliveryAcceptance.xcresult`: **10/10 passed** (7 model, 3 UI). `ShowcaseRegression.xcresult`: **26/26 passed** (18 model/app, 8 UI). The final Context package run completed **159 passed + 1 intentionally skipped** across XCTest and Swift Testing. The 16 paired cases all matched expected outcomes. The local verification summary is `.verification/editor-20261109/summary.json`.

At this checkpoint the changes were an uncommitted local diff on `codex/context-itinerary-editor`. The original checkout was not edited. The checkpoint established no new remote CI outcome, commit, push or PR. Live-provider and field acceptance remain the limitations listed above.
