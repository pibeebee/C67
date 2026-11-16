# Task: Compare itinerary planning methods in Pocket settings

Status: Experimental implementation available in TestFlight and deployed server; live end-to-end acceptance pending
Owner: Unassigned
Reviewers: iOS, Pocket server, planning/contract owners
Branch: `gi/ui-audit-improvements` (existing checkout; verify current state before continuing)

## Outcome

Allow testers to select Luna, the earlier candidate-selection hybrid, or the newer weather-aware hybrid in Pocket settings and generate a trip using the selected method. Label experimental behavior and uncertainty truthfully; never present synthetic data as live. Preserve all selected place IDs exactly once.

## Scope and dependencies

- Add a persisted per-device method selection and snapshot it into each new planning request. Existing saved jobs and retries must retain their original method, never silently change after settings change.
- Evolve client/server order request and job identity compatibly. Unknown method values and older servers must produce an actionable error, never silently run Luna instead. Maintain existing Luna as default for older saved inputs and clients; keep model validation intact.
- Implement actual candidate-generation/selection for both hybrids in the Pocket server, including all selected IDs and explicit order locks. Old hybrid selects a bounded deterministic candidate menu. New hybrid augments it only with legitimately available, correctly scoped data: unknown exposure remains unknown; no unsupported indoor/outdoor claims or synthesized road ETA/weather. Candidate limits and fallback must be explicit and not reinstate six-place product limits.
- The existing order request sends date but not start time, activity-level exposure, or ETA matrix. The current hourly forecast model does not carry apparent temperature or UV. The new hybrid cannot truthfully reproduce the weather experiment without adding and validating these inputs and provider availability; do not treat coordinates as road ETA or category as exposure evidence. The benchmark additionally used synthetic fixed durations and synthetic area selections.
- UI must allow testers to understand which method ran and that hybrid methods are experimental. Reorder and departure edits must not invoke a new order; preserve session/job recovery and cancellation behavior.
- Server deployment is separate and not authorized by this local implementation task. Do not connect a new client to an older deployed server as if the methods exist. No production accounts, credentials, actual locations or user data in fixtures.

## References

- [Pocket engine integration](../guides/pocket-engine-integration.md)
- [Pocket reasonable ordering](pocket-reasonable-order-integration.md)
- [Contract](../../contracts/api/openapi.json)
- Workspace experiment: `poc/hybrid-weather-comparison/REPORT.md` (outside this repository checkout).
- Workspace weather experiment: `poc/indoor-outdoor-heat-lab/REPORT.md` (outside this repository checkout).

## Acceptance criteria

- [ ] All three settings select genuinely distinct implementations and persist across relaunch; the selection is visible on generated result and snapshotted at job creation.
- [ ] Old and new hybrid candidates retain every selected place exactly once and respect explicit order constraints, including more than six places.
- [ ] Unknown activity exposure cannot be presented as confirmed indoor/outdoor, or used as proof of reduced exposure; weather and travel data gaps remain visible and do not remove stops.
- [ ] Candidate choice, reasons and source references are validated against actual inputs and computed evidence. Unsupported claims are rejected or disclosed; the selected method cannot be silently substituted.
- [ ] Existing Luna request and older persisted job behavior remain compatible; changed-input retries, cancellation, asynchronous recovery and identity are tested.
- [ ] Simulator checks cover changing settings, creating trips through all three choices using a local synthetic server, and retry/failure behavior. Clearly distinguish local synthetic evidence from live provider/deployed evidence.

## Verification plan

Run focused server tests for each strategy, weather/exposure gaps and identity; `swift test --package-path packages/C67Backend`; relevant contract validation; iOS Simulator build and interaction tests in explicit mock/local test mode; `python3 scripts/swift_format.py --check`; `git diff --check`. Record exact results, runtime and outstanding live-provider/server deployment limits.

## Result and handoff

- Implemented locally: persistent Settings choice, request/job method snapshot and server echo, bounded deterministic candidate selection for both hybrid variants, rejection of unoffered orders, lock handling and basic server validation. Results show the selected method in Trip details. The default preserves Luna compatibility. A server without matching method echo is rejected rather than silently substituted.
- **Incomplete:** weather-aware hybrid is a limited contextual prototype, not the tested weather-comparison algorithm. It explicitly reports that exposure and candidate arrival times are unknown and therefore no heat/rain exposure comparison was performed. The current request does not carry evidence-backed per-activity exposure, candidate ETA, duration or the necessary hourly apparent-temperature/UV inputs. Do not represent it as a validated weather-aware planner or ask teammates to compare real weather outcomes yet. Candidate choices and explanations have not been independently assessed.
- Checks: 25 focused Python ordering tests passed, including local HTTP jobs through all three methods with a synthetic model. One earlier run logged a background SQLite cleanup error; the final rerun passed without that error. 73 Swift package tests, OpenAPI/fixture check, SwiftFormat and `git diff --check` passed. One iPhone 18 Pro Max/iOS 27.2 UI test in synthetic fixture mode opened Settings and selected a method. iOS-to-server end-to-end and live provider checks remain outstanding.
- Next: implement real evidence-scoped exposure, WeatherKit/Open-Meteo fields, bounded time-dependent candidate ETA and weather comparison; test all three selections against an isolated server end-to-end. Deploy only with separate authorized operational scope.
