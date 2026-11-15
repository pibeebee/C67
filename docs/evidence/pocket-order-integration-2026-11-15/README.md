# Native reasonable ordering integration — 15 November 2026

The new maintained path is implemented locally. The existing native UI calls
asynchronous Luna order jobs and can review/save an untimed experience plan.
**Live successful end-to-end acceptance remains unverified:** the single actual
five-place request in this integration run ended with upstream HTTP 524.

## Executed checks

| Layer | Result | Evidence |
| --- | --- | --- |
| Python service, ordering and authenticated HTTP | 39 tests passed | `/private/tmp/c67-order-server-v2.log` |
| Swift backend/domain, persistence, retry and contract decoding | 63 tests passed | `/private/tmp/c67-order-backend-final-v3.log` |
| Creation/preferences app unit cases | 44 passed | `/private/tmp/c67-order-ui-final.xcresult` |
| Native synthetic UI | 3 passed | Same final result bundle |
| Final Simulator build | Passed after active-trip duration override fix | `/private/tmp/c67-order-build-final.log` |
| API/fixture validation | Passed | `scripts/check_contracts.py` |
| Pinned formatter | Passed, 662 files | `/private/tmp/c67-order-format-final.log` |
| Actual five-place UI → server → Luna attempt | Failed: provider HTTP 524 | [Recorded metadata](live-attempt.json) |

Simulator: iPhone 18 Pro Max, iOS 27.2, Xcode 27.2; minimum deployment remains iOS
18. Dedicated XcodeBuildMCP tools were absent, so verification used xcodebuild,
xcresulttool and native XCUITest. Earlier failed compiler/test runs were corrected:
a large SwiftUI expression was split, and a historical availability-blocking unit
expectation was updated to the newly authorized untimed flow. The final synthetic
run passed; that does not turn the actual-provider failure into success.

The three synthetic UI cases verify every selected place is retained, unknown
activity/duration does not open an availability form, review/save works, endpoint
editing remains available, and settings do not reveal the read token. Backend
checks separately verify rename without another generation, protected local
save/reload/start, request identity on disconnect, terminal failure without
regeneration, larger/manual selection and server payload decoding. The final
active-trip view also honors the user's duration override.

## Actual provider attempt

One request contained the five public selections from the earlier failure:
Taman Bendera Pusaka, Tatemukai Signature Omakase Sushi, National Library of
Indonesia, Night market and Memorial Coffee Cipondoh. No main spot was forced.
The maintained server retrieved five Open-Meteo source records and calculated ten
light windows for the app candidate date. It then called Luna once.

Logs record start at 08:11:18.486 WIB and HTTP 524 at 08:13:23.670 WIB: approximately
125.184 seconds for the provider attempt. No completed answer was returned, so no
live order or live trip was saved. The screenshot shows all five selections kept
and an explicit retry action. No second provider attempt, fallback model or
invented result was used. Private request/source snapshots and credentials remain
outside the repository.

- [Synthetic review screenshot](synthetic-review.png) — explicitly synthetic data.
- [Actual failure screenshot](live-provider-failure.png) — provider failure with selection retained.
- Local result bundle: `/private/tmp/c67-order-runtime-ui.xcresult`.

A successful real generation followed by review/save is the remaining acceptance
step when the provider can complete a request. Shared deployment, container runtime,
physical iPhone, TestFlight and later Hi-Fi adjustments were not part of this run.
