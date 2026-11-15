# Restore Pocket itinerary requests in the normal app

Status: Verified locally on iPhone 18 Pro Max Simulator with iOS 27.2

Branch: `gi/pocket-ui`

## Outcome

Missing or rejected Pocket configuration gives a settings action. A server job can keep running after **Continue later**. The app retains the draft and resumes the same request when the user reopens it. The app reads the saved result if the server already completed the request. A confirmed failure provides an explicit recovery action.

## Diagnosis

The Simulator had no Pocket read token. The two screenshot jobs had failed locally and neither request ID existed in the local Pocket server database. The original client collapsed missing configuration and several other errors into `ORDER_GENERATION_FAILED`. The local server was also offline when inspected. The earlier live acceptance injected its connection through a harness and did not verify regular app configuration.

## Verification

- The normal app reopened the exact five-place draft and offered **Open Pocket settings** without a token. One UI test passed.
- The configured normal app used its Keychain connection and the local Pocket server. The UI test started the screenshot's five-place request, tapped **Continue later**, terminated and relaunched the app, resumed the draft and verified all five places in the itinerary. One live UI test passed. There was one server job and one Luna call. The server logged 136.155 seconds from request start to completion.
- The Swift package passed 64 tests, including a regression for keeping the draft and preserving the missing-configuration error. Simulator build, SwiftFormat and whitespace checks passed.
- The earlier temporary provisioning filter ran zero Swift tests. The corrected suite executed the Keychain provisioning probe successfully before the live test. The temporary app and UI probes were removed after building the verification runs.

[Verification summary](../evidence/pocket-order-recovery-2026-11-15/summary.json) · [Missing-connection UI log](../evidence/pocket-order-recovery-2026-11-15/missing-connection-ui.log) · [Live resume UI log](../evidence/pocket-order-recovery-2026-11-15/normal-live-resume-ui.log) · [Server log](../evidence/pocket-order-recovery-2026-11-15/server.log)

Evidence covers the local Simulator and the loopback Pocket development service with live Luna. The Simulator now has the development read token in the app's Keychain. A physical iPhone requires its own configured Pocket connection. Server work continues while the Pocket service remains up. Remote deployment was outside this task.
