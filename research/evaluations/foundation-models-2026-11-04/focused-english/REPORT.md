# Focused English Foundation Models experiment

## Result

Task-specific output and smaller context improved some observed cases in this exploratory setup, but did not make the workflow reliable enough for automatic trip changes. A single-review provisional assessment found 5 of 12 previously tested scenarios correct in both repetitions, compared with 0 of 12 in the earlier broad-context setup. Four additional English paraphrase cases produced one correct case. Two of three separate tool scenarios met the full stated criteria. All 19 pairs of greedy responses were identical. These are small, correlated observations; the changed schema, prompt, context, output length and time of test prevent attributing the change to any one adjustment.

There is no blinded evaluation: the previous cases and results were already known during design; new paraphrases were authored by the same evaluator. Independent human review is pending. Selection of each task type and relevant context was supplied by the harness; an actual user-facing router was not tested. The four new cases are an exploratory challenge, not an independent holdout. Outputs, run settings and tool traces are in `runs.jsonl`; `assessment.jsonl` is a separate provisional review and `assess.py` must not be used to grade future outputs without re-review.

## Setup

`SystemLanguageModel.default` was explicitly selected; preflight reported available and `en_US` supported. Mac17,2, Apple M5 with 24 GiB, macOS 27.2 build 26B123, Xcode 27.2 build 27B52, macOS SDK 27.2 and Swift 6.4.2. The model internal version and Apple Intelligence region were not obtained. Each run used a fresh process/session, greedy sampling, default temperature, no seed, 450 maximum response tokens, and 30-second timeout. All 38 attempts produced a typed, decodable response; this does not establish semantic correctness. Successful process wall-time median 1.122 s, nearest-rank p90 2.278 s and maximum 2.835 s. The earlier configuration had 1,400 output tokens and different schema/prompt/context and was run at another time; service cold/warm state is uncontrolled, so the latency difference is not a causal benchmark. Network access was denied to the evaluator process; a separate system service was not independently isolated. No physical iPhone or current system-wide offline test occurred.

Model instructions, code, prepared inputs, fixture and binary were hashed after a sanity check and before the main series (`freeze.sha256`). The model executable never reads assessment notes or expectations. Synthetic fixtures are not live MapKit, weather or real traveller data. Intentional unknown and stale fixtures preserve realistic failure cases.

## Model results

| Previously tested scenario | Result in both runs |
| --- | --- |
| Extend 30 minutes | Correct intent, B and 30 minutes, without a calculated leave time. |
| Negation: keep C, skip D | Wrong: emitted extension at C with zero minutes. |
| Correction to 15 minutes | Correct duration and B, but invented a proposal ID and added an unnecessary question. |
| Set deadline 10:30 | Included 10:30 but selected extension, with invented 15 minutes. |
| Ambiguous cancellation | Selected skip D instead of asking. |
| Coffee, reading, quiet preferences | Captured all three. |
| Golden hour | Correct explanation that C need not be cancelled, citing E-GOLD. |
| Weather | Correct 60% uncertainty explanation with E-WEATHER. |
| Route deadline | Correct arrival and deadline with E-ROUTE. |
| Place recommendation | Chose P1 and provided relevant tradeoffs, but cited E-P1 while also asserting facts about P2 without E-P2. |
| Unknown accessibility | Correct prose, but returned literal string `"null"` as candidate ID rather than null/omission. |
| Stale proposal | Proposed applying P-OLD despite invalid/stale context. |

The four new paraphrases: 20-minute extension was correct; negation selected C but added conflicting fields and a question; ambiguous cancellation emitted skip B with an unresolved question; 11:15 deadline was misclassified as an extension. Counts above assess the complete output, not merely a correct fragment. The schema omitted actions entirely for explanation and recommendation requests, so the earlier unwanted action field was structurally impossible in those modes; task routing itself was externally supplied.

## Tool use, separately

Only one relevant fixture tool was registered per run, and the user message explicitly instructed its use; this does not prove autonomous tool selection. On all six attempts, the model called the registered tool once with the required arguments, and received only the corresponding local fixture. The weather answer correctly said rain was not certain but claimed 69.99% instead of the fixture's 0.7 (70%); the search case reported the returned place, citation and unknowns; the opening-hours case reported unavailable and stopped after the single call. Thus 2 of 3 tool cases met the full provisional criteria in both repetitions. These are synthetic read-only fixtures, not provider latency, real availability, or a thrown-exception recovery test. The unavailable case returned a structured failure, not a thrown network exception.

## Application-side checks and templates

`guards.py` contains an **experimental harness validator**, not the C67 product validator. It was written and adjusted after the model runs, with the observed errors visible; its rejection rate is exploratory and not a blind estimate. It verifies revision, target/status, duration, endpoint, deadline and proposal validity, and returns only a proposal requiring confirmation and revalidation. On the 20 intent outputs it rejected 14 and allowed six as proposals. Two of those six were the wrong skip-D interpretation of an ambiguous request: a structurally valid action cannot prove the model understood the user. The stale model output was rejected because it also contained an unresolved question; a separate unit test directly verified rejection of stale P-OLD. Four focused unit tests passed, including completed-stop rejection and confirmation requirement. The duration range is an experimental safety bound, not a C67 product policy.

`templates.json` records three deterministic renderings of structured synthetic weather, route and golden-hour facts with source IDs. They are generated without the model and demonstrate a way to keep known values and uncertainty in explanatory text. They are not a complete production template system, do not verify the source data, and were not compared through a user study. Neither the validator nor templates apply or save any change.

## Next steps

Retain deterministic validation and confirmation; do not deploy the experimental harness as product logic. Investigate negation, deadline classification, ambiguous references, and literal `"null"` IDs with narrowly scoped development tests. Test multi-tool selection, thrown exceptions, live provider freshness, the actual C67 validator and routing, and independent fresh cases. Repeat on the intended physical iPhone and measure real-device availability, quality and latency. Two independent human reviewers should evaluate factual support and semantics before any integration decision.

## Reproduction

Sources and `run.py` preserve the model-visible input construction; `Support.swift` reuses the earlier fixture ledger. Compile the two Swift files to `/tmp/c67-focused-evaluator`; run `run.py sanity`, freeze hashes, then `run.py main` in a fresh directory. The runner refuses to overwrite existing results. Grade fresh outputs independently rather than reusing the hard-coded notes in `assess.py`. Run `python3 -m unittest -v test_guards` in this directory. The source package path and `/tmp` binary are machine-specific and must be adjusted for another host.
