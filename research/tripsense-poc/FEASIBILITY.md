# Feasibility and evidence — 3 November 2026

## Overpass request reliability — 4 November 2026

Request configuration now has an explicit TripSense User-Agent and a 60-second timeout for both network inactivity and total resource transfer, while the optimizer retains its 180-second deadline. A host-scoped shared gate serializes requests and suppresses subsequent calls for at least 30 seconds after HTTP 406/429, or longer when `Retry-After` requires it. HTTP-date and delay-seconds formats are accepted; no automatic retry loop is used.

A fixed public-query probe is shared by the Mac CLI and iPhone app, with a request-body hash for reproducibility. The first post-change Mac execution received **HTTP 502 in 0.64 seconds**. It did not return valid OSM data; hours remain unknown. This is a separate observation from the earlier timeout/406 results and does not establish that provider availability is repaired. Physical comparison evidence will be recorded below once executable device access is established.

## Update: route optimization and OSM — 3 November 2026

The four-stage implementation now uses a directed ETA matrix and exhaustive bounded combination/order search, followed by departure-time route validation. It supports locked candidates and conservative OSM opening-hours lookup. Previous experiment sections below are historical, before this optimizer was implemented.

| Live Mac scenario | Solver result | Revalidated baseline | Result |
|---|---:|---:|---|
| [A: three museums](evidence/optimization-a.txt) | 3,260 s | 3,806 s | 6 orders, 546 s less travel |
| [B: four museums](evidence/optimization-b.txt) | 4,922 s | 4,993 s | 24 orders, 71 s less travel |
| [D: mixed, six candidates / four stops](evidence/optimization-d.txt) | 2,709 s | 3,131 s | 336 theme-valid orders, 422 s less travel; result replaced one initial place |

All comparisons use the same candidate pool within each run; D is a combination comparison, not the same set of four final destinations. The recorded counters in these runs are logical lookups, including cache hits, despite the older label “requests”. Baselines were revalidated at each segment departure. These results demonstrate the observed examples, not globally optimal real traffic, historical relevance or venue opening.

**OSM live status: UNSUPPORTED OR UNVERIFIED in this environment.** The [six-place audit](evidence/osm-hours-audit.txt) located 6/6 places with MapKit, but the Overpass lookup failed and all OSM hours remained unknown. A diagnostic attempt returned `NSURLErrorDomain -1001` (timeout); separate direct GET probes to the configured endpoint returned HTTP 406. Alternate public Overpass status endpoints timed out. This does not establish OSM coverage or that any place lacks data. Fixture responses demonstrate parsing/matching/fallback only.

For later comparison, official museum pages were found for [Museum Nasional](https://www.museumnasional.or.id/layanan-blu/), [Galeri Nasional](https://gni.kemenbud.go.id/kunjungi-kami), and [Museum Taman Prasasti](https://www.mitramuseumjakarta.id/prasasti); the first page timed out when opened. No authoritative branch-specific hours were established for the three cafes. No comparison of OSM hours to official sources was possible while OSM lookup failed. Do not treat these links as a verified live hours feed.

**Final local checks:** 38 deterministic package tests passed (one opt-in live test skipped), and 3 iOS Simulator app unit tests passed. Evidence: [package test output](evidence/optimization-unit-tests.txt) and [Simulator summary](evidence/optimization-ios-tests.json).

**Known boundary:** model-category matching is approximate; D selected one gallery and three cafes, so the history/museum suitability and overall balance remain unverified. Device, interactive UI and accessibility acceptance remain open. [Apple's documentation](https://developer.apple.com/documentation/mapkit/mkdirections) advises requesting directions when the corresponding information will be presented; review the matrix and alternative-route use before production.

## Original POC conclusion (historical)

Native on-device Foundation Models can call a custom Swift `Tool` that uses `MKLocalSearch`: **VERIFIED on the local Mac**, including an actual transcript and a separate passing live integration test. The application-specific tools also performed actual MapKit searches/directions and produced native-validated Jakarta schedules. This does not establish physical iPhone execution, globally efficient travel ordering, venue opening accuracy or recommendation quality.

The experiment found concrete model errors: an unrelated cafe justified with unsupported “historical ambiance”, and five proposed stops when four were requested. Native ID/category/count validation handles those boundaries. The geometric ordering heuristic was worse than the model-order baseline in the recorded four-stop experiment. Real operating hours remain unknown.

## Environment and requirements

- Observed Xcode 27.2 (27B52), Apple Swift 6.4.2, iOS/iOS Simulator SDK 27.2, macOS SDK 27.2; Swift 6 language mode.
- SDK declarations mark `LanguageModelSession`, `Tool`, `@Generable` and `@Guide` as iOS/macOS 26.0+. `MKMapItem.location`, `address` and location initializer also require OS 26. Deployment is set to 26.0, independently of SDK/test runtime 27.2.
- A local development signing identity is installed. No private key, credential or profile is included. The iOS build uses no signing; Simulator app tests use ad hoc signing. A team must be selected for a personal-device run.
- Mac model availability was `available`. `supportsLocale(en_US)` was `true`; `supportsLocale(id_ID)` was `false`. The recorded language set is in [live-tool-test.txt](evidence/live-tool-test.txt). No claim of Indonesian generation quality or support follows from English execution.
- Paired physical devices were discoverable, but their Apple Intelligence configuration and ownership/selection were not established. No app was installed/launched on a phone. Physical-device validation is pending, not reported as unavailable hardware.

## Capability statuses

| Capability | Status | Evidence / boundary |
|---|---|---|
| Custom Tool registered with LanguageModelSession | VERIFIED | Local Mac transcript in live-tool-test.txt |
| Actual model-invoked MKLocalSearch with real results | VERIFIED | One successful tool call; National Museum, Indonesia National Gallery, Museum Taman Prasasti |
| Typed @Generable arguments/results and recommendations | VERIFIED | Application-specific tools ran in live scenario records; iOS compilation also passes |
| MapKit names, IDs, coordinates, categories and addresses | VERIFIED | Live search records; missing fields retain unknown/session-ID semantics |
| Walking MKDirections distance, ETA and polyline | VERIFIED | Live scenarios record actual meter/second/geometry-point results; full geometry remains native |
| Driving and departure-date API support | SUPPORTED BUT NOT EXECUTED | SDK request transport/departure properties, compiled implementation; no live driving experiment |
| Deterministic time budget / duplicate-ID / invalid-ID / hours checks | VERIFIED | Explicit synthetic unit tests; over-budget live scenario rejected |
| Structured itinerary / remove-and-recalculate / cancellation | VERIFIED | Core tests and 2 Simulator application unit tests, fixture mode |
| Real structured business opening hours from public MapKit | UNSUPPORTED OR UNVERIFIED | No opening/business-hours member found in the inspected iOS and macOS 27.2 MKMapItem headers; OSM lookup exists but has not succeeded live here |
| Verified-hours provider integration with a real venue source | UNSUPPORTED OR UNVERIFIED | Injection interface exists; verified-status windows are exercised only as test inputs |
| Fixture opening restrictions | DEMO ONLY | Clearly marked synthetic windows; waiting and closed-visit tests |
| English model generation | VERIFIED | Actual local Mac responses |
| Indonesian model generation | UNSUPPORTED OR UNVERIFIED | Local locale check returned false; not attempted |
| Physical iPhone inference and end-user UI flow | SUPPORTED BUT NOT EXECUTED | App builds; no phone execution or interactive UI acceptance |
| Light/dark, VoiceOver and visual polish acceptance | SUPPORTED BUT NOT EXECUTED | Native adaptive controls/type used; no visual or accessibility inspection performed |
| Global real-world optimization / best route | UNSUPPORTED OR UNVERIFIED | Exhaustive snapshot matrix plus up to five time-dependent refinements; estimated values and limited candidates cannot establish a global real-world optimum |

## Original experiments and observed outcomes (historical)

### Small integration experiment

`rtk swift run --package-path research/tripsense-poc TripSenseProbe` first compiled and ran before the full app was built. Model was available and made one actual search tool call. Initial generation took 4.96 seconds and returned two names from three real MapKit results. The dedicated opt-in test subsequently passed in 4.24 seconds; it captured the entire fixed-public-scenario transcript in [live-tool-test.txt](evidence/live-tool-test.txt). These are separate executions, not a physical-phone test.

### A — Thematic compatibility

[Final run](evidence/scenario-a.txt): native selection contains National Museum, Museum Taman Prasasti and Indonesia National Gallery, all retrieved as MapKit museums. Three 45-minute visits, 5-minute arrival buffers, 4,821 route meters and 3,806 travel seconds fit the five-hour budget. Elapsed itinerary time is 3h33m26s. Hours are unknown for every venue.

[Initial run](evidence/scenario-a-initial.txt) contained a cafe whose model explanation asserted historical ambiance. Native category selection was added and regression-tested. Museum category is a broad thematic proxy; it does not verify every museum's historical content. Model explanations remain unverified interpretation.

### B — Efficient routing and constraints

[Final run](evidence/scenario-b.txt): four retrieved museums, eight-hour budget, 10,955 route meters, 9,320 travel seconds, 10,800 visit seconds, four 5-minute buffers. End-to-end elapsed time is 5h55m20s. The native geographic heuristic took **1,096 seconds longer** than the same destinations in the baseline order (8,224 travel seconds). Actual MapKit ETAs at each candidate departure were used. This is evidence against treating nearest-geographic ordering as reliably efficient, not evidence of optimization.

The comparison baseline is the native category/count-validated model order, before geographic reordering. No all-pairs route matrix was calculated. The first-leg route cache hit is recorded.

Earlier attempts are retained: [empty MapKit match](evidence/scenario-b-initial.txt), [five-hour over-budget rejection](evidence/scenario-b-overbudget.txt), [too many model choices](evidence/scenario-b-extra-stops.txt). These led respectively to explicit no-match handling, confirmed rejection behavior, and native count bounding. They are not silently excluded from evidence.

### C — Opening restrictions

DEMO ONLY / synthetic verified-status test inputs. Tests reject a closed visit, wait for the next opening window, preserve demo provenance, and leave unknown hours unasserted. No model manufactures hours and MapKit presence is never interpreted as “open”. Fixture hours are deliberately deterministic, not a representation of Jakarta business schedules.

### D — Mixed preferences

The [live run](evidence/scenario-d.txt) contains National Museum plus three cafe-category destinations: Loko Cafe, D'Stupid Baker and Kopi Nako Monas. Four stops fit the six-hour budget: 4,162 route meters, 3,222 travel seconds, 10,800 visit seconds, 20 buffer minutes; elapsed 4h13m42s. The model proposed two stops; native variety/category selection filled the desired count from retrieved results. This achieves museum/history plus coffee, but the three-cafe balance demonstrates limited recommendation quality. Native additions are labeled and hours remain unknown.

## Original verification and limits (historical)

Observed final checks: **17 deterministic package tests passed, 1 opt-in live test skipped in the default run; the dedicated live test passed separately; 2 Simulator application tests passed**. Generic iOS Simulator build passed. Swift formatting and whitespace checks are tracked in the task handoff.

Exact reproducible commands are in [README](README.md). Default Swift Testing covers same/mixed theme selection, unrelated model choices, excess count, actual-route arithmetic/order, hours conflicts/waiting/unknown, insufficient duration, duplicate/invalid IDs, empty results, route errors, unavailable models, removal, invalid input and category tags. The live test is opt-in and requires real services. Application XCTest covers fixture generation/removal and cancellation on iPhone 18 Pro Simulator iOS 27.2, without UI automation.

Captured records use a fixed public Jakarta request, no current-device location or account data. Diagnostics for arbitrary inputs redact query, custom coordinates and departure timestamp; destination IDs remain visible in memory. Captured transcripts are limited to the fixed public probe. No backend, paid model, provider token, external package, shared mutation, commit or push is involved.

Important limitations: route ETAs/coverage can change; the nearest-neighbor/outward-distance proxy may backtrack; hours remain unknown; model explanations can be wrong; requested count may exceed available relevant candidates; custom origin uses the first search match; locality can extend beyond administrative Central Jakarta within the radius; exact-departure cache has limited reuse; no persistence or return leg. Cancellation ignores stale UI results, but an underlying system request may finish during cancellation. Device, interactive UI and accessibility acceptance remain separate work.

## Official sources and inspected APIs

Current Apple documentation was retrieved through Context7; installed SDK declarations were inspected to resolve exact availability and property spelling. Apple's itinerary sample supplied the concept of registering a points-of-interest Tool; the POC does not copy its unrelated multi-day features or assume the sample establishes real travel feasibility.

- [Apple: adding intelligent app features with generative models (itinerary sample)](https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models)
- [Apple: expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- [Apple: SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Apple: supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
- [Apple: MKMapItem](https://developer.apple.com/documentation/mapkit/mkmapitem)
- [Apple: MKLocalSearch.Request](https://developer.apple.com/documentation/mapkit/mklocalsearch/request)
- [Apple: MKDirections](https://developer.apple.com/documentation/mapkit/mkdirections)
- [Apple: Apple Intelligence requirements](https://support.apple.com/en-us/121115)

Installed evidence sources: `FoundationModels.framework/Modules/FoundationModels.swiftmodule/*swiftinterface`, `MapKit.framework/Headers/MKMapItem.h`, `MKLocalSearchRequest.h`, and `MKDirectionsRequest.h` under the Xcode 27.2 iOS/macOS SDKs. Negative header evidence is scoped to those public APIs, not a universal statement about all Apple services.
