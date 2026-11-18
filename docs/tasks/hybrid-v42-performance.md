# Hybrid v4.2 planning latency

Status: Local implementation and compile-only verification. Owner and reviewer to be assigned by the project team.

Hybrid v4.2 is opt-in in the itinerary method picker. The iPhone uses the same
schedule search, ordering rules, time-specific travel validation, and quote limits
as v4.1. It prepares up to two regular-hours lookups at a time while Luna runs
and reuses the weekly evidence for the dates in the same job. User-confirmed
access and booked visits retain their existing meaning.

The Pocket contract adds a compact Luna request. One request accepts up to three
candidate dates and asks for shared activity/duration estimates plus per-date hints
and overrides. Each returned plan binds only evidence from its own date.
Malformed batch responses can fall back to individual compact requests. The
same Luna model and completion validation apply. Supplying all durations still
allows itinerary generation without Luna. Luna assistance in v4.2 requires the
updated Pocket server.

Use the iOS unified-log category PlanningTiming and Pocket order_timing and
order_complete events. Join the app's request_id to its order_id through the
luna_round_trip event and then look up the order_id on Pocket. itinerary_visible
measures the successful first-itinerary flow through the review screen appearing.
The logs include elapsed time and counters. They omit selections and user text.
Compare median and p95 for matched routes, dates, and user inputs alongside
feasibility, user constraints, and quality of duration and activity advice.

The supplied Swift and Python cases use synthetic responses. Run them in a later
authorized test session, then measure latency and itinerary quality with live
providers on an iPhone. Keep the recorded v4.1 behavior as the comparison.

Local checks passed with Xcode 27.2 and Python 3.12. The C67 scheme built for
testing against the generic iOS Simulator destination, and SwiftPM built the
package and its tests with `swift build --build-tests`. Python byte compilation
covered `server/pocket/src` and `server/pocket/tests`. The OpenAPI and fixture
contract check, pinned SwiftFormat check, and `git diff --check` passed. No test
case, app, simulator, or provider was run for this checkpoint.
