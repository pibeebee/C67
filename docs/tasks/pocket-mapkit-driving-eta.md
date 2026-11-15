# Calculate driving ETAs and reroute a manually reordered Pocket itinerary

Status: Implemented and verified locally on 15 November 2026.

Branch: `gi/pocket-ui`

## Outcome

The device calls the existing Apple MapKit `MKDirections.calculateETA()` adapter
in automobile mode for the origin and successive stops. It supplies successive
planned departure times derived from travel and visits. The map service supplies
time and road distance. Identical points require no travel. Missing quotes display
the six-minute default explicitly and leave distance empty. One throttling
response suppresses remaining calls for that run. The user can refresh missing
ETAs. Old planned trips can acquire ETAs on their first open.

Manual reorder validates the exact set of places and updates the existing job,
proposal and selected places in one local write. Luna output and per-place
context remain attached to the proposal and there is no new ordering request.
Recent estimates can be reused when the directed leg and planned departure
still match. The departure-time editor recalculates only MapKit estimates.
No server contract or deployment is required.

## Verification

- 67 Swift package tests passed, including one-call ordering, manual reorder,
  reused and changed legs, fallback, and persistence.
- Two focused UI tests with synthetic venues/ETAs passed on iPhone 18 Pro Max
  Simulator, iOS 27.2. They exercised drag, retained stop set, save, and start.
- The production MapKit adapter returned real ETAs and road distances for
  three fixed public Jakarta pins on macOS. Reversing the order produced
  different routes. Initial ordering was a synthetic fixture instrumented to
  count calls. The count stayed at one, with no actual Luna requests.
- The initial incremental Xcode run loaded stale domain artifacts. The focused
  UI run passed using a fresh DerivedData directory.
- ETA evidence is a point-in-time quote. Physical iPhone and TestFlight
  execution were outside this check.

[Live MapKit log](../evidence/pocket-mapkit-routing-2026-11-15/live-mapkit.log) ·
[Simulator summary](../evidence/pocket-mapkit-routing-2026-11-15/simulator-summary.json) ·
[Swift log](../evidence/pocket-mapkit-routing-2026-11-15/swift-summary.log) ·
[Apple MapKit ETA](https://developer.apple.com/documentation/mapkit/mkdirections/etaresponse)
