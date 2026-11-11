# Task: Evaluate focused English Foundation Models workflows

Status: Complete for exploratory local evaluation; independent review and device tests pending
Owner: Hendra / coding assistant
Reviewers: Independent human review pending

## Outcome and scope

Test task-specific generation, minimal context, focused schemas, deterministic safety gates and templates, and separate read-only tool behavior. Work only in the evaluation directory and this evidence brief; preserve existing product code and prior results. Synthetic inputs only; never provide grading expectations to the model. This is not product integration or an approved architecture decision.

## Acceptance and checks

- Run an explicit on-device model with English availability preflight, frozen inputs and recorded raw outputs, latency and tool traces.
- Compare matched cases with the earlier broad-context run and include new English cases; report model correctness separately from harness routing, templates and validators.
- Test tool success and unavailable fixtures without live data or silent cloud fallback. Record unsupported or untested layers.
- Validate harness logic, data integrity and whitespace; do not claim physical iPhone, two-human review, app guard or production provider acceptance.

## Result

See [focused evaluation report](../../evaluations/foundation-models-2026-11-04/focused-english/REPORT.md), raw runs, tool traces, provisional assessments, experimental guard tests and deterministic templates in the same directory. The experiment does not modify app behavior or prove end-to-end task routing. No deployment, commit, push, physical iPhone, real provider, independent human review or production guard test was performed.
