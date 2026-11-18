# Hybrid v4.2: Luna and Foundation Models test — 18 November 2026

This file records the historical runs with different provider inputs.
The [controlled Simulator benchmark](hybrid-v42-performance.md#controlled-simulator-comparison)
supersedes the procedure for any new matched comparison.

## Scope and outcome

The provider isolation and deterministic scheduler tests ran on macOS: six
tests passed. These use synthetic provider responses; they do not measure
either model's inference speed or assess the quality of its advice. When both
providers supply identical advice, the test verifies identical schedule times,
stop order, durations and route call count for its fixture. It also verifies
provider-specific snapshots, manual durations, unavailable-model handling,
and validation of generated response mappings.

The physical-device comparison ran on Giovan's iPhone 17, iOS 27.2.1, with
two Jakarta scenarios and one repetition per method. Both arms shared synthetic
10-minute travel estimates and unavailable opening hours. The Luna connection
was deliberately set to a localhost placeholder because the actual Pocket
server URL and test credentials were not available to the runner. Both Luna
arms failed to connect; this is a test configuration failure and is not a
measurement or diagnosis of Luna or the production service. Xcode reports
the combined test as failed with two issues. No valid Luna comparison exists.

## Foundation Models observations

| Scenario | Model call | Complete job | Route calls | Outcome |
| --- | ---: | ---: | ---: | --- |
| Manual day | 5.840 s | 5.869 s | 37 | Succeeded |
| Two candidate days | 4.256 s | 4.340 s | 14 | Succeeded |

In both cases the resulting order was Museum Nasional Indonesia, Taman Literasi
Martha Christina Tiahahu, then M Bloc Space. Visit durations were 45, 75 and
75 minutes; the first duration was manually locked. The first scenario chose
19 November, departing 11:00 Jakarta time; the second chose 20 November,
departing 09:00. These are single observations, not a latency distribution.

Both results passed the test's feasibility, selected-place coverage, first-stop,
finish-time and manual-duration checks. The model inferred suggested activities
from names and preferences. Venue activities and practical usefulness were not
independently verified. No real travel estimates, opening hours, weather, or
solar data were used by the Foundation Models arm. Luna normally receives
server-provided weather and light context, so even a complete run compares the
current app paths rather than models given identical context.

## Authenticated physical-device rerun

An authenticated rerun used the existing device session without exposing the
access token. Pocket health returned HTTP 200 and both Luna requests reached the
server, but both returned `POCKET_ORDER_METHOD_UNSUPPORTED`. Read-only
inspection confirmed the healthy active `c67-pocket-beta-pocket:v4-20261117`
container accepts `hybrid_v4`, but does not accept `hybrid_v4_2`. Thus this is
a server version mismatch, not evidence that the Luna model failed. The server
was not changed. The authenticated combined test failed with two issues.

In that rerun Foundation Models succeeded again: manual day 5.509 s model /
5.586 s job, two candidate days 4.235 s model / 4.342 s job. The same itinerary
order and durations were returned as above. The reported 0.516 s and 0.404 s
Luna job failures are rejection times, not Luna inference timings.

The local Xcode result and log for the first partial run
are `/tmp/c67-v42-device-comparison.xcresult` and
`/tmp/c67-v42-device-comparison.log`; they are temporary and may contain device
diagnostics, so they should not be published. The authenticated rerun artifacts
are `/tmp/c67-v42-auth-debug-comparison.xcresult` and
`/tmp/c67-v42-auth-debug-comparison.log`, with the same handling restrictions.

## Simulator comparison using local v4.2 Pocket

On 18 November, a temporary loopback Pocket server ran the current local v4.2
code and contacted Luna; it was stopped after the run. The shared Pocket server
was not changed. Both methods ran in the iPhone 18 Pro Max Simulator (iOS 27.2)
with the same two three-place Jakarta fixtures, dates, preferences, manual
45-minute first stop, synthetic 10-minute ETAs, unavailable hours and v4.2
scheduler. Two repetitions alternated method order. This is an app-path
comparison, not a perfectly controlled model comparison: Luna also received
three weather sources and six light entries; Foundation Models received none.
The model prompts, transport and hardware execution also differed.

| Scenario | Repetition | Luna job | Foundation Models job | Outcome |
| --- | ---: | ---: | ---: | --- |
| Manual day | 1 | 74.941 s | 1.713 s | Luna succeeded; Foundation Models failed |
| Manual day | 2 | 72.791 s | 7.662 s | Both succeeded |
| Two candidate days | 1 | 95.199 s | 5.647 s | Both succeeded |
| Two candidate days | 2 | 115.288 s | 20.664 s | Both succeeded; Foundation required retries |

These are complete job times, including provider attempts and scheduling, not
the time to render a screen. The failed Foundation attempt is not an inference
latency. The second two-day Foundation job included one failed batch attempt
(10.937 s) followed by two successful calls (4.966 s and 4.658 s). On the
first failed attempt Simulator logs included `Simulator is not supported`;
subsequent generations nevertheless succeeded, so this run does not establish
the root cause or a reliable Simulator failure rate. The suite reports failed
overall because it recorded the one failed Foundation job. Luna succeeded 4/4;
Foundation Models succeeded 3/4. A sample of four cannot support robust
latency percentiles or reliability conclusions.

All successful proposals passed the harness's structural, schedule-window,
place-coverage, first-stop and manual-duration assertions. In manual repetition
2, Luna returned order [museum, park, M Bloc], while Foundation returned
[museum, M Bloc, park]. For both two-day repetitions Luna returned [museum,
M Bloc, park], while Foundation returned [museum, park, M Bloc]; all chose
20 November 09:00 Jakarta time. Luna's park duration was 30 and 22 minutes;
Foundation's was 67 minutes in both. Luna discussed rain while Foundation had
no weather context. Luna produced Indonesian suggestions despite English
preferences; Foundation's suggestions were English. No human quality scoring,
venue-fact verification, actual opening hours or real MapKit ETA validation was
performed. Neither structural feasibility nor greater speed proves equivalent
recommendation quality or real-world usability.

Simulator Xcode result and log: `/tmp/c67-v42-simulator-comparison.xcresult` and
`/tmp/c67-v42-simulator-comparison.log`. Local Pocket timing log:
`/tmp/c67-v42-local-server.log`. Temporary results may contain diagnostics or
trip content; do not publish without review. The active shared Pocket server
still needs a separately reviewed v4.2 deployment for normal app use.
