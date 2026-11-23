# Show trip preparation below Suggested departure

Status: Ready for review

Branch: `fix/ui`

## Outcome

Travellers see a compact Before you go card after the departure card on a feasible itinerary and on a saved trip awaiting departure.

## Scope

- Derive weather tips from the existing departure forecast and hours reminders from available venue information. Use an extra travel time tip when a route leg uses a default estimate.
- Keep developer schedule diagnostics in their existing area with a distinct heading.
- Verify placement, the user-facing build mode, and the rain and opening-hours tips in an isolated Pocket Simulator integration scenario.

## Design

The card uses the existing itinerary surface, system text styles, and single-color SF Symbols. One grouped surface keeps the short actions together between the departure card and the timeline. Supporting text uses reduced-opacity primary text because the initial secondary text measured 3.44:1 against the Light card surface.

The card shows the opening-hours reminder whenever a feasible plan has stops. Known conflicts use regular hours compared against the scheduled visit windows, and multiple conflicts are summarized by count. Weather tips use the forecast for the selected departure time and origin. An unavailable forecast produces no weather tip.

[Existing design system](../product/design-system.md)

## Verification

The focused Pocket integration scenario passed on the iPhone 18 Pro and the iPad Pro 11-inch (M5) Simulators with iOS 27.2. The iPad used Dark Mode and accessibility-medium text. The scenario checked card order, the hidden staging diagnostics, the synthetic rain tip, and the opening-hours reminder. Live forecast, named hours conflicts, and the other conditional tips were outside the fixture's scope.
