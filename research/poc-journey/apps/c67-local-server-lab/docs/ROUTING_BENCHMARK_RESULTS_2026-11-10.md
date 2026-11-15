# Routing benchmark results — 10 November 2026

## Outcome

Implemented on `codex/routing-access-benchmark` from main `0a06e1d`. The CLI isolates endpoint selection, routing adapters, shared Context/TJ planning, budgets and safe observations. Application defaults and the live editor storage policy are unchanged. No production integration, commit, push, PR or deployment is included.

**The local Valhalla graph works and the finalist policy reduces synthetic calculation work. No provider has yet demonstrated better cafe-door correctness or real traffic ETA accuracy in this POC.** Google live is explicitly skipped at the user's request because paid APIs are not needed for this MVP evaluation. Apple live remains unexecuted because its provider configuration is absent.

## Synthetic campaign

The delivery campaign contains **1,002 observations**, three repetitions, and **102 baseline/finalist pairs**. The independent export/invariant auditor reports zero issues. Outcomes: available: 768, candidate: 222, expected_match: 12.

All 222 candidate observations preserve their requested required destinations, manual order where applicable, return deadline, and elapsed arithmetic. The 12 direct/transfer/direction controls match their expected outcomes. These are authored services and travel models, not live bus or road observations.

| Synthetic model | Paired n | Median paired runtime reduction | Calls saved over paired runs | Maximum elapsed regret |
| --- | ---: | ---: | ---: | ---: |
| `apple_access` | 18 | 83.89% | 420 | 0 s |
| `apple_pin` | 18 | 85.04% | 423 | 0 s |
| `google_place_id` | 18 | 79.13% | 420 | 0 s |
| `shared_tj_synthetic_walking` | 27 | 58.09% | 51 | 0 s |
| `synthetic_directed_roads` | 3 | 97.75% | 258 | 840 s |
| `valhalla_access` | 18 | 87.01% | 420 | 0 s |

Provider-labelled synthetic rows all use the explicitly synthetic routing implementation. Differences between those labels are not evidence that Apple, Google or Valhalla is faster. The ordinary travel model is distance-based and aligned with the ranking prior, so its zero observed regret is optimistic and cannot establish generalization. Mixed-size p50/p95 also combines very different workloads.

**Adversarial finding:** directed-road travel deliberately contradicts the local prior. The faster method retains all hard rules but returns a trip **840 seconds (14 minutes) longer** than the broader baseline in each of three repetitions. The bounded-search flag remains visible. The 30% exploratory calculation-speed target is reached in these synthetic paired groups; schedule quality is not universally preserved. This is why the policy remains benchmark-only.

## Real local graph queries

The official Valhalla image is pinned to digest `sha256:f21f529beff825d5020183612c90a1630fdf00eb9f569570eebb815b06b1427c`, engine `3.9.1-52228c4e0`, running on a dedicated Colima profile (4 CPUs / 6 GiB). The dated Geofabrik Java source was checked against its published MD5; original source and extracted-input SHA256 values are in the source manifest. The bounded extraction retained 12,661,723 nodes and 3,030,454 ways, with 1,394 named cafes available for sampling.

**96/96 real local HTTP route queries succeeded** between successive sourced POIs: 16 cafe targets × driving/walking × three repetitions. Geometry was decoded and its start/end checked against requested points. These are `valhalla_poi_probe` observations, not entrance-qualified variants.

| Mode | Successful n | Median query latency | Nearest-rank p95 |
| --- | ---: | ---: | ---: |
| walking | 48 | 7.62 ms | 64.61 ms |
| automobile | 48 | 12.19 ms | 74.79 ms |

The graph uses static speeds, with no traffic feed. The measurements exclude download, extraction and graph preparation and include local HTTP/decoding. Startup/build was performed separately, but no precise cold-start comparison was instrumented. These small repeated samples are not throughput/SLA or field ETA evidence. Routes stay away from the extraction boundary; omitted boundary-crossing ways remain a graph limitation.

## Source and entrance coverage

Exactly two distinct OSM cafes were sampled for each of Blok M, Cikini, Tebet, Senayan/SCBD, Kemang, Kebon Jeruk, Ragunan and Kuningan. **All 16 have source-linked POI positions; zero currently have independently confirmed public customer-door references in this sample.** No POI center was relabelled as a door, and no Google coordinate was transferred to Apple/Valhalla. Cafe names and continued operation have not been field-confirmed.

OSM attribution: OpenStreetMap contributors, ODbL. Source SHA256: `b7f66e5b9d93677f081c5a93fd67e8d08c7a63abead7de925bf3a3439cf004dc`. Extracted graph-input SHA256: `9340256256dbff5a011df5a8de98810b20f9010c7a3d46f251295b6fccd558cc`. The [manifest](../fixtures/routing/jakarta-venues.json) retains source URLs, dates and bounds.

## Live prerequisites and safety

- Google live is disabled by default even when an API key is present; a regression test proves the paid route is not activated by key presence. Its outcomes are `disabledByScope`. Apple map credentials are absent in the active configuration. Both cases have zero external Apple/Google requests and no successful-query latency percentile; they are not provider routing failures.
- The existing live itinerary context acquisition still depends on Google Places. With paid acquisition disabled, that phase is not live-validated; the actual OSM road probe and synthetic context/TJ campaign remain usable independently. Removing Google Places from the recommendation app is outside this task.
- An explicit Google ID or conservative exact-name/proximity resolution is required. Google acquisition and route/matrix errors consume the same 200-request / 1,000-element cap. Failed requests are not retried; matrix missing cells remain unknown.
- TJ live itinerary comparison also needs valid public access points, current feed rules and walking evidence. Fixture success establishes adapter/shared-engine behavior only. Real platform doors, crossings, ramps and transfer weather exposure remain unverified.
- Provider snapshots/routes remain in memory. Exports exclude raw responses, coordinates, polylines, addresses, reviews and credentials. Detailed schedule-quality fields are synthetic-only. No Google geometry is displayed on Apple maps.
- Initial Overpass acquisition failed/timed out, so the source sample was extracted from the pinned PBF. The large PBF download timed out near completion, resumed successfully, and passed its source checksum. Python 3.15 lacked a compatible osmium wheel; extraction used an isolated Python 3.14 environment with osmium 4.2.0.
- Baseline compiler/deprecation diagnostics appeared during initial unsigned builds even though the processes exited successfully. Separate bounded-job confirmation builds produced explicit `BUILD SUCCEEDED` for both apps. Hosted CI has not run for this local diff.

## Verification

| Check | Evidence |
| --- | --- |
| Routing-specific XCTest | 19 tests passed: access/mode/freshness, budgets, matrix partial/auth failures, timeout, cache/coalescing, stale uncooperative results, fixed optional order, return deadline, empty draft, adversarial quality and TJ provenance/direct/transfer/staleness |
| Context Lab full package | 144 XCTest passed, one intentional historical benchmark skip, plus 35 Swift Testing cases passed; recommendation/context/editor compatibility retained |
| Trip Integration package | 81 Swift Testing cases passed, including existing feed/calendar/access/cancellation and Journey routing regressions |
| Python | 62 tests passed, including routing sample/auditor rejection controls |
| Synthetic executable + auditor | 1,002 observations / 102 pairs; zero auditor issues |
| Local Valhalla + auditor | 96 successful HTTP route queries; zero export/invariant audit issues |
| ContextHarness / Showcase | Both unsigned Simulator confirmation builds explicitly succeeded |
| Evidence, format, portability, links, whitespace | Passed: 3,415 immutable publication copies, 26 maintained-source entries, 3,573 publication files in the portability/link scan, SwiftFormat and whitespace checks |

No new Simulator UI, physical-device, human-fit or field-door acceptance was performed: this task adds no UI or app-default routing change. Raw safe execution outputs are under ignored `poc-journey/.verification/routing-20261110/`; intermediate/failed logs remain separate from delivery evidence.

The dedicated Valhalla container was stopped and restarted successfully using the same pinned image/graph; its status endpoint recovered. The runtime is stopped after verification, preserving the local graph for an explicit future run.

## Recommendation

Keep the faster policy experimental. Next, acquire independently supported public pedestrian/vehicle access for a small held-out subset, configure operator-owned Apple credentials, and run paired Apple/Valhalla queries. Google paid live tests remain excluded unless separately requested. Inspect endpoint connectivity separately from query latency. Do not enable the policy globally based on local graph speed or the distance-aligned synthetic cases.

See the [usage and protocol](ROUTING_BENCHMARK.md) and [task brief](../../../docs/tasks/routing-access-benchmark.md).
