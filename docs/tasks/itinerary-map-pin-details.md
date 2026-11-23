# Task: Show place details on itinerary map pins

Status: Ready for review  
Owner: iOS and Pocket maintainers  
Branch: fix/ui

## Outcome

Selecting a numbered stop opens the approved C2 callout anchored to the pin. The blue visit block shows the itinerary time and duration.

## Scope and dependencies

- Use the selected MapKit place's address and contact details. Refresh missing metadata by its Apple Place ID.
- Use Pocket's existing hours lookup for regular hours and add an optional, source-attributed entry rule from current, verified research for that exact place and traveller. The lookup does not initiate new research.
- Keep the pin details usable when an individual source has no result. Preserve the Apple Maps action in live mode.
- Local code and synthetic integration verification. External actions authorized: none.

## References

[Design system](../product/design-system.md) · [Pocket integration](../guides/pocket-engine-integration.md) · [API contract](../../contracts/api/openapi.json)

## Acceptance criteria

- [x] Selecting a pin presents the matching stop, itinerary schedule, address, contact, regular hours and entry rule where supplied.
- [x] Closing or selecting another pin clears the previous stop's details.
- [x] The authenticated Pocket response includes only current, supported entry evidence for the same traveller and place.

## Verification plan

Run the focused C67 Simulator UI integration scenario with the synthetic Pocket fixture and the Pocket HTTP integration scenario with a disposable database. Verify only these integration tests.


## Result and handoff

- The iPhone 18 Pro Simulator (iOS 27.2, Xcode 27.2) passed `C67UITests/PocketEngineUITests/testItineraryMapPinShowsPlaceDetailsAndClearsThemWhenSwitchingStops` in mock mode with `--pocket-integration-fixture`. It checked the schedule against the itinerary and verified the complete and unavailable detail states. Result bundle: `/tmp/c67-map-pin-fourth.xcresult`.
- `python -m unittest discover -s server/pocket/tests -p test_hours.py -k HoursHTTPTests -v` passed using an isolated SQLite database and synthetic authentication and hours responses.
- See the [Pocket service notes](../../server/pocket/README.md#itinerary-map-place-details) for coverage. Live MapKit/Pocket metadata and physical-device behavior were outside these runs. The Pocket changes are local and require a separate deployment.


## Follow-up: Simplified pin card

The pin callout now shows the stop name, MapKit address, planned visit and Open in Maps. It no longer looks up or presents hours, contact information or entry rules from this surface. The C2 schedule block remained in use for the initial comparison of three layout mockups.

The mock Pocket scenario `testItineraryMapPinShowsOnlyPlaceAndVisitDetails` passed on iPhone 18 Pro Simulator (iOS 27.2). It verified the removed sections, the retained schedule and address, dismissal, and the next pin's address fallback. Result bundle: `/tmp/c67-map-pin-simplified.xcresult`.


## Follow-up: Compact layout selected

The selected compact layout places the planned visit beside Open in Maps. The card caps its width at 308 points and stacks the footer when horizontal space is insufficient. The focused mock Pocket integration scenario passed on iPhone 18 Pro Simulator (iOS 27.2) and checked horizontal alignment and the action's 44-point minimum height. Result bundle: `/tmp/c67-map-pin-compact.xcresult`.


## Follow-up: Pin callout motion

Selecting a stop scales and fades the compact callout in from the pin. Dismissal fades and slightly scales the card back toward the pin. Camera changes track the pin directly. Reduce Motion uses a short fade.

The focused mock integration scenario passed on iPhone 18 Pro Simulator (iOS 27.2). It exercised opening, dismissal and selecting a second pin. It did not measure frame timing or exercise the system Reduce Motion setting. Result bundle: `/tmp/c67-map-pin-motion.xcresult`.


## Follow-up: Map focus motion from the reference recording

Selecting a pin lifts the numbered marker, slides the compact card into the bottom dock, and centers the camera before zooming if the existing scale permits it. Dismissing the card restores the prior overview. Reduce Motion uses immediate camera positioning and a brief card fade.

The focused mock integration scenario passed on iPhone 18 Pro Simulator (iOS 27.2). It verified camera recentering, the bottom dock across stops, and dismissal. A Simulator recording confirmed the camera movement and card entrance. The system Reduce Motion setting was not exercised. Result bundle: `/tmp/c67-map-focus-verified.xcresult`.


## Follow-up: Anchored card with camera focus

The compact card follows the projected pin while the map zooms, recenters or pans. It opens with a spring and a slight tilt, and fades while shrinking toward the pin on dismissal. The camera returns to the overview after the dismissal transition. Reduce Motion retains a short fade.

The focused mock integration scenario passed on iPhone 18 Pro Simulator (iOS 27.2). It checked camera recentering, matching movement of the card and pin during a pan, dismissal, and opening a second pin. It did not measure spring timing or exercise the system Reduce Motion setting. Result bundle: `/tmp/c67-map-focus-anchored.xcresult`.


## Follow-up: Closer camera focus and stronger card spring

The camera targets 26 percent of the overview distance, bounded to 140–1,100 metres, and respects a closer existing view. Entry uses a stronger spring, a smaller initial scale, and an animatable tilt around the pin.

The focused mock Pocket integration passed on iPhone 18 Pro Simulator (iOS 27.2). It verified increased pin separation after zoom, recentering, and card tracking during a pan. It does not measure the spring trajectory. Result bundle: `/tmp/c67-map-pin-strong-focus-retry.xcresult`.
