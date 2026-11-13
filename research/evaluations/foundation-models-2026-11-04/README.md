# C67 Foundation Models evaluation

This isolated harness and report do not modify C67's app, solver or backend. Start with [the report](REPORT.md), [case dispositions](series-v4/case-status.md) and [v4 raw runs and objective assessments](series-v4/assessed-runs.jsonl). The package was supplied separately under the user's Downloads directory. No evaluator-only key is copied into this directory.

## How the evaluation works

The Swift executable explicitly selects `SystemLanguageModel.default`. The Python runner sends only one case's `context`, explicit `history` and `userMessage`; it does not open the evaluator key or send case ID, split or expected answers to the model. Registered tools read frozen local fixtures only after an actual valid call, with a shared two-call budget. They cannot change a plan. Each run uses a new process and model session, greedy sampling and a 20-second process deadline. The evaluator process has network sockets denied; separately hosted system services are not thereby proven offline.

V1/v2 used `@Generable` optionals, whose generated schema did not match the package's required nulls. V3's explicit-nil macro option did not change that generated schema. Those runs are retained as development evidence, not combined with the corrected series. V4 uses a dynamic schema with required nullable unions. Its [actual SDK-generated schema](series-v4/generated-schema-v4.json) was checked against the supplied contract. It was frozen after all development cases were attempted. Because v4 was constructed after v2's evaluation output and key were reviewed, v4 is a follow-up and has no fresh blind holdout.

Raw records are never repaired. `grade_results.py` is a **separate, post-run** process that reads the evaluator key and performs objective field checks only. It does not call a model. `assessed-runs.jsonl` combines the untouched raw records with provisional objective findings; two human reviewers are still required for semantic accuracy, factual claims and recommendation quality. The validator implements the JSON Schema keywords present in the supplied contract: `type`, `required`, `properties`, `additionalProperties`, `enum`, `items` and `maxItems`.

Original source bytes used for frozen series and control runs are retained as `frozen-*.swift.txt`. The regular Swift files are layout-formatted working copies; the v4 evaluator also gained a `--dump-schema` command after the recorded runs to support reproduction. Each freeze manifest records the byte-for-byte archive path, all relevant input hashes, and the original compiled binary hash. The `/tmp` binaries are local and temporary; a newly compiled binary starts a new evaluation series rather than replacing historical evidence.

## Start a new series

Use a compatible Apple Silicon Mac, Xcode, a ready system model and the original evaluation package. The following example creates a separate directory and binary, leaving the recorded run intact. Replace `PACKAGE_DIR` with the supplied folder. `reproduce_evaluation.py` is the future-run copy of the runner: unlike the originally frozen runner, its primary phase selects every locale that the new manifest reports as supported.

```sh
rtk mkdir -p /tmp/c67-eval-new
rtk cp evaluations/foundation-models-2026-11-04/series-v4/Evaluator.swift /tmp/c67-eval-new/Evaluator.swift
rtk cp evaluations/foundation-models-2026-11-04/series-v4/reproduce_evaluation.py /tmp/c67-eval-new/run_evaluation.py
rtk cp evaluations/foundation-models-2026-11-04/series-v4/freeze_evaluation.py /tmp/c67-eval-new/freeze_evaluation.py
rtk cp evaluations/foundation-models-2026-11-04/series-v4/grade_results.py /tmp/c67-eval-new/grade_results.py
rtk proxy xcrun swiftc -parse-as-library -swift-version 6 -O /tmp/c67-eval-new/Evaluator.swift -o /tmp/c67-eval-new/evaluator
rtk proxy /tmp/c67-eval-new/evaluator --dump-schema > /tmp/c67-eval-new/generated-schema-v4.json
rtk proxy python3 /tmp/c67-eval-new/run_evaluation.py --phase sanity --package PACKAGE_DIR --binary /tmp/c67-eval-new/evaluator
rtk proxy python3 /tmp/c67-eval-new/run_evaluation.py --phase development-diagnostic --package PACKAGE_DIR --binary /tmp/c67-eval-new/evaluator
rtk proxy python3 /tmp/c67-eval-new/freeze_evaluation.py --package PACKAGE_DIR --binary /tmp/c67-eval-new/evaluator
rtk proxy python3 /tmp/c67-eval-new/run_evaluation.py --phase primary --repeat 10 --package PACKAGE_DIR --binary /tmp/c67-eval-new/evaluator
rtk proxy python3 /tmp/c67-eval-new/grade_results.py --package PACKAGE_DIR
```

The development diagnostic is explicitly outside supported-product results when `id_ID` is unsupported. After freezing, `--phase evaluation-diagnostic` runs the eight Indonesian evaluation cases separately; use it only as a diagnostic when the locale is unsupported, and rerun the separate grader afterward. The runner verifies frozen source, prompt, schema, fixture, input and binary hashes before primary/evaluation calls. Package location and binary paths are recorded in the new freeze manifest. Preflight, tool/sandbox behavior and all results must be reassessed on the new machine; do not reuse this Mac's support or latency claims. The included `summarize_results.py` is specific to this run's blocked Indonesian cohort and refuses a different support profile.

The `RuntimeControls.swift` and `run_controls.py` files record cancellation, long-input, token and synthetic stale-revision controls. `offline_control.py` safely refused the initial Wi-Fi-only attempt when Ethernet was active. `offline_both_control.py` subsequently disabled the two observed services, verified no active interfaces while two samples ran, and restored both services; it has a separate restoration watchdog. See the recorded interface state and raw results before applying this machine-specific script elsewhere.
