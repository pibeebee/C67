# Task: Native Discover and Search slice

Status: Ready for review
Owner: C67 team
Branch: `gi/native-discover-search`

## Outcome and scope

Provide a native SwiftUI layout for Discover and Search, using local example journeys and four top-level tabs. Journey retains the existing personal planning and My Trips flows via a segmented control; Bookmark is a placeholder. Search and category filtering operate on example data only. Account remains available on Discover, Search, and Journey. No new provider, backend, notification, voice search, or journey-start integration is included.

References: [product context](../product/product-context.md), [architecture](../architecture/architecture.md), and [design system](../product/design-system.md). The agreed task uses system styling while final designs are pending.

## Acceptance criteria

- [x] Discover and Search contain the supplied screen hierarchies with native controls and explicitly labeled example content.
- [x] Shared example journeys support local title/category filtering, category selection, and an empty-result state.
- [x] Journey retains Plan and My Trips without nested tab bars; Bookmark is a placeholder.
- [x] No shared API, persistence, location or provider integration was added.

## Verification and handoff

- Generic iOS Simulator build: `xcodebuild -project apps/ios/C67.xcodeproj -scheme C67 -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/c67-slicing-build CODE_SIGNING_ALLOWED=NO C67_DATA_MODE=mock build` — passed locally (Xcode 27.2); this is a build, not a Simulator run.
- Swift layout: `python3 scripts/swift_format.py --check` — run before handoff.
- iOS tests, Simulator interaction, physical-device walkthrough, and live integrations were not run at the user's request. Visual layout and interaction behavior remain unverified at runtime.
- No API or database contract changes. Changes are local and uncommitted.
