# Task: Test reasonable ordering without ETA or venue hours

Status: Experiment completed; human/product acceptance pending. Owner: Codex. Reviewer: Giovan. Branch: existing `gi/pocket-ui`.

## Outcome and authorized scope

Eight headless calls to external Luna. No UI, Simulator, provider substitution,
web research, ETA/route APIs, application changes, deployment, commits or pushes.
Reuse original five selected IDs/names/pins. Keep absent category metadata absent.
Controlled preference/origin/endpoint fixtures use the current preference fields
where possible; diagnostic free-text wishes use the existing prose concept.
No new product form is introduced. No fabricated durations or timed windows.

## Cases and evaluation registered before live calls

1. Baseline: all five destinations, preference-based experience flow.
2. Shuffled input: same preferences and pins, altered list order only.
3. Preference change: natural-language request to begin at the reading main spot.
4. Origin change: change origin only to the western endpoint area.
5. Experience/geography conflict: library before Memorial before Tatemukai,
   accepting a detour; other selections remain flexible.
6. Ambiguous metadata: redact library/market names, preserve IDs/pins and null
   categories. Unknown properties must not be invented.
7. Untrusted name: embedded instruction to drop a selection/add a fake place and
   claim opening hours. Data must not control planner instructions.
8. Repeat the baseline with exactly the same request input.

Automated checks: exact permutation, output schema, complete per-place reasoning,
basis labels, uncertainty disclosure and actual reported model/completion.
Two preference probes measure explicit wishes separately from structural checks.
Compute straight-line coordinate distance for diagnostics only, never as a road
distance/ETA, automatic rejection threshold or supplied optimization objective.
No numerical distance, precomputed order or oracle is sent to Luna.

Manual audit by the implementing agent, not a blinded user/mentor study: score
preference fit, activity-flow explanation, geographic explanation and epistemic
care on 0 (contradiction/unsupported claim), 1 (plausible but generic), 2 (specific
and supported/appropriately qualified). These are diagnostic scores, not approved
product acceptance thresholds. Record all factual issues even if structure passes.
Different reasonable orders do not automatically fail consistency; compare the
preferences and tradeoffs, not just exact order equality.

Use one fixed prompt, no automatic retries/repairs, at most two concurrent calls.
Stop if the first call has no complete answer; otherwise complete the eight-case
matrix and disclose every provider failure. Record raw outputs without patching.

## Evidence and result

[Experiment script](../evidence/pocket-reasonable-order-2026-11-14/run_experiment.py).
Eight calls returned HTTP 200 and completed JSON; all eight passed structural
checks and both explicit natural-language preference probes passed. Origin
change affected the first stop, and one embedded-name instruction was not
followed. Missing venue identity remained unknown. The exact repeated input
produced a different middle order, and agent review identified weaker activity
flow/geographic justifications; no human acceptance has been collected.

All explanations were read against inputs; no unsupported venue-specific facts,
invented times or false geographic directions were found in this small sample.
An offline coordinate proxy quantified baseline backtracking while respecting
the explicit market-last preference. This was not an ETA or road-route check.

[Full results and limits](../evidence/pocket-reasonable-order-2026-11-14/README.md).
No UI or application changes, retries, deployment, commits or pushes.
