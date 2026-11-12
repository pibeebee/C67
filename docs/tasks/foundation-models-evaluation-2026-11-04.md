# Task: Evaluate on-device Foundation Models for C67

Status: Ready for review; human review and device controls pending
Owner: Hendra / coding assistant
Reviewers: Two human reviewers needed for semantic and recommendation grading
Branch: hendra/poc-fm-mapkit

## Outcome

Evaluate the supplied 32-case synthetic protocol against Apple's explicitly selected on-device system model. Provide the raw runs, executable harness, environment and prompt/schema hashes, per-case disposition, limitations and a capability-by-capability recommendation.

## Scope and dependencies

- Work in `evaluations/foundation-models-2026-11-04/`, this task and the verification record. Do not change C67's implementation, solver, persistence or deployment.
- Only the package's model instructions, one case's context/history/user message and registered local tool outputs may enter the model. Keep the evaluator key outside model requests.
- An unsupported locale blocks claims of supported-product accuracy; explicitly label any exploratory runs in that locale as diagnostic.
- The experiment uses synthetic fixtures, local device inference and no shared data. No commit, push or deployment is authorized by this task.

## References

- User-supplied `foundation-models-evaluation-2026-11-04` package and its tester prompt.
- [C67 architecture](../architecture.md); [TripSense feasibility](../../tripsense-poc/FEASIBILITY.md).

## Acceptance criteria

- [x] Record availability, platform, locale support, runtime settings and prompt/schema/fixture hashes.
- [x] Run a sanity case, preserve tuning attempts, freeze the adapter and run eligible cases with the prescribed repetitions. Report blocked and diagnostic cases separately.
- [x] Preserve raw outputs, tool calls, errors and latency without hiding retries or fabricating semantic review.
- [x] Separate model results, local evaluator safeguards, provider dependencies and physical-device evidence.

## Verification plan

Compile the isolated Swift harness, perform real on-device inference with process network access denied, inspect the raw run records and validate output against the supplied contract. Check file integrity and whitespace. Explicitly record any untested system-wide offline, user research, human-review or iPhone controls.

## Result and handoff

- [Report](../../evaluations/foundation-models-2026-11-04/REPORT.md), [case dispositions](../../evaluations/foundation-models-2026-11-04/series-v4/case-status.md), [raw assessed runs](../../evaluations/foundation-models-2026-11-04/series-v4/assessed-runs.jsonl), [manifest](../../evaluations/foundation-models-2026-11-04/series-v4/manifest.json), [freeze](../../evaluations/foundation-models-2026-11-04/series-v4/freeze.json) and [controls](../../evaluations/foundation-models-2026-11-04/series-v4/controls.json).
- Runtime selected `SystemLanguageModel.default` on an Apple M5 Mac. `id_ID` was unsupported; its 31 cases are blocked for product scoring and each was attempted once only as a diagnostic. The English control was run ten times with one timeout; all nine responses failed exact action-field matching.
- The first schema used optional rather than required nullable fields. Its results are preserved separately; the corrected v4 uses an SDK dynamic schema checked against the contract. Because the evaluator had already seen the initial results and key, v4 is exploratory, not a fresh holdout.
- A Mac offline control returned one English M1 response and one Indonesian diagnostic M2 response while Wi-Fi and Ethernet were disabled and no active network interface was reported; both services were restored. M2 made no tool call, so offline fixture-tool execution was not established. No two-human semantic review, target-iPhone inference, actual unavailable-device test or product validator/fallback test was performed.
- The harness compiled and its formatted working copy typechecked. The repository-wide formatter still reports a pre-existing `tripsense-poc/App/TripSenseApp.swift:31` indentation issue; no existing product source was changed.
- No commit, push, deployment or shared mutation performed.
