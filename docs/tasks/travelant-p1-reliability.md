# Task: Improve Travelant P1 reliability

Status: Implemented locally, runtime acceptance pending

Branch: `gi/travelant-p1`

Baseline: `e6eb38d`

## Outcome

- Pocket and iOS retry final job writes while retaining computed results in memory. A Pocket ordering job without a worker or retained result becomes interrupted. Client polling uses a six-minute deadline and increasing intervals. Cancellation releases the local planning slot and keeps the draft.
- Pocket adds stable error codes to existing HTTP statuses. Authenticated requests distinguish missing or expired sessions from temporary service errors.
- Date changes revalidate a replacement schedule and obtain fresh dated estimates as needed. A validated date can be returned when a different candidate date fails during comparison.
- Start uses the trip timezone and revision. A different date requires a revised itinerary. A changed same-day schedule is reviewed before start. Active replanning runs without model calls, reuses accepted durations, and preserves actual visit progress and the original endpoint.
- A trip with an endpoint stays active until endpoint arrival. Foreground GPS confirmation requires two fresh samples for the current target. Manual confirmation remains available.

## Verification

- Swift package tests on macOS: **149 passed**. Regressions include final-write recovery without a second provider call, cancellation, partial date comparison, new date enrichment, start on a different date, and an extended visit followed by model-free replanning and endpoint completion.
- Pocket Python tests with loopback HTTP and temporary SQLite: **64 passed**, including owner-scoped recovery from a failed result write.
- OpenAPI and fixture validation, SwiftFormat lint, and `git diff --check` passed.
- Xcode `build-for-testing` succeeded for the generic iOS Simulator destination in mock mode. The targeted UI run could not start because Xcode and CoreSimulator had no available runtime destination. The foreground GPS and endpoint UI still require runtime acceptance.

### Simulator verification on 2026-11-19

- `C67AppTests/TripCreationTests` covers saved-date changes, confirmation of a changed same-day schedule, explicit application of a replan, and manual endpoint arrival after reopening the saved trip from disk.
- `C67AppTests/SplashAndLocationPermissionTests` adds boundary cases for the timestamp, distance, and accuracy of a GPS fix.
- `C67UITests/PocketEngineUITests/testFutureSavedPocketTripOffersDateEditorBeforeStarting` exercises the date recovery action from a saved Pocket trip.

On iPhone 18 Pro Max Simulator, iOS 27.2, the serial `C67AppTests` run passed 143 tests with 5 skipped. This includes both new trip regressions and the GPS sample boundary test. The focused future-trip UI test passed twice after updating its fixture to select the required three places and use the current Next button. It covers saving a future trip, the date mismatch message, and opening the date editor; it does not exercise calculating and applying the revised schedule.

An initial broader `PocketEngineUITests` run timed out after 300 seconds, with multiple failures in older scenarios; several use fewer than the current minimum of three recommendations. One location-distance UI scenario passed. These failures remain to be triaged individually. An initial parallel app-test run was killed by the system; the serial rerun passed. All Simulator scenarios use synthetic fixtures. Automatic GPS arrival, active-trip UI, and physical-device behavior remain unverified.

## Rollout gate

Run the focused Simulator suite when a runtime is available. Walk through sign-in, Pocket planning, interrupted polling, same-day start, active replanning, relaunched endpoint navigation, and manual arrival on a signed device against a compatible Pocket deployment. Measure time until itinerary review and record failures by layer. The server and TestFlight rollout are separate release actions.
