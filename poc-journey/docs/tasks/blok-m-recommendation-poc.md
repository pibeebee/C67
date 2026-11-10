# Blok M recommendation evaluation

Status: Implemented, scripted device checks passed, pending human/manual acceptance
Owner: Hendra / Codex implementation
Reviewers: Two independent human reviewers pending assignment
Branch at start: hendra/poc-fm-mapkit

## Outcome

Evaluate profile sensitivity and sourced relevance in Trip Integration, then exercise recommendation, location review, routing, weather, accept/reject, revision and export. The approved plan uses synthetic contrasting personas, Bundaran HI return trips by automobile, existing preference features, and a 1.5 km Blok M catchment.

## Scope and dependencies

- Only poc-journey may change. Preserve unrelated local work.
- Add a dated sourced catalog, explicit Debug entry points, isolated evaluation output, deterministic tests, evaluator and protocol.
- Real MapKit calls are authorized by implementation of the live evaluation plan. Signed-device WeatherKit still needs matching operator provisioning.
- Human judgments and physical network interactions require real reviewers/operator observations. Never substitute generated grades or scripted results for these.
- No commit, push, deployment or shared backend change is authorized.

## Acceptance criteria

- [x] Dated venue/source inventory with unknowns and geographic verification.
- [x] Explicit Blok M configuration with isolated storage and historical default compatibility.
- [x] Production-pipeline generic/category/combined comparison with separate reviewer labels.
- [x] Hard-gate, temporal, revision, fallback and location regressions.
- [x] Replay UI and build checks, plus separately labeled provider evidence.
- [x] Reproducible report with measured outcomes and pending human/device layers.

## Verification

Use the journey verification script for packages/build/UI, the focused Blok M evaluator, Swift layout check, portability and git diff --check. Keep new raw outputs in .verification. See the application Blok M protocol for cases and thresholds.

## Result and handoff

Implemented the dated 13-candidate catalog, explicit Debug modes, catchment/branch validation, category/general/E5 evaluator, isolated provider/session outputs, 12 new Swift tests, eight scorer tests and blinded reviewer materials. All 232 package tests and three Trip Integration Simulator UI cases pass. Three unsigned Simulator builds pass. Real Mac 1/3/6-place routes pass with unavailable WeatherKit. Thirty-six recommendation comparisons are exported without generated human grades.

The Foundation Lab's dated UI preset exposed a real-clock dependency. Corrected only the `--timing-ui` non-provider evaluation clock without moving historical dates. The combined rerun passed all nine Foundation Lab and all three Trip Integration cases, giving 12/12 UI tests. A final focused unsigned build also passed.

The first signed iPhone build was blocked by Apple's agreement/provisioning setup. After the user activated WeatherKit, signing for Team K39QVFTK2A and com.hendra.pocjourney succeeded. iPhone 17 / iOS 27.2 passed primary-only WeatherKit diagnosis and all 11 scripted cases. Ten plan artifacts and revision envelopes passed independent inspection. Human reviewer grades and physical network/background/input-change observations remain pending. No commit or push was performed.

See [protocol](../../apps/c67-trip-integration/docs/blok-m/PROTOCOL.md) and [execution report](../../apps/c67-trip-integration/docs/blok-m/REPORT-2026-11-06.md).
