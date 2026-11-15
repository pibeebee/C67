# Evidence catalogue and LLM/AnyJev results

Verified on 10 November 2026, Asia/Jakarta. C67 Preference Lab v0.3 build 3, iPhone 18 Pro Max Simulator, iOS 27.2, Xcode 27.2. The backend and AnyJev run on the Mac. Deployment to the homelab and physical-device verification are outside this campaign.

The real-source ingestion, configured LLM extraction, actual AnyJev inference, catalogue activation, local HTTP matching and Simulator interaction completed. The comparison does not establish improved real-user preference fit. Source checks accounted for the successful controlled labels. Adding AnyJev did not improve those labels over source-guarded LLM extraction.

## Methods and evidence

The configured LLM endpoint is `https://luna-provider.example/v1`, requested model `cx/gpt-6-luna(max)`. Responses report `gpt-6-luna(max)`. This is the identity reported by the endpoint. OpenRouter is retained only in the historical failed-campaign artifact.

AnyJev is the actual `anyjev==0.3.0` package with its Hugging Face backend and `Qwen/Qwen3-0.6B`, revision `c1899de289a04d12100db370d81485cdf75e47ca`. It uses MPS, float32, L0, three option rotations, canonical option order and content-free prior correction. The acceptance score was fixed at 0.6 before this comparison. Its scores have not been calibrated against venue truth.

After the user questioned this model choice, a direct capability check requested `logprobs=true` and `top_logprobs=5` from the configured `cx/gpt-6-luna(max)` chat endpoint. It returned the requested letter but omitted the logprobs field. The `/v1/completions` route used by AnyJev's existing remote vLLM backend returned HTTP 404 with an HTML response. These checks are retained in [anyjev-provider-capability.json](artifacts/catalog-2026-11-10/anyjev-provider-capability.json). They establish that the tested routes did not expose the required scores, rather than proving that every model or route on this provider is incompatible. A remote adapter would require genuine candidate-token scoring and a compatible prompt/token mapping. The local Qwen selection was an implementation decision made before this capability check. The benchmark therefore evaluates the external LLM extractor plus local Qwen/AnyJev judge, not AnyJev using the supplied external model itself.

Twenty real OpenStreetMap entities were selected from the temporary Menteng–Cikini bounding box in category rounds. The sample contains seven cafes, seven libraries and six bookshops. It is an ODbL map extract, with its source, attribution and retrieval timestamp retained in [the source snapshot](catalog/osm-source.json). These identities are not twenty verified operating businesses.

The controlled comparison uses twelve authored cases with six claims each. The first six cases are development cases and the last six are a small held-out subset. Expected statuses never enter model requests. Cases cover category-only evidence, explicit shared-area permission, book purchasing, different rooms, prohibition, conflicting sources, conditional duration, accessibility, source injection, takeaway-only consumption and Indonesian evidence.

The expected policy statuses include 59 unknowns and 13 decisive labels. These probes exercise our declared structured-evidence policy. Literal predicates already encode most of the relevant meaning, so the rule baseline is a strong control and the results do not demonstrate extraction quality over arbitrary prose or reviews. The held-out cases remain authored within the same vocabulary and are not an independent user study.

Raw observations and evaluator expectations are in [controlled.json](artifacts/catalog-2026-11-10/controlled.json). [The replay](artifacts/catalog-2026-11-10/replay.json) recomputes the metrics and verifies fixture/policy identity without repeating inference or historical timings.

## Controlled label comparison

An unsupported positive is a `supported` answer when the expected answer is `unknown` or `contradicted`. Decisive recall measures how many of the 13 expected positive/negative labels are recovered correctly. It prevents an always-unknown method from appearing useful solely because this corpus contains many unknowns.

| Method | Correct labels | Exact status agreement | Unsupported positives | Correct decisive labels |
|---|---:|---:|---:|---:|
| Literal structured-source rules | 72/72 | 100.0% | 0 | 13/13 |
| LLM extraction | 67/72 | 93.1% | 2 | 13/13 |
| AnyJev raw readout | 57/72 | 79.2% | 2 | 0/13 |
| AnyJev L0, content-free prior | 10/72 | 13.9% | 60 | 10/13 |
| Source rules + LLM | 72/72 | 100.0% | 0 | 13/13 |
| Source rules + LLM + AnyJev | 72/72 | 100.0% | 0 | 13/13 |

| Method | Development | Held-out authored subset |
|---|---:|---:|
| Literal structured-source rules | 36/36 | 36/36 |
| LLM extraction | 33/36 | 34/36 |
| AnyJev raw readout | 28/36 | 29/36 |
| AnyJev L0, content-free prior | 7/36 | 3/36 |
| Source rules + LLM | 36/36 | 36/36 |
| Source rules + LLM + AnyJev | 36/36 | 36/36 |

The five LLM mistakes were on-site coffee inferred from a cafe category, a conditional reading permission treated as unconditional, and three compound activities marked prohibited when their required evidence was incomplete. Source validation preserved the declared unknown status in all five cases.

The combined result depended on the source guard. Missing source evidence stays unknown even when both models assert support. Explicit, unambiguous source prohibitions stay contradicted even when a model disagrees. Conditional and conflicting facts stay unknown until their conditions are checked. The same source policy is used in the source+LLM ablation and the combined pipeline, so the AnyJev comparison does not benefit from a different guard.

A development-only diagnostic repeated L0 with and without the content-free prior correction. Without correction it returned 28/36 correct statuses with zero unsupported positives, while content-free correction returned 7/36 with 29 unsupported positives. The frozen main comparison was retained. This supports a configuration-specific explanation for the poor L0 result. It does not establish that AnyJev fails with every model or question. The diagnostic is in [prior-diagnostic.json](artifacts/catalog-2026-11-10/prior-diagnostic.json).

## Real-source coverage

All twenty real-source LLM extractions and actual AnyJev decisions completed. The active generation is `e119ffdc7f5d7b7e7e408599`, with source rule `explicit-negative-v2`. It was activated from cached raw model work after the source-rule correction, without another twenty provider calls. [The enrichment report](artifacts/catalog-2026-11-10/enrichment.json) marks those cache hits. [The initial uncached run](artifacts/catalog-2026-11-10/enrichment-initial-gate.json) preserves the first preparation observations.

| Real-source label state | Count |
|---|---:|
| Supported | 7/120 |
| Unknown | 113/120 |
| Contradicted | 0/120 |

The source can support bookshop-related activity and one accessibility fact. It does not establish personal-book reading, on-site coffee consumption, or their combination in a shared seating area. Therefore the twenty-place combined reading/coffee request has no fully supported result. This is a source-coverage gap. Model inference did not supply the missing venue evidence.

The twelve/eight real-venue split in the enrichment report is reserved for later external assessment. It is not labelled ground truth. Current business operation, permission changes, reservations and the actual experience of visitors still need independent evidence.

## Timing

There are three distinct timing boundaries.

| Measurement | Observed value | Boundary |
|---|---:|---|
| LLM extraction for real venues, median | 5.203 s/venue | One full six-label extraction |
| AnyJev L0 for real venues, median | 1.920 s/venue | Six claim decisions |
| Sum of twenty uncached per-venue preparation times | 170.873 s | Sequential processing observations, excluding initial runtime/model loading |
| LLM extraction for controlled cases, median | 4.601 s/case | Six authored claims |
| AnyJev L0 for controlled cases, median | 1.813 s/case | Six claim decisions |
| AnyJev raw for controlled cases, median | 0.605 s/case | Six raw decisions |
| Local HTTP matching, median over 40 requests | 0.866 ms | Loopback HTTP plus catalogue matching |
| Local HTTP matching, p95 | 1.135 ms | Same 40 requests |
| First measured local HTTP request | 15.013 ms | First observation, without claiming an OS-cold cache |
| Simulator request after answering a preference | 0.430 s | One observation, including the 350 ms debounce, through model-state update |
| Simulator request after restoring the session | 0.268 s | One observation without debounce, through model-state update |

Local HTTP timing is from [http.json](artifacts/catalog-2026-11-10/http.json). Provider-attempt counters were unchanged before and after all forty requests. The catalogue generation remained the same throughout.

The Simulator additionally records request start through decoded response and model-state update. Its observations are in [simulator-client-timing.json](artifacts/catalog-2026-11-10/simulator-client-timing.json). The record distinguishes requests containing the 350 ms debounce from restored-session requests without it. It excludes final frame rendering, and two observations are not a latency distribution. These app observations are reported separately from the sub-millisecond local HTTP result.

The benchmark does not time route/order generation. The earlier Google discovery HTTP result, the previous E5 top-result preference probes and earlier route benchmarks use different work boundaries and datasets. They cannot be pooled into a single speedup or accuracy percentage.

## HTTP scenarios

Five repetitions per scenario, on the same active twenty-entity generation.

| Scenario | Returned candidates | Fully supported candidates | Median HTTP |
|---|---:|---:|---:|
| Broad reading interest | 13 | 0 | 1.078 ms |
| Required personal-book reading | 13 | 0 | 0.865 ms |
| Required browsing/purchasing books | 13 | 6 | 0.748 ms |
| Required reading and coffee in one place | 20 | 0 | 0.984 ms |
| Reading and coffee may be separate | 20 | 0 | 1.019 ms |
| Dated ninety-minute visit | 13 | 0 | 0.834 ms |
| Additional required walking preference | 13 | 0 | 0.836 ms |
| Area outside the temporary scope | 0 | 0 | 0.775 ms |

Unknown candidates remain visible with explanations. They are not counted as fully supported. Required contradictions are excluded when the source establishes one. The real-source sample has no such reading prohibition, so that exclusion is validated in controlled regression, not claimed as a field observation. A dated visit remains unknown because regular map hours cannot establish all dated exceptions.

## Build and interaction verification

Python regression passed 43 cases. Final Swift regression passed 13 cases, including the Jakarta calendar-day boundary for UTC source timestamps. Simulator builds succeeded.

[Python log](artifacts/catalog-2026-11-10/python-tests.log), [Swift log](artifacts/catalog-2026-11-10/swift-tests.log) and [source fingerprints](artifacts/catalog-2026-11-10/source-fingerprints.json) retain the final regression and code identities. The UI summaries retain the initial failure as well as the later passing correction, rather than counting retries as additional independent scenarios.

Five distinct UI scenarios passed across focused runs.

- Clarify an activity, save a choice, restore it and undo a change.
- Skip a question while retaining usable local choices.
- Start a new trip without carrying temporary preferences.
- Request a question from the actual configured LLM, without having it invent the user's answer.
- Load the active real catalogue, save a venue, expand missing-evidence details, open the summary, relaunch and retain the saved choice.

The last scenario initially failed because SwiftUI propagated the DisclosureGroup identifier to its children. Exported hierarchy evidence showed the text was present. The assertion now checks the user-visible explanation and the same scenario passed after correction. This failure was not presented as a product-data failure or discarded from the log.

UI inspection also found that taking the first ten characters of a UTC timestamp displayed the previous calendar date. The view now formats the date in Asia/Jakarta, with a regression case for that boundary.

Direct native-app input through computer use failed with `noWindowsAvailable` on Device Hub. The initial app screenshot was observable. Interaction verification used actual XCTest execution on the same Simulator, with passing attachments. [Catalogue details](artifacts/catalog-2026-11-10/catalog-evidence.png) and [retained selection](artifacts/catalog-2026-11-10/catalog-selection.png) are from the passing run. Raw xcresult bundles stay in the ignored `.local` directory.

## Provider failures and corrections

The historical OpenRouter policy rejection is preserved in [openrouter-blocked.json](artifacts/catalog-2026-11-10/openrouter-blocked.json). The replacement endpoint passed a minimal authenticated JSON verification, then the first full extraction returned Markdown despite accepting `json_schema`. That failed preparation did not activate a partial catalogue. Its result and sanitized response are retained in [enrichment-json-contract-failed.json](artifacts/catalog-2026-11-10/enrichment-json-contract-failed.json) and [extraction-diagnostic.json](artifacts/catalog-2026-11-10/extraction-diagnostic.json).

The adapter now includes the schema in an explicit JSON instruction as well as the API parameter. Parsed output still undergoes field, ID and citation validation. The corrected campaign completed all 32 intended extractions, twenty real and twelve authored. Those successful extractions reported 11,191 prompt tokens and 9,200 completion tokens. This excludes diagnostics and the advisor verification. Monetary cost was not reported by the endpoint and remains unknown.

Credentials remain in the ignored `.env.catalog.local`, with mode 0600. They are not in the app bundle or these results. Source evidence and authored probes were sent for extraction. Google content and evaluator expectations were excluded.

## Implementation choice supported by this campaign

Source-checked data provides the decisive protection in these probes. Source+LLM and source+LLM+AnyJev tied, while explicit structured-source rules alone also matched every authored status. Consequently, this experiment does not justify requiring AnyJev as the final authority for user-facing recommendations. The implemented combined path remains available as an experiment, with its source guard enabled.

The largest remaining constraint on real preference fit is missing venue evidence. Independent verification of the relevant reading/coffee conditions and feedback on actual recommendations are needed before claiming the catalogue improves user satisfaction. Further model work should be compared against the already successful source-guarded baseline on fresh, independently assessed examples.

Reproduction commands and configuration are in [catalog/README.md](catalog/README.md). All results above describe this bounded local campaign.

## OpenRouter logprobs follow-up

Later on 10 November, the user requested a free OpenRouter alternative. A fresh public catalogue and endpoint check found `logprobs` and `top_logprobs` on `liquid/lfm-3-1.7b:free`, `liquid/lfm-2.5-2.6b:free`, and `recursive/flint-v1.0:free`. All three were probed with the existing key, authored synthetic text, required parameter support, denied data collection, and a zero-price routing ceiling.

Both Liquid routes returned HTTP 404 with the account's Free model training data-policy restriction. Flint initially rejected disabling reasoning. With mandatory reasoning left enabled, it returned actual token log-probabilities for A, B and C, and reported cost USD 0. Three subsequent cyclic option rotations for one explicit reading-permission claim all returned HTTP 200, the correct letter and finite scores for all three candidates. Their response times were approximately 1.97, 1.73 and 1.40 seconds, with reported cost USD 0 for each. This is a capability check over one authored claim and is not a replacement accuracy benchmark.

The successful remote score source is therefore `recursive/flint-v1.0:free` through OpenRouter on this account. A production AnyJev adapter still needs to handle mandatory reasoning and score completeness explicitly. These returned scores concern the visible answer after the provider's reasoning, which differs from the earlier local no-thinking readout. No remote AnyJev accuracy claim is made from these API probes. The active catalogue/provider configuration was not changed by this investigation.

[Sanitized discovery and probe evidence](artifacts/catalog-2026-11-10/openrouter-logprobs.json) and [bounded probe script](scripts/probe-openrouter-logprobs.py) retain the requests' results. The script's mandatory-reasoning handling was corrected after the initial Flint error. Re-running it consumes the same persistent eight-attempt capability ceiling rather than resetting it.
