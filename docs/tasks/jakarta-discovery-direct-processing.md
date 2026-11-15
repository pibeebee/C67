# Task: Keep discovery near Jakarta and process directly after the survey

Status: Simulator walkthrough completed. Specific preference coverage still needs work.
Owner: Codex
Branch: gi/pocket-ui
Base: b71eae3
Date: 14 November 2026

## Outcome and scope

The user reported that independent bookstore search returned Australian places and requested that Confirm trip be removed. Their example of unrelated preferences also required clarifying current query behavior.

- Preserve separate queries for unrelated labels: ramen shop + independent bookstore + jogging becomes three searches, not one all-label venue requirement. Results are interleaved and deduplicated; the four-query refresh budget is unchanged. A keyword result is not verified preference evidence, and E5 is not integrated by this task.
- Interpret Jakarta & nearby as a visible, temporary 60 km radius around -6.20, 106.84. This includes nearby city centres but is not an administrative DKI/Jabodetabek polygon. Change this explicit scope if a later product decision chooses different coverage.
- Require the enclosing MapKit region, reject native results outside the radius or with a known non-ID country code, and filter coordinates again in the interactor. Apply the same policy to manual destination search, regardless of whether the user's device/origin is overseas. Filter before the native result cap. No local results means an empty result, not an overseas fallback.
- Remove `TripInputConfirmationView` and its navigation case. Completing/skipping the main-spot/duration survey attempts planning directly. Reuse the existing draft title, dates/window, mode and options; never replace a missing origin with a guessed location. An origin-only sheet can resume the attempt when needed. Existing visit-availability/consent review stays conditional, and now shows its date/window.
- Preserve unlimited selection and retained metadata. The current planner still accepts at most six places and Pocket still validates Jakarta Selatan/Kemayoran. Unsupported selections receive an inline explanation without truncation. Earlier overseas selections remain visible/removable but cannot be submitted. This task does not expand the solver, area resources, routing, or Luna transport.
- The initial code change was verified with unit tests. The subsequent user request authorized a Simulator walkthrough and live MapKit searches. Changes remain local.

## References

- [ADR 0010](../decisions/0010-pocket-native-ui-integration.md)
- [Integration guide](../pocket-engine-integration.md)
- [Earlier flow evidence](recommendations-first-flow.md)

## Verification plan and evidence

Use the existing `TripCreationTests`, `PreferenceAnswersTests` and `PreferenceFlowTests` only, explicitly excluding `C67UITests`. Exercise independent label queries, mixed local/foreign provider results, empty local results, neighbouring-city coordinates, radius edges, invalid coordinates, country mismatch, direct processing with fixed/flexible stay duration, missing origin recovery, retained larger/overseas selections, and availability/consent gates. All data/providers in these tests are synthetic or stubbed; this is not a live MapKit-quality benchmark.

`xcodegen generate --spec ios-ui/project.yml` removed only the four project entries for the deleted confirmation screen. Verification used Xcode 27.2 / Swift 6.4.2, hosted non-UI tests on iPhone 18 Pro Max / iOS 27.2, and an unsigned device Release build.

| Check | Actual result |
| --- | --- |
| Hosted Debug build + three selected unit suites | 42 tests passed, no failures; no UI/render suites selected |
| Device Release build | `BUILD SUCCEEDED`, signing disabled; no install, archive, or upload |
| Pinned SwiftFormat | All 659 Swift files pass; the total decreased by the removed confirmation view |
| Project regeneration | Only the deleted view's four PBX entries were removed |
| Whitespace / plist | `git diff --check` and `plutil -lint` pass |

The final unit command explicitly selected `C67AppTests/TripCreationTests`, `C67AppTests/PreferenceAnswersTests`, and `C67AppTests/PreferenceFlowTests`, with `-skip-testing:C67UITests`, `-parallel-testing-enabled NO`, and `C67_DATA_MODE=mock`. All selected tests are model/presenter tests. Local results: `/tmp/c67-jakarta-direct-unit-tests-final.xcresult`, `/tmp/c67-jakarta-direct-unit-tests-final.log`, `/tmp/c67-jakarta-direct-release.log`, and `/tmp/c67-jakarta-direct-format.log`. Xcode's existing nonblocking App Intents metadata warning remains; no source compiler errors were reported. No live-provider or UI/manual acceptance is implied.

## Simulator walkthrough

On iPhone 18 Pro Max Simulator running iOS 27.2, the user example produced separate synthetic ramen, bookstore and jogging candidates. Seven selections remained visible in My Places and after going back from the main spot survey. The initial error banner covered Next and retained the seven-place message after removal. The fix confines the banner to planning screens, puts it above their content and clears the error when selection changes. After retesting, reducing seven choices to three left Next usable. Picking a main spot and one hour opened the three-stop mock itinerary, where the selected cafe had a one-hour visit. The incorrect warning for preferences present in the discovery vocabulary was also removed.

Live native results for the combined example included Jakarta ramen venues and an apartment-complex jogging result whose public access is unknown. `Independent bookstore` returned `MKErrorDomain` code 4 (`placemarkNotFound`) in a bounded native diagnostic. The general `bookstore` query returned 24 results within the radius in that diagnostic. Independence was not established. The app treats code 4 as an empty result and displays the missing preference above the other results. The revised app was observed showing an empty result for the stand-alone label and keeping Bakoel Koffie selected after an explicit Refresh in a mixed result list. The live flow advanced from the survey to Visit availability for unknown hours. The walkthrough stopped at that handoff.

After the walkthrough fixes, the unsigned Release build succeeded and 44 selected unit tests passed, including regressions for recovering from a seven-place selection and classifying the native no-result error. Two targeted mock UI tests passed: `RecommendationsUITests/testMockRecommendationSelectionAndNext` and `TripCreationUITests/testSpecificPlacesOpenMainSpotAndProcessDirectly`. Pinned formatting and whitespace checks passed. Local UI test evidence is in `/tmp/c67-walkthrough-ui-1794636598.xcresult`.

## Limitations

The 60 km product radius is wider than Pocket's current itinerary areas. Scheduling still depends on supported destinations, the six-place planner limit, visit availability, consent where applicable, and the existing trip window. Live simulator coverage was a small sample. Specialized place retrieval, evidence for attributes and access, freshness, latency on physical iPhones, and E5 integration remain open. The older Pocket fixture UI tests still expect the earlier catalog recommendation workflow and require a separate fixture update.
