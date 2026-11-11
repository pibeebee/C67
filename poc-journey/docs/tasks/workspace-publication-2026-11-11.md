# Workspace publication — 11 November 2026

Status: Local validation complete; ready for pull-request review

The user authorized committing all pending workspace changes, pushing the task branch and opening
a pull request. Current main is merged without rewriting its history. Previously published Journey
Showcase mode-policy/compiler fixes and broader walking-provider support are retained. Local
Foundation Lab fixture-clock handling and explicit Blok M/busway diagnostic App/UITest paths are
also included; this is a new broad workspace scope, separate from the historical PR #12 scope.

Original import and report hashes remain immutable. Changes to maintained diagnostic sources and
their guide are recorded in the development ledger rather than rewriting archived publication
hashes. Frozen focused-English evaluation sources retain their byte-identical checksums.

## Local verification

- C67 app unit target on iPhone 18 Pro / iOS 27.2: 86 passed, 2 skipped.
- TripSenseKit: 52 deterministic cases passed; 1 opt-in live case skipped.
- Journey packages: TripIntelligence 57, PreferenceLearning 29, VisitTiming 59,
  PreferenceQuality 40 and TripIntegration 81 cases passed (266 total).
- Journey Python tooling: 66 tests passed; focused-English evaluation guards: 4 passed.
- Trip Integration synthetic replay UI: all 4 cases passed on iPhone 18 Pro / iOS 27.2.
- Foundation Lab timing UI: both cases passed on iPhone 18 Pro / iOS 27.2.
- Foundation Lab timing UI on iPad Pro 11-inch (M5) / iOS 27.2: 1 passed, 1 failed.
  The failure is the historical test's phone-style tab-bar selector, which cannot find
  the floating iPad tab bar after the timing assertions pass. This is a test portability
  limitation, not evidence that iPad tab switching passed.
- Global Swift formatting, publication portability and immutable evidence checks passed.
  Evidence validation covers 3,415 imported copies and 32 reviewed maintained-source changes.
  The two byte-frozen focused-English evaluation sources are excluded from formatting.

Earlier native Hi-Fi UI, iPad preview and shared-client checks remain documented in
[the Hi-Fi task](../../../docs/tasks/hi-fi-ui-completion.md). No provider/model calls,
real-device acceptance, deployment or backend/schema changes were performed by this publication task.

## Publication

All originally pending workspace files are included in the topic commits. The current-main
merge retains the already-published fixes and adds this verification record. The branch is
Feat/itinerary-list-ui; the pull request targets main. Local build caches, result bundles and
fresh deterministic output remain ignored or outside the repository.
