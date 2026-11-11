# Task: Complete Hi-Fi UI and connected trip flow

Status: Ready for review
Branch: `Feat/itinerary-list-ui`

## Outcome
Complete Balaraja Sketch → Hi-Fi Add Places, save-name alert, saved itinerary, populated Home, active trip and per-stop arrival. Connect existing preference, main-spot and processing views. Every source state has a named Xcode preview.

## Scope and decisions
- Native SwiftUI; iOS 18 minimum; existing Domain/Data contracts and manual trip events.
- Recommendations require a confirmed starting point, at least one required place and explicit schedule/walking or driving. Other preference answers remain wishes, not unsupported route guarantees.
- A changed save name regenerates the proposal and requires review before applying.
- TRIP DONE means arrival at a stop. Completion occurs only after finishing the last visit.
- Live turn-by-turn guidance, backend APIs/migrations, deployment and commit/push are outside this task.
- Preserve unrelated working-tree changes. Sketch metadata/photos remain DEBUG sample content; runtime missing metadata stays absent.

## Acceptance and verification
Both Home entry choices reach a saved mock itinerary. Back, cancellation, selection limits, name regeneration, arrival/complete-stop events and account isolation retain their meanings. Preview all states; verify Light/Dark, large text and iPad. Run targeted unit/UI tests, Simulator build, shared package tests, formatting and whitespace checks. Record actual outcomes and limitations below after verification.

## Results
Implemented:
- Typed draft routes and a main-actor creation presenter; shared planner requests stay behind the existing Interactor and Domain repository.
- Native compact search/selection, stable search identities, all six Add Places previews and an editable selected-places sheet.
- Both creation paths, explicit planner confirmation, optional recommendation skip/retry, main spot and stay duration, and truthful processing copy.
- Save-name regeneration/review, accepted itinerary detail, grouped populated Home, map/status and per-stop arrival/complete transitions. Existing active-trip options remain reachable.
- Drafts survive sheet cancellation in memory and are cleared on account change or successful save. Late search/request results and duplicate taps are guarded.

Verification completed on Xcode 27.2 / iOS Simulator 27.2:
- Generic Simulator build passed, including the final source state.
- All 14 creation unit tests passed in `/tmp/c67-hi-fi-selection.xcresult`; its two recommendation UI cases also passed (16/16 total).
- A focused regression run passed 17/17 cases in `/tmp/c67-hi-fi-focused.xcresult`, including save/rename, visit editing/replanning, Home return, arrival and continuation. The broader run initially passed 23/26; its three failures were fixed and passed in the focused run. Together, the latest results cover all 15 affected iPhone UI cases.
- Eight new screen states rendered in one passing iPad preview test (`/tmp/c67-hi-fi-ipad.xcresult`). A separate iPad reading-width check and XCTest accessibility audit for sufficient descriptions, traits and text clipping passed (`/tmp/c67-hi-fi-accessibility.xcresult`). This is not full VoiceOver navigation or a contrast audit.
- The shared backend package passed 34/34 tests. Targeted SwiftFormat lint passed 47/47 files; repository-wide formatting still reports 16 pre-existing files outside this change. Whitespace checks passed.
- Add Places rendered in Xcode Canvas after cleaning stale build artifacts that referenced the old itinerary initializer. The remaining preview surfaces were rendered by UI tests. Native alerts/keyboard previews may require Live Canvas interaction.
- Visual captures were inspected on iPhone and iPad, including Dark accessibility text and reaching the arrival action by scrolling. Captures are outside Git at `/Users/neuhendra/Documents/PBB/exports/c67-hi-fi-completion`.

Observed issues fixed during checks: first-presentation sheet binding, accessibility panel overflow, native-alert action labels, saved-trip navigation title, scoped modal UI test queries, and preserving/deduplicating recommendation choices across refresh and back navigation.

Limits: live providers/search, a physical device, full VoiceOver/Reduce Motion walkthroughs and an iOS 18 runtime were not acceptance-tested. Existing iPad orientation warnings remain. No backend API/schema changed, and no commit, push or deployment was performed.
