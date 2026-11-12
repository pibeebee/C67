# Exploratory English evaluation with pre-supplied trip data

## Decision

This configuration did not pass all tested trip-planner behaviors. All 24 outputs met the structural JSON contract, but every one of the 12 scenarios contained at least one observable violation of the task instructions in both repetitions. This is a provisional single-review assessment, not a measurement of all possible prompts, models, devices or production accuracy. Supplying facts and using supported English did not make this particular setup safe to apply without independent validation and user confirmation.

## Method and boundaries

We used a new 12-case synthetic suite, not a translation or complete rerun of the original 32-case protocol. The shared context supplies a current trip, a precomputed route/deadline result, forecast, golden-hour timing, two candidates and their attributed facts. The accessibility-unknown case replaces candidate evidence with explicitly unknown access, and the stale case supplies an invalid old proposal. These deliberate missing/stale cases test honest uncertainty. All facts are synthetic, not live provider results.

The original runtime instructions and v4 nullable dynamic output schema were reused. Each case has its own session and process; the full shared context is included even when some facts are irrelevant. Model-visible inputs are in `run.py`; no grading key, rubric, case ID or expected answer is sent to the model. The suite and settings were frozen in `freeze.sha256` after a single sanity check and before the 24 main attempts. This is exploratory: the earlier evaluation and its key were already known, and there is no fresh blind holdout. No prompt tuning or postprocessing was performed in this series. Tool registration was empty: supplying data directly does not test model tool selection, tool failure handling, real MapKit, weather providers, or offline execution of tools. Price-unknown, source conflicts, typo, prompt injection, actual app validation, and many original scenarios were not separately tested.

Runtime preflight reported `SystemLanguageModel.default` available and `supportsLocale(en_US) = true`. The evaluator explicitly selected that model, with no cloud fallback. The evaluator process was sandboxed against network sockets; a separately hosted system service was not independently isolated in this series. Earlier offline controls are documented in the parent report and are not a new offline test. Hardware was Mac17,2, Apple M5, 24 GiB, macOS 27.2 (26B123), Xcode 27.2 (27B52), macOS SDK 27.2, Swift 6.4.2. This is not an iPhone result. The model's internal version and Apple Intelligence region were not obtained.

Each case ran twice with greedy sampling, no seed, default temperature, 1,400 maximum response tokens and a 30-second process deadline. All 24 returned schema-valid responses; no timeout or error occurred. All 12 pairs had identical parsed output, so the repetitions are correlated rather than independent evidence. Process wall time: median 4.392 seconds, nearest-rank p90 5.495 seconds, maximum 5.577 seconds; process/session startup is included and service warm state is uncontrolled. Sanity returned in 9.471 seconds and is excluded from main counts.

## Provisional case review

| Case | Finding in both repetitions |
| --- | --- |
| extend | Correct type, target and 30 minutes, but filled a computed leave time that must be null, included unrequested candidates and asserted feasibility for the extension without a recalculated result. |
| negation | Failed to propose skipping D; instead proposed a 40-minute extension at B. |
| correction | Correctly retained 15 minutes at B, but filled the computed leave time instead of null. |
| deadline | Did not supply the requested 10:30 time; said it could not set the deadline yet also emitted a set-deadline action. |
| ambiguity | Emitted skip D instead of asking which item was intended. |
| preferences | Recorded only quiet, proposed an unrelated extension, and claimed P1 closes at 11:00 rather than the supplied 12:00. |
| golden | Correctly stated missing golden hour does not cancel C, but also proposed an unrequested extension at C. |
| weather | Correctly stated 60% is not certain, but also emitted an unrelated extension action. |
| route | Correctly repeated 11:40 before 12:00, but also proposed an unrelated extension. |
| recommend | Selected the grounded P1 with its 8-minute detour and price, but also emitted an unrequested begin-visit action targeting a candidate. |
| unknown | Correctly said accessibility was unverified for both places, but also emitted an unrelated extension action. |
| stale | Correctly warned that P-OLD was invalid, but emitted an apply action and copied old revision 6 instead of current revision 7. |

These are visible field and factual errors, not a full semantic/factual-claim audit. The assessment was conducted by the coding assistant; two independent human reviewers and consensus are still pending. No overall unsupported-claim rate is claimed. A schema-valid response is not a correct response; no evidence here shows the application actually accepted or rejected these actions.

## Implications and next experiments

Keep scheduling, routing, freshness, revision checks, persistence and confirmation in native/application code, with weather and place data obtained from real providers as appropriate. Do not replace the AI backend or enable model-directed actions on this evidence. Narrower task-specific prompts and schemas, smaller context, and separation of explanation from actions may improve results, but none was evaluated here. Design and freeze a fresh English suite before tuning/holdout, separately test tool success and failure, unavailable/missing facts and actual application guards, then repeat on the intended physical iPhone. A model result is a proposal; the app must still validate it.

## Reproduction and artifacts

`run.py` contains the synthetic context and case messages; `sanity.jsonl` and `runs.jsonl` preserve raw responses, times, schema checks and empty tool traces. `freeze.sha256` records source, binary, instructions and contract hashes. The binary under `/tmp` is ephemeral. Compile `../series-v4/Evaluator.swift` as in the parent README and run `python3 run.py sanity` and `python3 run.py main` from a fresh copy of this directory; the runner refuses to overwrite existing records. Reproduction is a new series and requires fresh runtime preflight, hash recording, and review.
