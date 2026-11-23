# Travelants engine v5.2 release

Engine v5.2 batches transient opening-hours evidence in the iOS Pocket planner and shares the v5.1 schedule evaluator. New trips default to v5.2. Saved v5.1 proposals retain their recorded engine until an edit or replan succeeds. The hours client can use the single endpoint when an older server returns 404 for the batch route.

## Verification

- SwiftPM reported 191 tests, including one skipped opt-in benchmark. Two focused follow-up tests passed for schedule equivalence, v5.1 decoding, route edits and active replanning.
- The Pocket Python suite passed all 70 tests. Validation of OpenAPI and synthetic fixtures passed. The iOS Simulator passed 65 TripCreation tests and the v5.1 outdoor options and save regression.
- The paired timings remain in [Pocket opening-hours batch experiment](pocket-hours-batch-experiment.md). Six valid IDs use one Pocket request, one Auth lookup, and six provider lookups in the synthetic benchmark. Production end-to-end latency was outside this release verification.
- On 22 November the Pocket container moved to `c67-pocket-beta-pocket:hours-batch-20261122` and kept its persistent volume. The release applied the hours changes to the previously running code. Ten hours tests passed in the candidate container. Nginx validated and reloaded its configuration.
- Public health returned 200. The two hours paths and account deletion rejected unauthenticated requests with 401. An existing demo session returned the same results through the batch and single endpoints for three public fixtures. One supplied validated regular hours, one had unavailable data, and one returned a temporary provider error. Rollback and verified backups are in the homelab staging directory `/home/giovan/apps/c67-pocket-beta/staging/hours-batch-20261122`.

## TestFlight candidate

Travelants app version `1.0.1`, build `202611221150`, with engine v5.2. The device archive built successfully and passed the local signing verification. Record Apple processing, group assignment and Beta App Review status when verified.

Suggested What to Test

- Create an itinerary with six places. Review which stops have regular opening hours and which hours still need confirmation.
- Open a trip saved with Travelants v5.1. Change the departure date and verify the resulting itinerary shows Travelants v5.2 in Trip details.
- Change the order of an existing itinerary. Check that all selected places remain in the plan and any reservation or outdoor notes are still visible.

App Store Connect accepted the upload at 12:23 WIB. The build initially showed Processing. The final Simulator comparison reached itinerary review in all three configurations. With three fixture stops, v5.1 with fresh connections took 2.84 s, v5.1 with reused connections took 2.86 s, and v5.2 with the batch endpoint took 2.83 s. Each configuration ran once. The measurements include XCTest interaction and accessibility polling.
