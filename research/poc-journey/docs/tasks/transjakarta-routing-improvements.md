# TJ routing improvements and paired evaluation

Status: Complete for the bounded routing improvements and deterministic evaluation.
Owner: Hendra / Codex

## Authorized outcome

Implement the recommendations to reduce avoidable infeasibility and measure before/after behavior. Keep the work in the journey POC and evaluate routes, walking, time budgets, transfer proof and user-facing corrections through the existing itinerary pipeline.

## Implementation decisions

- Replace nearest-two discovery with ordered route connectivity and up to 64 candidate paths per direct/transfer stage within the existing 800-metre access radius. Keep 128 walking lookups per calculation and 20 minutes per walking component.
- Import complete TJ patterns inside the existing Jakarta boundary from the original captured ZIP. Retain operator/category identity, calendars and unconditional pickup/drop-off permissions. Scheduled exact-times service is recorded as an exclusion.
- Prefer a feasible direct service. Search up to one transfer when direct service fails. Require an attributed interchange candidate, validated walking, a two-minute authored transfer buffer and a full headway for each boarding.
- Prioritize provider-verified walking up to 15 minutes for local itinerary legs to keep multi-venue request usage bounded. Prune an alternative after its bus arrival cannot beat an existing complete journey, using nonnegative walking as the lower bound.
- Retry eligible transient walking errors once under the existing pacing and total-request cap. Cache validated walking within one calculation. Propagate cancellation and invalid provider evidence explicitly.
- Add early dwell-budget checks and explicit UI actions to extend the day or shorten stays. Preserve chosen venues for recalculation. Expose the existing sourced Jakarta catalog and configurable live origin.
- Preserve old journey decoding with an optional second-ride connection. Audit transfer source membership, show both rides in the UI and retain transfer components in JSON/Markdown exports.

## Evaluation

Use the frozen pre-change planner in the test target for paired comparisons. Measure 200 adversarial platform inputs, 100 nearby-destination inputs, 199 source-route endpoint pairs and two official two-corridor connections. Record feasible recovery, regressions, synthetic walking calls, candidate bounds and per-leg calculation timings. Check one-transfer itinerary acceptance/save/reload/export and the existing 64-case/1,000-input suite. Verify package tests, script tests and Showcase Simulator behavior.

Run `rtk proxy python3 poc-journey/scripts/evaluate_transjakarta_improvements.py --output poc-journey/.verification/YOUR_NEW_RUN` from the repository root. The output directory must be new. Historical v1/v2 manifests and captured reports remain available. Active compatibility probes use v3. Legacy single-route gate counts and active network routing coverage are presented separately.

## Remaining acceptance

The selected defaults require live-provider and field calibration. Two or more transfers, geographic expansion beyond the existing boundary, scheduled exact-times service, verified accessible entrances and holiday exceptions require further implementation/data. Waiting-buffer calibration depends on field or verified realtime evidence. The implemented runtime uses a conservative full-headway policy.

Commit, push and deployment are outside this local task.

## Verified result

Platform-search inputs improved from 20/200 feasible to 200/200. Source-network endpoint pairs improved from 12/199 to 195/199. Two official one-transfer corridor pairs improved from 0/2 to 2/2. All 501 paired inputs had zero feasibility regressions. The remaining four source-route requests have inactive calendars on the tested Saturday, with bounded alternative search recorded separately.

All 256 package functions, 39 Python tests, 15 Showcase Simulator tests and the existing TJ review/accept UI test passed. All four POC apps built for Simulator. The active compatibility suite and original exact-platform sweep remain captured with their original deliberate invalid inputs. Field transfer access, live waiting calibration and dedicated transfer UI interaction remain acceptance gaps. [Dated report](../../apps/c67-trip-integration/docs/transjakarta/IMPROVEMENTS-REPORT-2026-11-06.md)
