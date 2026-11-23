# Align bottom actions across the trip flow

Status: Ready for review

Branch: `fix/ui`

## Outcome

Screen-level primary actions in the native trip flow share a capsule size, horizontal margins, and a vertical offset from the bottom safe area. The completion notice sits above the saved itinerary's action.

## Scope

- Reuse the existing shared bottom action bar and native button styling across preferences, place selection, processing, the itinerary, and trip completion.
- Use the native scroll-edge effect behind itinerary and saved-trip actions, matching the Next footer.
- Hide the tab bar in saved-trip details and the completion summary so the primary action lines up with the creation flow. The Trip and History tabs remain on Home.
- Use the same primary capsule style and equal available widths for paired actions inside the active-trip map panel.
- Preserve the labels, enabled states, and actions for each screen.

## Verification

Run only the Pocket Simulator integration scenario for recommendations through save and reopen. Compare the primary button frames on Recommendations, Main Spot, Itinerary, and the saved trip.

The selected scenario passed on iPhone 18 Pro Simulator (iOS 27.2) using synthetic Pocket data. All four primary buttons matched within one point for width, height, left edge, and bottom edge. The save dialog and return to Home also passed. The run covered these four layouts at the standard text size.

The same integration scenario passed after adopting the native scroll-edge background for itinerary actions. A Simulator screenshot confirmed that the solid white strip behind the start button was gone.
