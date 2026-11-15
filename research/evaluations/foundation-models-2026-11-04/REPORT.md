# Foundation Models evaluation for C67

**Decision:** defer replacing C67's AI backend or adding an unsupervised natural-language action interface. The Apple system model ran on this Mac, but `supportsLocale(id_ID)` returned false. With a contract-correct schema, the one supported English control did not produce a fully correct action in any of ten attempts; the exploratory Indonesian runs also showed unsafe proposed actions and did not exercise the three requested tools. This is evidence about the tested setup, not a general claim about every Apple model or future release.

## Scope and integrity

The supplied nine checksums matched. The model process received `model-instructions.txt` with locale/language placeholders replaced and, for each session, only one case's context, explicit history and user message. It never opened the evaluator key or rubric. Only case-authorized local read tools were registered. Tool fixtures were not inserted into prompts; the wrapper would return a fixture only after an actual valid tool call. No tools could apply, save or mutate plans.

`SystemLanguageModel.default` was explicitly passed to `LanguageModelSession`; no cloud model or silent fallback was used. Apple's documentation distinguishes this system model from the separate `PrivateCloudComputeLanguageModel` type. The evaluator process ran under a macOS sandbox denying network sockets; a sandboxed TCP connection returned `EPERM`. A separately hosted system daemon was not independently isolated by that sandbox. For an additional offline control, Wi-Fi and the active USB Ethernet service were temporarily disabled: the system reported no active network interface before and after both samples. Both services were restored, and `scutil --nwi` subsequently reported both interfaces active. This is not a packet-capture audit.

The recorded machine was a Mac17,2 with Apple M5, 24 GiB RAM, macOS 27.0.1 build 26A434, Xcode 27.2 build 27B52, Swift 6.4.2 and macOS SDK 27.2. Model availability was `available`; `id_ID` was unsupported and `en_US` supported. The Mac locale was `en_ID`; Apple Intelligence service region was not independently verified. The model's internal version was not exposed by the observed API. [Manifest](series-v4/manifest.json) and [freeze](series-v4/freeze.json) provide the full settings and SHA-256 hashes. The 26.4+ nullable-schema SDK API used by this harness is a separate deployment consideration from C67's existing iOS 18 minimum.

Each run used a fresh process and session, greedy sampling, default temperature, no seed, at most 1,400 response tokens, up to two local tool calls and a 20-second total process timeout. There were no automatic retries. A timed-out process was terminated; this does not prove how quickly a separately hosted model service stopped its work. Successful-process latency includes session/process setup and uses unknown mixtures of cold and warm service state. Identical greedy outputs are correlated observations.

## Schema correction and freeze

The initial v1/v2 `@Generable` schema incorrectly mapped contract fields requiring explicit JSON nulls to optional fields that could be omitted and whose generated schema did not permit null. This was discovered by inspecting the SDK-generated schema after the initial series. Those results are preserved in [the initial assessment](assessed-runs.jsonl), but exact nullable-field failures in that series cannot fairly be attributed to model understanding.

The v3 attempt using the SDK's explicit-nil macro option produced the same generation schema; it is preserved as an unsuccessful adapter experiment. V4 uses `DynamicGenerationSchema` with required, explicit nullable unions. Its [actual generated schema](series-v4/generated-schema-v4.json) was checked against the package contract's types, required fields, enum values, array bound and extra-property rules. Raw JSON is validated before any repair; no fields are filled in by the grader.

The original runtime instructions were unchanged. All 24 development cases were attempted before the v4 source, instructions, schema, fixtures, settings and binary were frozen; the eight evaluation cases were run afterward. **This is a follow-up exploratory series, not a fresh holdout:** the initial series and its evaluator key had already been inspected. The model executable still never reads that key. Source bytes used at freeze are retained in `frozen-Evaluator.swift.txt`; the freeze record documents their relocation before formatting the working copy. A schema-export command was subsequently added to the working copy for future series; it was not present in the evaluated executable.

## Primary and diagnostic results

| Population | Attempts | Raw schema-valid responses | Timeout | Result |
| --- | ---: | ---: | ---: | --- |
| Supported `en_US` control, M1 | 10 | 9 | 1 | 9/9 responses had the requested action type, B target and 30 minutes; **0/10 attempts** matched all required action fields. |
| Unsupported `id_ID`, exploratory M1/M2 | 31 | 29 | 2 | 22 objective failures, 7 responses with objective checks clear but awaiting human review, 2 timeouts. Not product-eligible results. |

The single English case accounts for ten eligible attempts. The 31 Indonesian cases account for **310 blocked planned repetitions**; one separate diagnostic attempt was made for each. In the English responses the model filled `localTime` with `2026-11-05T09:50:00+07:00` when the contract requires null for an extension. The supplied planned leave was 09:20, so 09:50 is arithmetically plausible; the failure is that the model supplied and asserted a computed leave time reserved for the application. All nine canonical responses were identical. The tenth attempt reached the 20-second limit.

M1 English response-only process latency was p50 **10.174 s**, p90 **13.942 s** and maximum **13.942 s** across nine responses; the timeout reached **20.061 s**. Indonesian diagnostic M1 response-only latency was p50 **4.818 s**, p90 **11.349 s**, max **13.906 s** across 27 responses; M2 response-only latency was p50 **17.151 s**, p90/max **18.750 s** across two responses, with one additional timeout. These are Mac measurements and cannot establish the proposed iPhone p90 target.

The [32-case table](series-v4/case-status.md), [machine summary](series-v4/summary.json), [raw runs with objective assessments](series-v4/assessed-runs.jsonl) and [additional offline runs](series-v4/offline-assessed-runs.jsonl) retain case/run IDs, raw output, errors, timings, tool traces and review status. Main Indonesian rows are **Blocked**, even if a diagnostic response appears promising. An objective failure is a field-level finding, not a complete human semantic review. Potential critical flags are review candidates, not final severity decisions. Two human reviewers were unavailable; factual accuracy, unsupported factual-claim rate, complete recommendation quality, disagreements and consensus therefore remain unmeasured.

The narrow automated check for evidence IDs absent from the supplied context or returned tool results flagged **0/9** English responses and **1/29** Indonesian diagnostic responses (`PREF-01`). This checks identifiers only: it neither verifies that a cited source supports a statement nor detects all unsupported claims in prose. The `REC-06` example below is a factual overstatement that the objective field checks did not catch.

## Concrete observations

- **Intent and negation:** `INT-03` emitted the expected `skip_stop D` action, but its message incorrectly said skipping D was unsupported and asked whether to skip C. `INT-04` omitted the requested deadline and put 11:00 into B's leave time. `INT-05` proposed skipping D for an ambiguous request. `INT-06` turned “setengah sebelas” into a different `set_leave_time` action. These are unsupported-locale diagnostics, not an accuracy estimate.
- **Correction:** `INT-08` emitted exactly the 15-minute extension at B, with null unused fields and a message saying it was not saved. This is one diagnostic success on objective fields; two human reviews are still required.
- **Golden hour:** `EXPL-02` said golden hour did not directly require cancellation, but omitted one required evidence ID and did not provide the complete supplied time/closing explanation. It does not establish a reliable explanation feature.
- **Preferences and recommendations:** `PREF-01` captured only the quiet preference, invented an evidence reference and proposed unrelated changes. `REC-01` selected P1 with PL1, but did not explain the 8-minute detour or unknown noise/cost. `REC-02` correctly said no wheelchair-accessible candidate was verified. `REC-06` said no place met the price limit, although missing prices establish uncertainty rather than impossibility. The latter illustrates why objective field checks cannot replace semantic review.
- **Stale proposal:** `OPS-02` correctly warned in its message that P-OLD was stale, yet returned `basedOnRevision: 6` against current revision 7 and included `apply_proposal` for P-OLD. The application must independently reject it.
- **Read-only tools:** v4's three Indonesian tool cases produced **0 actual calls across 3 attempts**, including one timeout. No forecast/search/hours fixture was returned to the model. Therefore tool selection, argument accuracy and recovery from the fixture's unavailable response were not established.

## Runtime controls

[Controls](series-v4/controls.json) record a measured 8,192-token model context size. For the English sample, the instructions counted 691 tokens, case prompt 296, dynamic schema 717 and one weather tool 121; these separate counts exclude framework/transcript overhead and generated output. An artificially long 60,298-token prompt returned `LanguageModelError: May contain unsafe content`; it did not establish a precise overflow boundary. A canceled running task produced `CancellationError`, the session reported not responding, and a fresh session returned a response. This is a harness/runtime observation, not validation of the app's cancellation UI or restart logic.

A separate synthetic wrapper check rejected a response based on revision 7 when current revision was 8. It is an evaluator demonstration, not a test of the C67 application's actual validator, persistence or confirmation flow. With both active network services disabled, the English M1 sample returned the same contract-shaped response in 6.222 s, with the same unwanted computed time; the Indonesian M2 sample returned in 3.327 s and made no tool call. The full [offline control record](series-v4/offline-both-control.json) includes interface state and restoration. It supports local model inference without an active network on this Mac; because M2 made no tool call, it does not establish successful fixture-tool execution offline or live routing/weather/search offline. Device-unavailable behavior was not exercised. The unsupported-locale preflight was observed, but no product fallback UI was tested.

## Integration decisions

| Capability | Decision | Evidence and boundary |
| --- | --- | --- |
| Indonesian intent and preference extraction | Defer product integration | Runtime reports unsupported; diagnostics include wrong targets/actions and missing preferences. |
| Structured action proposals | Defer execution use; research only behind validation and explicit review | Even the supported English control failed complete action-field matching. Never apply directly. |
| Explanations of solver outputs | Research with deterministic templates as fallback | One golden-hour diagnostic preserved the broad distinction but missed required evidence and details. No human semantic study. |
| Recommendations from supplied candidates | Research only | One P1 selection was grounded but incomplete; accessibility unknown was handled in one case, while price uncertainty was overstated in another. |
| Model-directed local tools | Defer | No actual call in three diagnostic cases, including a timeout. Test a revised harness and supported locale before assigning a cause. |
| Local replacement for backend AI | No replacement established | A future, narrowly scoped parser or explanation layer could be local for supported locales after new independent evaluation. The current C67 planning backend and live-provider acceptance remain separate. |
| Native/provider responsibilities | Retain deterministic code and verified data sources | Scheduling, route calculation, weather, place search, evidence freshness, revision checks, actual history, persistence and confirmation remain app/backend responsibilities. Local model inference supplies none of these facts by itself. |

Current C67 UI already exposes direct place/time controls, a “Stay 30 minutes longer” action and reviewed proposal application. A deterministic explanation template is a proposed comparison, not a demonstrated feature for every scenario. No user study compared interactions, clarity or preference satisfaction with the model.

Next: obtain two independent human reviews; create a genuinely fresh, unseen paraphrase set; evaluate a target iPhone with the intended OS and supported language, including offline tool execution; exercise unavailable-model fallback, tool failures and actual app revision/confirmation behavior. Reassess the runtime's Indonesian support after OS/model updates rather than assuming this Mac's result applies forever.

## Verification and source references

The v4 harness compiled and the formatted working copy typechecked. The supplied contract checker was exercised against required fields, enum values, extra fields, the array limit and integer/boolean distinctions. The frozen input hashes still match. The repository-wide SwiftFormat check reported one pre-existing error at `tripsense-poc/App/TripSenseApp.swift:31`; evaluation Swift files passed after formatting. No C67 application or solver source was changed.

Apple references: [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [on-device versus Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), [locale support](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/supportedlanguages), and [tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling). Documentation was retrieved via Context7 and checked against the installed SDK.
