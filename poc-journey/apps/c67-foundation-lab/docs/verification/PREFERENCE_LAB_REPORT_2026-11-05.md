# Experiment 02 — local preference profile and embeddings

Date: **5 November 2026**, Asia/Jakarta. App **v0.3, build 5**. This is a separate screen in the same Foundation Lab app. Experiment 01 and its previous itinerary-import lab remain available under **01 · Foundation**.

**Outcome:** the new screen, local profile storage, category comparison and actual E5 embedding inference work on the tested Mac, Simulator and physical iPhone. The prototype can change its ranking from a short direction or one liked place. It does **not** establish consistently better recommendations than the category baseline, reliable interpretation of negation, or reduced user effort.

## Implemented scope

- **02 · Preferensi**, selected on normal launch, has optional interests, a short Indonesian/English direction, explicit avoids and up to six liked places. A user can begin with one signal; empty input is labeled general, not personalized.
- The profile combines explicit interests and the known attributes of liked places. Repeating a like does not inflate its weight. A dislike excludes that particular place and is not interpreted as rejecting its whole category. This updates an application profile; it does not fine-tune the model weights.
- Two catalogs are available: **14 fictional venues** with illustrative attributes and Jakarta coordinates, and **10 real MapKit identities/categories** frozen from the 5 November iPhone run. Their provenance is visible and retained in exports. The second catalog performs no new live search and invents no quietness, reading seats or opening hours.
- Native filters remove liked/disliked places and candidates with known avoided tags before either ranking method. Positive interests are soft scoring signals, not an AND guarantee. Unknown attributes do not become verified matches or exclusions.
- The category baseline uses explicit interests and tag weights from likes. The embedding method matches the profile query to supplied place descriptions. Both score the same eligible candidate pool; the UI shows the first three rows of each ranking. Zero category scores are displayed as zero and are not evidence of a personal match; a zero-score baseline is labeled general.
- A fresh comparison invalidates the old result. Input changes cancel pending work and ignore stale completion. Profile/history storage, reset and JSON/Markdown export are separate from experiment 01. Profiles are separated by catalog. A malformed history file is preserved while valid runs remain recoverable; profile recovery falls back to an empty profile with a visible message.
- Likes here are explicit interactions on this screen. Existing visits, imports and choices in the old lab do not silently train the new profile. No new route, ETA, visiting time, weather result or hosted AI service was added.

## Model and reproducibility

| Component | Frozen configuration |
|---|---|
| Embedding model | `intfloat/multilingual-e5-small` |
| Revision | `614241f622f53c4eeff9890bdc4f31cfecc418b3` |
| Artifact | Upstream `onnx/model_qint8_avx512_vnni.onnx`, bundled as `model.onnx` |
| Artifact SHA-256 | `dd476dd0c2514e9b9be83aeb3853fac0763e0bdf4a71645407587d77c48a2d88` |
| Runtime | ONNX Runtime 1.24.2, CPU, two intra-op threads |
| Tokenizer | Hugging Face Swift Tokenizers from `swift-transformers` 1.4.0, local tokenizer files |
| Encoding | `query:` / `passage:` prefixes, supplied attention mask, zero token-type IDs, mean pooling, L2 normalization, 384 dimensions, cosine similarity |
| Input limit | Maximum 512 tokens per encoding; oversized input is rejected rather than silently truncated |
| Assets | About 135.4 MB for weights/tokenizer/configs; MIT model license and source notice bundled |

The artifact's upstream filename is not a claim that Apple devices have AVX instructions. Actual CPU inference of that artifact was observed on Apple Silicon and the iPhone. Resource hashes are verified during preparation and again before inference. The model and catalogs are bundled; this inference path does not send preferences to an AI API. An airplane-mode or packet-capture audit was not performed.

Upstream references: [E5 model and usage](https://huggingface.co/intfloat/multilingual-e5-small), [ONNX Runtime Mobile](https://onnxruntime.ai/docs/tutorials/mobile/), [official ORT Swift package](https://github.com/microsoft/onnxruntime-swift-package-manager), [Hugging Face Swift Tokenizers](https://github.com/huggingface/swift-transformers). Framework compatibility is supported by the local builds and runtime evidence below, not inferred solely from documentation.

## Verification

| Check | Result and boundary |
|---|---|
| New unit tests | **15/15 passed**: cold start, explicit avoids, repeated likes, disliked-place semantics, common candidate filtering, invalid vectors, unavailable model, cancellation, input limits, unknown IDs, contradictions, snapshot unknowns and storage recovery. [Log](preference-lab-2026-11-05/preference-tests.log) |
| Previous Foundation Lab tests | **57/57 passed**; existing package source remained byte-for-byte unchanged. [Log](preference-lab-2026-11-05/legacy-tests.log) |
| Formatting | `swift-format lint --strict` passed for app and both packages |
| iOS builds | Simulator build/run and signed iPhone build succeeded. [Simulator metadata](preference-lab-2026-11-05/simulator/final-build.json), [device build](preference-lab-2026-11-05/device-build.log) |
| Simulator walkthrough | Cold input/general result; one liked place and derived profile; actual semantic comparison; persisted profile after relaunch; experiment history/export; switching to the MapKit snapshot; old Foundation tab available. [UI evidence](preference-lab-2026-11-05/simulator/observations.json) |
| Mac inference | Twelve authored cases: ten completed semantic comparisons, one cold/general run, one category-only baseline. Final semantic-run durations **0.65–1.76 s** on macOS 27.0.1, including initialization and native work. [Frozen final series](preference-lab-2026-11-05/final-evaluation/summary.json) |
| Physical iPhone | Build 5 installed; two scripted E5 runs against the 14-place fictional catalog completed in **0.874 s** and **0.733 s**, both with top IDs H/A/G. Runtime iOS 27.0.1 (24A446). [First run](preference-lab-2026-11-05/iphone/run.json), [final run](preference-lab-2026-11-05/iphone/final-run.json), [device console](preference-lab-2026-11-05/iphone/final-console.log) |
| Tokenizer reference | Exact token IDs matched seven Python tokenizer probes, including Indonesian, whitespace, accents, Japanese and emoji. [Reference checks](preference-lab-2026-11-05/reference/reference-check.json) |
| Numerical reference | Two embedding probes were close but not bit-identical to Python ORT 1.24.2: minimum cosine about **0.99925**, maximum component difference about **0.00658**. This is not an exact cross-build parity pass; the remaining numerical difference has not been isolated. |
| Previous journey preservation | Only the app entry file changed among pre-existing Swift files, to add the tab container. Old views, models, prompts, package code and tests were preserved. [Hash audit](preference-lab-2026-11-05/preservation.json) |

The phone runs use actual E5 inference in the iPhone app, not Foundation Models or a Simulator stand-in. They are scripted pipeline checks, not a full physical-device UI walkthrough. The final signed build includes the UI recovery improvement. These latency figures **cannot be compared directly with the previous 23-second Foundation run**: that run included live MapKit search and several generative tasks with different data.

## What the ranking trials showed

The [case manifest](preference-lab-2026-11-05/final-evaluation/manifest.json) records source/binary/model hashes. Twelve development cases were authored and inspected, one run each; the earlier series is also retained. This is not a blind holdout or an independently reviewed preference benchmark. Fixture tag coverage is a narrow diagnostic and is not user satisfaction or real venue quality.

- **Short directions:** Indonesian and English coffee/reading directions put relevant reading/cafe descriptions high. The Indonesian case ranked library H above coffee cafes A/G, so semantic similarity did not satisfy all three coffee/reading/quiet requirements at the top position.
- **Likes change the profile:** liking fictional reading cafe A excluded A and ranked G/H/B semantically. Replacing that signal with liked art gallery C excluded C and ranked L/I/H. The top results changed without asking the user to fill every preference field, but a quiet indoor attribute can also pull unrelated activities upward.
- **No consistent win over categories:** in the two liked-place cases, the number of top-three rows carrying all diagnostic target tags was the same for both methods. Text-only category scores were zero because that baseline does not parse free text; ranking above that baseline is not evidence of superiority over a fully configured recommender.
- **Negation failure:** “Saya ingin ngopi tetapi tidak ingin tempat ramai” ranked the lively market E and lively garden cafe B near the top. The embedding model did not turn the negation into a dependable exclusion. The screen warns about recognized negation and offers explicit avoids; arbitrary negations are not fully parsed.
- **Native constraints held:** all twelve recorded runs respected supplied explicit avoided tags and excluded liked/disliked IDs. This guarantee comes from application logic and the available tags, not reasoning by E5. It does not prove an unknown real venue lacks an avoided attribute.
- **Thin real data stays thin:** the MapKit snapshot can be ranked by names/categories, but the embedding supplies no new evidence of quietness, seating, price or opening hours. A higher cosine score cannot fill those missing facts.

## Remaining limits

1. Similarity is a relative score, not a calibrated probability. Top-three display does not guarantee three suitable places. Combined preferences, Indonesian slang, negation and activity-versus-ambiance distinctions still produce weak matches.
2. Fictional descriptions contain richer attributes than the real snapshot. Their results must not be generalized as real Jakarta recommendation quality.
3. Two phone runs and twelve development cases do not establish broad reliability, memory/battery behavior across older devices, long sessions or user benefit. Peak device RAM and energy were not profiled.
4. No user observation measured input, corrections, questions or decision effort. Profile-building from one like demonstrates an interaction, not that the final recommendation is helpful.
5. The new screen is not integrated into the old routing planner or its place-search workflow. Foundation Model or cloud-LLM preference extraction is not part of experiment 02. Free text is encoded for similarity, not converted into a guaranteed logical preference schema.
6. Numerical cross-build parity is approximate on the two probes. No exact embedding portability or hardware-wide ranking identity is claimed.

The next useful evaluation is independent review of recommendations and observation of users changing their choices. Hard requirements and text negation need explicit handling before interpreting semantic matching as a complete preference assistant. The routing method remains outside this experiment.

## Reproduce

```sh
python3 scripts/prepare-preference-model.py
bash scripts/run-preference.sh --learned --out /tmp/c67-liked
bash scripts/run-preference.sh --snapshot --out /tmp/c67-snapshot
bash scripts/run-preference.sh --cold --out /tmp/c67-cold
bash scripts/run-preference.sh --baseline --out /tmp/c67-category
python3 scripts/evaluate-preferences.py /absolute/path/to/preference-eval /tmp/c67-new-series
# In a temporary Python environment with tokenizers, numpy and onnxruntime==1.24.2:
python scripts/verify-preference-reference.py /absolute/path/to/preference-eval /tmp/c67-reference
```

Open the app's **02 · Preferensi** tab. The comparison icon is always available in the top toolbar. The original flow remains in **01 · Foundation**, including the earlier lab under Experiments. `--preference-ui` uses isolated storage with real E5 inference; `--preference-smoke` runs the fixed phone check and logs complete JSON. Weights are excluded from Git and can be reproduced with the preparation script; no publishing, commit or push was performed for this handoff.
