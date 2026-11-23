# Save a new itinerary from the toolbar

Status: Ready for review

Branch: `fix/ui`

## Outcome

In the Pocket itinerary review, the top-right checkmark opens the trip name dialog. After a successful save, Home shows the named trip in the Trip tab.

## Scope and acceptance

- Replace the review's close button and remove “Save your trip for later…” from the footer.
- Keep the current text validation and allow cancellation back to the itinerary. A failed save stays in review with its existing recovery action.
- Open the active trip flow from “Start your trip today.” A trip saved with the checkmark can be opened from its Home row.
- Exercise the native flow on Simulator with synthetic Pocket data. Use timed mock review to check the separate legacy flow.

## References

- [Pocket native integration](../guides/pocket-engine-integration.md)
- [iOS UI conventions](../../apps/ios/AGENTS.md)

## Verification

- On iPhone 18 Pro Max Simulator (iOS 27.2), the staging UI fixture passed the checkmark, name validation, cancellation, and save-to-Home checks. The large-text test confirmed a tappable control at least 44 points tall.
- On iPhone 18 Pro Simulator (iOS 27.2), the next-day fixture offered the checkmark, saved to Home, and showed the date-edit recovery when the saved trip was opened and started. The same-day fixture started from the review footer, confirmed the recalculated schedule, and reached the first arrival control.
- The generic iOS Simulator build passed with Xcode 27.2. The C67Backend package passed all 158 tests. The app creation suite passed its save, rename, retry, and session-change tests. Two selection-count tests in that suite failed before reaching review.
- The timed mock UI test stopped at Add Specific Place with an empty selection and a disabled Next button. The drag-and-save fixture passed once and a repeat stopped at the drag handle visibility assertion.
- SwiftFormat passed on the seven Swift files changed for this task. The full repository check reported formatting findings in seven other files.
