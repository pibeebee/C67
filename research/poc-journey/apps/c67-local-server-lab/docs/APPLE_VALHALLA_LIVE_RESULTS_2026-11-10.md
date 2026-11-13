# Apple native MapKit versus local Valhalla: matched live comparison

Date: 2026-11-10 (Jakarta). Scope: standalone routing benchmark in the Context Lab package on `codex/routing-access-benchmark`. This report covers the new live comparison only. It does not replace the [earlier benchmark checkpoint](ROUTING_BENCHMARK_RESULTS_2026-11-10.md).

## Decision

**Valhalla is the measured runtime winner in this environment.** The median paired Valhalla/Apple service-time ratio is 0.083 for automobile and 0.0367 for walking: approximately **12.1× and 27.3× faster**, respectively. This includes local HTTP/decoding versus Apple's managed service/network/decoding; it is not a comparison of algorithm complexity on equal hardware.

**Neither provider is established as the winner for real ETA accuracy, legal access or correct customer entrances.** No observed trips or independently verified customer doors were available. Lower predicted travel time and a shorter snap distance cannot establish those outcomes.

For the current iOS MVP, retain Apple as the final user-facing routing provider because it avoids operating a separate graph service and fits the existing native implementation. This is an operational recommendation, not a measured accuracy victory. Use Valhalla as an experimental candidate-ranking/walking accelerator behind an explicit adapter and evaluate final routes before adopting it. Do not change the app default based on this campaign.

## Actual execution and matching

- Apple requests used actual native `MKDirections.calculate` on the Mac, labelled `apple_mapkit_live`. This is **not Apple REST**; REST credentials were unavailable. No private key was needed for these native calls. Google requests: **zero**, as requested.
- Valhalla used the pinned local container and existing extracted Jakarta graph: version `3.9.1-52228c4e0`; image digest `sha256:f21f529beff825d5020183612c90a1630fdf00eb9f569570eebb815b06b1427c`. Colima allocation: 4 CPU / 6 GiB RAM. Speeds are static; no live traffic feed was configured.
- Source graph input SHA256: `9340256256dbff5a011df5a8de98810b20f9010c7a3d46f251295b6fccd558cc`; original PBF SHA256: `b7f66e5b9d93677f081c5a93fd67e8d08c7a63abead7de925bf3a3439cf004dc`.
- Sixteen sourced cafe POI coordinates cover Blok M, Cikini, Tebet, Senayan/SCBD, Kemang, Kebon Jeruk, Ragunan and Kuningan. Each venue was paired with its next neighbour in the manifest, including wrap-around, and then reversed: **32 directed pairs × 2 modes × 3 repetitions = 192 matched pairs / 384 requests**. These are 64 distinct OD/mode configurations repeated three times, not 192 independent routes.
- Each pair used identical typed endpoints, coordinates, mode, geometry request and requested departure. A SHA256 fingerprint records that identity. Departure was 30 minutes ahead, rounded to a minute to match Valhalla wire precision. Provider order alternated. Failures remained in the denominator. No retries were used.
- Apple dispatches were spaced by 1.2 seconds. Deliberate waiting is recorded separately and subtracted from **service latency**. Service latency still includes API/network/decoding and scheduling overhead; it is not server-only time. The route campaign checkpoints after every pair and stops on throttling/authentication/budget exhaustion. No such stop occurred.
- Only derived ratios, sampled geometry differences, endpoint-gap diagnostics, counts and timing/status metadata were archived. Raw routes, per-leg ETA/distance and provider payloads were not retained. POI centers were never relabelled as verified entrances.

## Road availability and latency

Percentiles use successful validated responses; unsuccessful responses remain in availability denominators. Nearest-rank percentiles are used. Paired speed ratios use only the 190 pairs where both responses passed validation.

| Mode | Provider | Valid / attempted | Service p50 | Service p95 | Wall p50 including pacing |
| --- | --- | ---: | ---: | ---: | ---: |
| Automobile | Apple native | 94 / 96 | 290.5 ms | 612.9 ms | 1,255.5 ms |
| Automobile | Valhalla local | 96 / 96 | 24.9 ms | 54.1 ms | 24.9 ms |
| Walking | Apple native | 96 / 96 | 257.6 ms | 489.9 ms | 1,161.8 ms |
| Walking | Valhalla local | 96 / 96 | 9.4 ms | 20.8 ms | 9.4 ms |

Apple valid-response rate was **190/192 = 98.96%**; Valhalla was **192/192 = 100%** in this sample. This is adapter acceptance, not a population-level reliability guarantee or proof that Apple could not find a road route.

The two rejected Apple automobile responses were both `Toko Kopi TUKU - GBK Senayan → Maxx Coffee`, repetitions 0 and 1; repetition 2 passed. The recorded failure was `invalidResponse`. Native validation checks endpoint correlation within 100 m and route/value validity. The original failed payloads and detailed rejected gaps were not archived, so the exact violating field cannot be reconstructed. Do not present these two observations as confirmed provider outages, inaccessible destinations or wrong-door incidents. More granular rejection telemetry is a follow-up.

First-pass versus repeated median service latencies were Apple automobile **305.0 → 290.5 ms**, walking **253.5 → 259.4 ms**; Valhalla automobile **26.9 → 22.3 ms**, walking **9.5 → 9.2 ms**. This does not isolate cold-cache behaviour: the graph was already running, two smoke pairs preceded the main run, and Apple may use managed caches. Graph download/build/startup are excluded.

## Route and ETA disagreement

All ratios below are **Valhalla / Apple**, not accuracy scores.

| Diagnostic | Automobile, 94 matched successes | Walking, 96 matched successes |
| --- | ---: | ---: |
| Median distance ratio | 1.0017 | 1.0018 |
| p95 distance ratio | 1.4084 | 1.6776 |
| Median predicted travel-time ratio | 0.6559 | 0.8070 |
| p95 predicted travel-time ratio | 1.5924 | 1.4572 |
| Median sampled geometry gap | 0.07 m | 0.11 m |
| p95 sampled geometry gap | 2,144.6 m | 796.2 m |
| Maximum sampled geometry gap | 3,356.3 m | 806.2 m |
| Apple endpoint-gap p95 | 76.7 m | 43.9 m |
| Valhalla endpoint-gap p95 | 51.9 m | 22.0 m |

The geometry metric samples up to 32 vertices in each direction and measures nearest point-to-segment distances, then takes their median. It is sensitive to vertex distribution and is not a Hausdorff distance, legality test or visual/field acceptance. Maximum disagreement was `Berkala Coffee → Keep On` for driving and `Tanamera → Kopi Buntu` for walking. Similar median distances coexist with substantial route differences in the tail. Valhalla predicted less time in the median; static speeds versus Apple expected-travel-time semantics and different routes prevent attributing that difference solely to traffic or claiming better ETA.

## Controlled itinerary calculations

Six fixed-order round trips used the first 1, 3 or 6 destinations from the same manifest, in automobile and walking modes, returning to the origin. Every leg made fresh live provider calls. Provider order alternated within each itinerary. Each next departure was one shared conservative timestamp, advancing by the larger previous predicted duration plus a controlled 30-minute visit, rounded up to a minute. Both providers therefore received identical leg departure inputs.

Visit duration, a 12-hour arithmetic budget and unrestricted visit availability were **authored controls**, not sourced opening hours, live weather or personal recommendations. This directly accumulates travel estimates; it does not execute the Context optional-stop/beam planner or the editor UI. Elapsed ratios and deadline flags below refer to **summed travel estimates plus dwell**, excluding padding introduced to align common departures. They are arithmetic-budget checks, not proof of a fully scheduled itinerary. Destination order is fixed by construction; no provider optimizes it or omits required destinations.

| Destinations / mode | Calls each | Both complete | Apple wall, includes pacing | Valhalla wall | Travel-time ratio | Travel + dwell ratio |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| 1 / automobile | 2 | Yes | 1.385 s | 0.052 s | 0.9341 | 0.9894 |
| 1 / walking | 2 | Yes | 2.563 s | 0.026 s | 0.9119 | 0.9851 |
| 3 / automobile | 4 | Yes | 5.187 s | 0.126 s | 0.8237 | 0.9243 |
| 3 / walking | 4 | Yes | 4.415 s | 0.044 s | 0.7647 | 0.8208 |
| 6 / automobile | 7 | Yes | 8.438 s | 0.177 s | 0.8190 | 0.9372 |
| 6 / walking | 7 | Yes | 8.475 s | 0.130 s | 0.7702 | 0.8410 |

All six completed with every requested destination and return leg and stayed within the controlled arithmetic budget on both providers. These wall times intentionally include the Apple pacing policy and must not be described as pure service speedups. The road table above is the appropriate latency comparison with pacing removed.

## Shared TransJakarta comparison

The existing `BuswayRoutingService` was used unchanged for scheduling and direct/one-transfer search. Only walking adapters differed. Both used the same static attributed network, endpoints and top-level departure; subsequent walking departures can differ as estimated access durations affect readiness. This is a system comparison, not a claim that every internal walk query was paired at the same time.

Endpoints used published stop coordinates with a controlled approximately 55 m northward offset. They are not verified public station entrances. Walking queries were live; bus schedules, frequency waiting buffers and interchange rules were **static GTFS**, not real-time vehicle observations. Feed checked 2026-11-06, archive last modified 2026-10-30, SHA256 `376b11f72ac30f9f4eb972ae32c7f1a3251b416dc3cd77cc573475a3b2676b9c`. The existing freshness check passed on 2026-11-10. Each case had a 32-call walking budget per provider.

| Case | Selected service, both providers | Walking calls Apple / Valhalla | Apple wall, includes pacing | Valhalla wall | Total predicted journey ratio |
| --- | --- | ---: | ---: | ---: | ---: |
| Bundaran HI → Blok M | 1, direct BRT | 10 / 10 | 11.736 s | 0.053 s | 0.9853 |
| Blok M → Bundaran HI | 1, reverse BRT | 7 / 7 | 7.756 s | 0.040 s | 0.9915 |
| Ragunan → Kota | 6A → 1, one transfer | 16 / 16 | 18.877 s | 0.170 s | 0.9920 |
| Dirjen Anggaran approach → Rawamangun approach | JAK.35, non-BRT Mikrotrans | 19 / 18 | 23.027 s | 0.101 s | 0.9685 |

All four succeeded and validated on both adapters. The last case chose **JAK.35**, although its endpoints were taken from a JAK.74 pattern; the engine was free to choose the feasible network service. It is not a demonstrated JAK.74 journey. Different candidate exploration explains unequal walking-call counts; these are calls for searching, not the number of journey segments. No car fallback or synthetic bus patterns were used. No BRT-to-non-BRT transfer or real station-gate traversal was established by these four cases.

## Verification and local evidence

Evidence root: `poc-journey/.verification/apple-valhalla-20261110/` (ignored, local).

- `smoke/paired-observations.json`: two initial matched live pairs, both modes successful on both providers.
- `roads/paired-observations.json`: all 192 road pairs; `roads/summary.json`: zero audit errors; `roads/repetition-summary.json`: first versus repeated timings.
- `controlled/controlled-observations.json`: six controlled itinerary and two direct/reverse TJ comparisons.
- `transit/controlled-observations.json`: transfer and non-BRT comparisons.
- `matched-tests.log`: seven deterministic tests passed for callback timeout/cancellation/late or duplicate callbacks, request cap/reentrancy, endpoint rejection, matching/repetition, safe exports and geometry diagnostics.
- `context-final-tests.log`, `trip-tests.log`, `python-tests.log`, `format.log`, `evidence.log`, `portability.log`, `diff-check.log`: final regression/static verification records. Final totals: Context 151 XCTest passed / 1 intentionally skipped plus 35 Swift Testing passed; Trip Integration 81 passed; Python 66 passed; formatter 0/392 files need changes; evidence 3,415 imports / 26 maintained entries; portability 3,581 files passed.

The Python auditor checks two providers per pair, identical hashes/modes, alternating positions, finite timing decomposition, ratio/availability consistency, complete coverage or explicit stop, and exclusion of unapproved payload fields. Four additional auditor tests reject tampering and misleading unavailable-pair statistics. Existing CI discovers the Python tests; live provider calls are manual only. Native app builds and Simulator UI acceptance were not rerun for this CLI-only extension; previous build evidence remains historical. Hosted CI, device behaviour and production readiness are not claimed.

## Remaining limitations and next decision

1. Establish independent, public, mode-specific cafe entrances and station access points, then inspect sampled route geometry and conduct observed trips. Current snap/geometry diagnostics cannot detect a back door, fence, private passage or unsafe crossing reliably.
2. Measure field ETA error and route legality before replacing final routing. This campaign has no travel-time ground truth and no traffic parity.
3. Validate deployed Valhalla latency, concurrency, memory, graph refresh/turn restriction completeness and boundary handling. Loopback performance with a running graph does not establish mobile-to-server production latency or total operating cost.
4. Add rejected-response diagnostic categories without archiving raw provider content. Two transient Apple validation rejections remain incompletely diagnosed.
5. Broaden independent routes, peak/off-peak dates, long-tail closures, weather and access conditions. Three correlated repetitions and four TJ paths do not establish Jakarta-wide coverage.
6. Test full Context planner/editor integration with sourced venue context separately. These controlled fixed-order calculations demonstrate routing arithmetic, not personalized itinerary quality or live opening-hour feasibility.
7. Keep candidate pruning experimental: the prior adversarial benchmark showed it can miss a better itinerary. Faster routing does not remove search-quality tradeoffs.

No production contract, app default, data feed or deployed service was changed; no commit, push or PR was performed.
