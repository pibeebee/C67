# Task: Native SwiftUI ITINERARY LIST

Status: Ready for review
Owner: Hendra
Reviewers: Pending human review
Branch: Feat/itinerary-list-ui

## Outcome

Implement Balaraja Sketch → HI-FI → ITINERARY LIST in ios-ui/C67.xcodeproj as the personal-plan review screen before saving.

## Scope and references

- Source frame `8133F462-4F8A-4A9D-B23A-346FDA26C78F`, 402 × 1282, document `AE5D7AB1-6866-4AC8-9BC8-94334C18ED6B`.
- [UI instructions](../../ios-ui/AGENTS.md), [shared design guidance](../design-system.md), [Home task](home-empty-swiftui.md), [planning architecture](../architecture.md).
- Reuse Planning presenter/domain/repository and existing place/duration editors. No contract or backend changes.
- Native Map, disclosure controls, navigation, sheets and buttons; retain iOS 18 deployment target and Swift language mode.
- Optional presentation metadata never invents category, photos, distance or per-stop weather for generated proposals. Source photos and weather/distance examples are isolated in DEBUG preview (`--itinerary-preview` / Xcode preview).
- Source hero gradient starts at #356AE6. Its lower end uses a darker #456BC8 variation of source #8FB0FF so normal white text remains readable. Stop cards retain the source's white/adaptive surface and timeline hierarchy. Native tap targets and wrapping can increase row heights.
- Source reorder handles are represented as native edit controls. Arbitrary route reordering is not supported by the existing planning contract; visit edits/additions regenerate a proposal rather than silently changing accepted order/times.
- Preserve prior Home and unrelated checkout changes. Local work only; no commit, push, deployment or live provider acceptance.

## Acceptance and verification plan

- [x] Departure summary, numbered timeline, editable visits, weather/context disclosures, map and save action render.
- [x] Generated proposal review supports edit → regenerate → save → detail and stale proposal saving is disabled.
- [x] Compare Light/Dark/large-text renders and iPad layout with the source.
- [x] Simulator build, targeted UI regressions and changed-file formatter/whitespace checks pass.

## Result and handoff

- Implemented `Features/Itinerary` with a typed presentation route and optional presentation metadata, reusing `C67Domain` entities. Home's planning editor automatically opens the new review; the legacy workspace keeps its original proposal form. Review retains a snapshot during regeneration, disables stale saves and exposes retry after a failed regeneration. Real saved trips still open the existing detail.
- Exported the visible source thumbnail layers `335F4DBA-28C3-421D-93C5-946574BB4E96`, `E5C4F3D4-724B-4B69-92BE-0D2A321979CE`, and `64559E2C-FD12-49FF-A3A7-5BE700DD4AC0` as 144 × 144 PNGs in 3x image sets. Source sample venues/weather/distances are confined to the DEBUG preview. Preview actions show an explicit notice and do not write a trip.
- XcodeGen generation, generic Simulator build, and final signed Simulator builds passed using Xcode 27.2. Existing deployment minimum (18.0) and language mode (6.0) remain unchanged.
- iPhone 18 Pro / iOS 27.2 / mock: the final Light result `/tmp/c67-itinerary-complete.xcresult` passes 2 tests: preview/timeline/map/source disclosure/sample-save notice, and generated review → edit visit → regenerate → open/cancel add-place search → save → trip detail.
- The new Home proposal/save/detail/back regression also passed in `/tmp/c67-itinerary-verified-light.xcresult` (3 tests total with the earlier versions of the two tests above).
- Dark accessibility XXXL preview passed after the final adaptive-header fix in `/tmp/c67-itinerary-final-dark-large.xcresult` (1 test). At large sizes the departure label switches to a readable sentence-case fallback; cards, text and save remain scrollable/reachable. These final runs report no failures, skips or runtime warnings. No live search query or routing/weather provider acceptance was performed.
- Standard Light/Dark, large text, and iPad Pro 11-inch (M5) / iOS 27.2 renders were visually inspected. Captures are outside Git at `/Users/neuhendra/Documents/PBB/exports/c67-itinerary-list/`. Native date/time formatting follows locale and time zone, so punctuation can differ from Sketch.
- A final Dark surface check found the system background style blending cards into the black canvas. `ItinerarySurface` now uses white / #1C1C1E appearance variants; its final Simulator rebuild and Dark screenshot check passed. The change leaves Light geometry and interaction behavior unchanged.
- Changed/new Swift files pass the pinned formatter: 0/18 require formatting. The full repository check reports the same two pre-existing issues in `evaluations/foundation-models-2026-11-04/focused-english/Support.swift:168` and `tripsense-poc/App/TripSenseApp.swift:31` (2/334); those files remain untouched. `git diff --check` passed.
- Physical-device, iOS 18 runtime, manual VoiceOver, RTL, iPad multitasking and arbitrary stop reordering remain unverified or outside this task. The error/retry rendering is implemented; forced provider failures were not exercised in UI tests.
- No backend/domain contract change, commit, push or deployment. Prior Home and unrelated changes were preserved.

Preview follow-up: `ItineraryListView.swift` now exposes named Light and Dark `#Preview` entries using the existing DEBUG-only Sketch sample. The Light preview rendered in Xcode Canvas on iPhone 18 Pro; the generic iOS Simulator build and targeted formatting check passed. The Simulator app was not launched for this preview check.
