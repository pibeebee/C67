# Task: Sketch recommendations in SwiftUI

Status: Ready for review  
Branch: `Feat/itinerary-list-ui`

## Outcome and scope

Slice Balaraja Sketch → HI-FI into the existing Home and planning flow using native SwiftUI controls. The source frames are HOME EMPTY ADD TRIP (`8A3FF269-7A01-41DF-A45F-B751B742C62B`), PREFERENCES PROCESSING 1 (`0FA94C7C-8A92-45A4-AA1F-FF079F73DA45`), PLACES LISTS (`F24F625A-5088-4382-B744-3EA5D40B2FF1`), and PLACES LIST ADDED (`3F1F6091-FC72-4831-930C-F76B56C928F2`).

The Home plus presents a native menu for recommendations or specific-place search. The processing view follows the real request, and the recommendations list supports selecting places, reviewing/removing them in My Places, refreshing and proceeding to an itinerary. Selection is capped at three, the remaining six-place planner capacity and the number of candidates. Stale results are dismissed when the draft or account changes. Existing workspace behavior remains available.

Sketch names, metadata and photos are DEBUG preview samples. Runtime data comes from planner candidates; missing photos, categories and addresses are not fabricated. The current synthetic mock returns one candidate. The previews and how to open them are documented in the [iOS README](../../ios-ui/README.md).

## Verification and handoff

- Generic iOS Simulator build passed with Xcode 27.2; Xcode Canvas rendered the Home, processing and list previews. The native Home menu was exercised in an automated UI test, not visually verified open in Canvas.
- Relevant mock UI tests passed on iPhone 18 Pro / iOS 27.2: Home menu and navigation, itinerary regression, recommendation selection/removal and continuation, the three-place limit, and an accessibility-size interaction check. The selection tests passed on retry after correcting a parent accessibility identifier.
- The shared `ios-backend` Swift package passed all 34 tests on macOS.
- Targeted SwiftFormat lint passed for all 17 files checked. Repository-wide formatting currently reports unrelated existing changes; see [verification](../verification.md).
- Live provider results, physical devices, VoiceOver and an iOS 18 runtime were not verified. Preview images and metadata are illustrative only. No contract or ADR changed; no commit or push was performed for this task.
