# Evidence catalogue v0.3

Verified checkpoint on 10 November 2026 after the user supplied the key and released testing. The full campaign, results and limits are in [the catalogue report](../CATALOG_RESULTS_2026-11-10.md). The source+LLM baseline and combined pipeline tied on the authored policy probes. Real-user preference fit is still unmeasured.

The temporary scope is configurable in `config.json`. It currently selects at most 20 cafe, library and bookshop source entities around Menteng–Cikini. Hotels, convenience stores and explicitly private/inaccessible entities are excluded. Scope and taxonomy remain open for discussion.

## Data and provenance

`osm-source.json` is a bounded OpenStreetMap snapshot retrieved on 10 November 2026. It contains 20 entities, selected in category rounds, with seven cafes, seven libraries and six bookshops. They are map records, not 20 independently field-verified operating businesses. Branch/tenant identities retain their OSM object type and ID. Different object IDs and similarly named branches are not automatically merged.

The snapshot is an ODbL derivative database. Preserve its attribution, license and access to the source data when distributing it. © OpenStreetMap contributors. License and attribution requirements are documented at <https://www.openstreetmap.org/copyright>. This source does not contain Google data. No Google result is sent into the enrichment pipeline or persisted in this catalogue.

Source retrieval follows the bounding box and category configuration. No location names or activity claims are encoded in the matching code. A category helps retrieve candidates. It does not prove personal-book reading permission, coffee availability, or permission to combine activities in a shared area.

Facts have stable IDs, source URLs and a retrieval timestamp. That timestamp means the source was fetched, not that somebody visited the venue that day. The real source may contain outdated or incomplete map records. Current opening status, personal-book policies and shared-area permissions generally remain unknown in this pilot. This limitation is part of the output.

## Label pipeline

1. Normalize a source object into an identity and inspectable facts.
2. Ask the configured LLM to return all six claims with supported/contradicted/unknown statuses and existing evidence IDs.
3. Run the actual AnyJev library at L0 with Qwen3-0.6B locally on MPS when available, otherwise CPU.
4. Validate model schema and citations. Positive labels require explicit structured source evidence and agreement from both models. Explicit source prohibitions remain contradicted even when a model disagrees. Missing, conflicting or unresolved conditional evidence remains unknown.
5. Store a complete catalogue generation in SQLite and atomically change the active pointer. A failed provider run keeps the last complete catalogue active.
6. Match user requirements from the active generation without model calls. Required contradictions are excluded. Missing, conflicting, conditional, stale, unsupported and date-specific information remains unknown.

The source guard is deliberately conservative. It can accept known structured assertions such as `shop=books`, `wheelchair=yes`, or `outdoor_seating=no`. It cannot certify new claims from arbitrary prose alone. Extending accepted evidence predicates and adding authorized observations are future work. LLM agreement cannot turn a missing fact into an established fact.

AnyJev uses next-token readout through its real Hugging Face backend. The library is `anyjev==0.3.0`. The model revision is pinned in `config.json`. L0 uses content-free prior correction, three option rotations and canonical ordering. Its distribution is an uncalibrated decision score. The 0.6 abstention threshold is provisional, fixed before the planned comparison, and has not been validated for this domain. No claim of superiority over rules or LLM-only extraction has been established.

The six initial predicates are personal-book reading, browsing/buying books, on-site coffee, personal-book reading with coffee in the same area, outdoor seating, and wheelchair access. The current user flow directly matches the first four. The last two are evidence experiments and do not create new preference questions automatically.

Reading with coffee is a specific compound claim. Independent reading and coffee statements, especially for different rooms, do not establish it. Book purchasing with coffee is a different compound activity and stays unknown until its own evidence contract exists. Conditional permissions remain unknown until the relevant visit conditions can be checked. Regular opening hours are visible as source information but never certify dated exceptions or the entire visit duration.

## Provider configuration

The user changed the provider from OpenRouter to an OpenAI-compatible endpoint during implementation. The active configuration is the ignored file `../.env.catalog.local`.

```dotenv
CATALOG_LLM_BASE_URL=https://luna-provider.example/v1
CATALOG_LLM_MODEL=cx/gpt-6-luna(max)
CATALOG_LLM_API_KEY=
CATALOG_LLM_MAX_CALLS=72
CATALOG_LLM_TIMEOUT_SECONDS=60
```

Fill only the API key. `env.example` is the shareable template. `POST /chat/completions` with the exact configured model ID was verified. The proxy accepted `json_schema` but returned Markdown on the first full extraction. The adapter now includes the JSON schema in the prompt, then parses and validates the output. An optional single retry switches a rejected API schema parameter to JSON object format. Provider-specific OpenRouter routing/price/reasoning fields are removed. Monetary cost is unknown unless the endpoint returns it.

The 72-attempt ceiling persists across client/service restarts and is keyed by provider/model identity. Failed and compatibility-retry attempts count. The endpoint key stays in server configuration and request headers. It is not bundled in the iOS app, logged, or included in result artifacts. Changing the key does not require rebuilding the app. The local app/service bearer is separate.

The configured provider also handles the optional clarification advisor after the service is restarted. Its longer timeout is reflected in the app. The user-facing disclosure names the configured AI service generically. Local clarification remains available.

## Reproduce

Run from the Preference Lab directory. These are reproduction instructions. Actual outcomes are recorded in the linked result report.

```bash
uv venv --python 3.12 .local/label-venv
uv pip install --python .local/label-venv/bin/python -r catalog/requirements-labels.txt
HF_HOME="$PWD/.local/huggingface" HF_HUB_DISABLE_XET=1 .local/label-venv/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen3-0.6B', revision='c1899de289a04d12100db370d81485cdf75e47ca', allow_patterns=['*.json','*.safetensors','*.txt','*.jinja'])"
```

The environment and weights were already downloaded for this checkpoint. Reuse them instead of reinstalling on this machine.

```bash
python3 scripts/catalog-lab.py status
.local/label-venv/bin/python scripts/catalog-lab.py prepare
.local/label-venv/bin/python scripts/benchmark-catalog.py --live
python3 scripts/server.py stop
python3 scripts/server.py start
python3 scripts/benchmark-catalog.py --http
python3 scripts/benchmark-catalog.py --replay artifacts/catalog-2026-11-10/controlled.json
```

`prepare` enriches the saved real source and activates only a complete generation. It stops at the first provider failure. The controlled benchmark uses separate authored cases and never activates them in the real-place database. Successful cached inference can be reused by exact payload, pipeline, provider and judge configuration. Each report marks cache hits. Failed extraction is not cached as successful model work.

Refreshing the source is a separate explicit operation.

```bash
python3 scripts/catalog-lab.py fetch
```

An HTTP-only benchmark requires an active catalogue and owned local service. It refuses to count an empty readiness response as a successful benchmark. It measures loopback request and matching time, excluding catalogue preparation and UI rendering. These timings are not route/order-computation benchmarks.

## Validation protocol

- Python regression for existing providers and new source, evidence, quota, citation, activation, missing-key and matching behavior.
- Swift package checks and an iOS 27.2 Simulator build.
- Opt-in `PREFERENCE_CATALOG_UI=1` UI test for actual catalogue results, unknown explanations, saved choices and relaunch.
- Twelve authored evidence probes with six claims each. First six are development probes and last six are held out. Expected labels are evaluator-only and never enter prompts.
- Compare literal structured evidence, raw LLM, raw AnyJev, L0 AnyJev, source-guarded LLM and the combined pipeline. Report decisive recall, abstentions, unsupported positives and failures alongside exact classification accuracy.
- Eight HTTP scenarios, five repetitions each. Record actual generation ID, counts, excluded candidates, server time and client time. Provider-attempt counters are compared before and after the requests.
- Real-place identities have a frozen 12/8 split for later external assessment. This split provides no field ground truth by itself.

The authored probes exercise our declared evidence policy and accepted structured predicates. They are not an independent benchmark of personal taste. More unknown outcomes must not be sold as a quality gain without reporting the reduction in useful coverage. Human preference-fit and current venue conditions remain unmeasured.

## Pre-key observations

Before the testing hold, one AnyJev/MPS smoke completed, and the real OSM source fetch succeeded. The initial OpenRouter campaign failed all 20 extractions with HTTP 404. A sanitized diagnostic reported an account data-policy rejection for free model training. That failed campaign is retained as `../artifacts/catalog-2026-11-10/openrouter-blocked.json` and did not activate a catalogue.

The preliminary AnyJev smoke produced an incorrect category-only decision with a score below the provisional acceptance threshold. It used a preliminary question. Subsequent results after the user released testing are in the full report. They include the final controlled comparison, a prior-correction diagnostic, active real catalogue, HTTP timings, regression checks and Simulator verification.
