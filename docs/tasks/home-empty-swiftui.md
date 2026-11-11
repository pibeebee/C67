# Task: Native SwiftUI HOME EMPTY

Status: Ready for review
Owner: Hendra
Reviewers: Pending human review
Branch: Feat/home-empty-ui

## Outcome

Slice Balaraja Sketch → HI-FI → HOME EMPTY into the C67 app using native SwiftUI controls.

## Scope and dependencies

- Home presentation, native Trip/History tabs, starting-point selection and entry into the existing planning editor.
- Reuse the existing Planning presenter, repository and account lifecycle. No API/domain changes.
- Preserve the existing planning workspace with `--planning-workspace` and Discovery with `--legacy-catalog`.
- Minimum iOS 18 and existing Swift language mode remain unchanged. Liquid Glass uses iOS 26 availability checks.
- Mock stays synthetic and memory-only. The location pill displays the actual draft origin label; the Sketch location is not presented as a verified device position.
- Local edits/checks only; no commit, push or deployment authorized.
- Started from the user's current checkout, preserving its unrelated uncommitted POC work and existing commits.

## References

- Sketch document: Balaraja Sketch (`AE5D7AB1-6866-4AC8-9BC8-94334C18ED6B`).
- HI-FI source frame: `2743A274-C2E2-42E5-A96A-D9F345F05213`, 402 × 874. Duplicate `7D92AF5D-96C0-45B3-A9B2-D35319A2979A` has the same hierarchy/copy.
- Source inspection: SF Pro 20 pt semibold title, 17 pt regular body, 4 pt gap; adaptive system grouped background (Light #F2F2F7); native glass controls and tab bar.
- [UI guide](../../ios-ui/README.md), [design system](../design-system.md), [architecture](../architecture.md).

## Acceptance criteria

- [x] Native home renders the reference header, centered copy and Trip/History navigation.
- [x] Add opens planning, location opens search, History and Account remain reachable.
- [x] Larger text and Dark appearance are visually checked.
- [x] Simulator build and relevant mock UI tests pass.

## Verification plan

Generate the Xcode project from project.yml; run the Simulator build, targeted TripHomeUITests and preserved Discovery smoke test. Capture Light, Dark and accessibility text screenshots. Run the pinned formatter and whitespace checks. Report runtime and unverified device/VoiceOver/iOS 18 acceptance separately.

## Result and handoff

- Implemented `Features/Home` and reused the existing Planning/Account presentation and data flow. Typed navigation paths stay separate per tab and reset on account changes. Saving a proposal dismisses the editor and opens its trip. Home handles loading, empty, error/retry and saved-trip states.
- `TripGlassCapsule` is shared visual code. Native glass is availability-guarded with iOS 18 fallbacks. `TripCanvas` is an adaptive asset; the target explicitly leaves the existing absent app icon unset so XcodeGen does not infer an AppIcon set from the new color catalog.
- XcodeGen regeneration and generic iOS Simulator build passed with Xcode 27.2. Deployment minimum remains iOS 18.0 / Swift language mode 6.0.
- iPhone 18 Pro, iOS 27.2, mock mode: 3 Home tests passed in Dark appearance (navigation/search/editor/account entry, accessibility XXXL with reachable controls, and plan → proposal → save → detail → back to populated Home). Standard-text test verifies the add button is at least 44 × 44 pt.
- Final Light run: 3 tests passed (Home navigation plus preserved Account-mode and Discovery/detail/save smoke tests). No expected failures, skipped tests or runtime warnings in either final result bundle.
- Result bundles: `/tmp/c67-home-dark-tests.xcresult` and `/tmp/c67-home-light-final.xcresult`. Earlier save-test failure was an automation gesture being consumed by the native map; the helper now scrolls the form at its trailing edge, with the same app behavior.
- Visually inspected standard Light/Dark and accessibility XXXL iPhone captures, plus iPad Pro 11-inch (M5), iOS 27.2. On iPad the native tabs relocate to the top. Screenshots are exported outside Git at `/Users/neuhendra/Documents/PBB/exports/c67-home-empty/`.
- Targeted pinned SwiftFormat check passed: 0/14 changed/new Swift files require formatting. Whole-repository `python3 scripts/swift_format.py --check` remains blocked by pre-existing formatting in `evaluations/foundation-models-2026-11-04/focused-english/Support.swift:168` and `tripsense-poc/App/TripSenseApp.swift:31`; neither file was changed. `git diff --check` passed.
- Physical device, iOS 18 runtime/material fallback, manual VoiceOver, RTL and iPad multitasking/folding-device acceptance remain unverified. No live planning/search/authentication acceptance is claimed.
- No contract or ADR changes. No commit, push or deployment; unrelated checkout changes were preserved.

Preview follow-up: `TripHomeRootView.swift` now has named Light and Dark `#Preview` entries using a synthetic in-memory planning repository. The Light preview rendered in Xcode Canvas on iPhone 18 Pro; the generic iOS Simulator build and targeted formatting check passed. The Simulator app was not launched for this preview check.
