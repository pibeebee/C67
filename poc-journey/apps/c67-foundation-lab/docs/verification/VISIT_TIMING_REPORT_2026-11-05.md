# Visit Timing Lab — sourced Jakarta facts and visit-time options

Date: **5 November 2026, Asia/Jakarta (WIB)**. Foundation Lab **v0.5, build 7**.

**Outcome:** separate tab **03 · Waktu** turns published venue rules, a planning duration and an optional time preference into visit-time options. It runs without Foundation Models, E5 or a hosted AI backend. Actual MapKit/forecast acquisition and calculation completed on Mac and a physical iPhone. Existing Foundation/preference screens and packages are retained.

This demonstrates **options supported by regular hours and available context**, not universal knowledge of the best time to experience a venue. Routing remains outside this experiment.

## Evidence and real-world grounding

The bundled catalog contains **11 actual Jakarta facilities**, manually curated from four official publications retrieved over HTTPS on 5 November. Each venue retains source references, retrieval time, a source-page SHA-256, regular sessions, published admission rules and unknown attributes. Dates are never moved forward to make old evidence appear current.

| Actual publication | Facts used and distinction tested |
| --- | --- |
| [Jaklitera official directory](https://perpustakaan.jakarta.go.id/supports/about-us) | Eight library/service locations. Cikini, Nyi Ageng Serang and PDS HB Jassin publish daily service and a Friday check-in interruption. Petojo also lists a Friday entry interruption. Jatinegara/Petojo list shorter weekend hours. Missing weekend hours for Tanjung Duren, Gandaria and Koja remain unknown. |
| [Museum MACAN visitor information](https://www.museummacan.org/visit) | Regular hours and a 17:30 last admission coexist with a temporary-closure announcement. That announcement was confirmed visible in a rendered browser, rather than inferred solely from HTML extraction. Suggestions are withheld pending recheck; the reopening date is unknown. |
| [Ragunan official website](https://ragunanzoo.jakarta.go.id/language/en/) | Tuesday–Sunday daytime service; Monday is explicitly closed. Outdoor context refers to the park, not every room/activity. |
| [Jakarta Pusat facility page](https://pusat.jakarta.go.id/kelurahan/kelurahan-gelora/fasilitas/fasilitas-taman-hutan-kota/taman-hutan-kota) | Hutan Kota GBK has two sessions with a midday gap and Monday closure. A whole visit must fit one session. |

These are **actual published rules**, not fictional venues or fabricated hours. They are not on-site observations of admission, current ticket inventory, emergency changes or holiday exceptions. Rechecking found the expected claims in **11/11 assertions across 4/4 pages**. This lightweight audit does not automatically update facts or replace manual review. [Audit](visit-timing-2026-11-05/source-recheck.json), [rendered-notice check](visit-timing-2026-11-05/browser-source-check.json).

## Implemented workflow

1. Choose venue/date, local availability and duration; opening-hours-only calculation needs no network. The default 60 minutes is visibly a **planning assumption**, not a sourced average stay. Display/calculation clocks use Jakarta time.
2. Native code finds start times at 15-minute intervals. The whole visit must fit a service session and local availability. Last admission and check-in pauses constrain **entry**. A check-in pause does not automatically prohibit staying after earlier valid entry.
3. Without a contextual preference, show up to three separated options and all valid start ranges. An arbitrary earliest slot is not called the venue's best visiting time.
4. For the two sourced outdoor venues, an optional action makes one MapKit search and one Open-Meteo request. A unique name match within Jakarta is required; ambiguity stops acquisition. No GPS permission is requested.
5. Fresh data supports lower-rain, daylight or near-sunset comparisons. The full duration needs hourly coverage; missing/null precipitation stays unknown. Lower-rain ranking uses maximum hourly probability over a visit; a displayed alternative can still have high probability. Daylight uses sunrise/sunset. Near-sunset uses an **application heuristic**: start within one hour before sunset and favor an end closer to sunset, within opening hours.
6. Sources, forecast coordinate/name/time, attribution, unknowns and explanations are visible. History and JSON/Markdown exports are separate. Input changes cancel pending work and invalidate its display. Switching tabs preserves completed output. Damaged history files are retained while valid runs remain readable.

Facts have a **seven-day application review policy**, including a bounded trip-date horizon. Old/historically incompatible facts require recheck. Forecasts have a 15-minute application lifetime and are tied to venue/date. Each acquisition stage has a 20-second limit without automatic retry; there is no 20-second promise for a whole run.

The new tab currently uses **Open-Meteo** for forecast/solar data; its [documented API](https://open-meteo.com/en/docs) supplies hourly probabilities and daily sunrise/sunset. WeatherKit's successful experiment remains in the separate routing PoC with its existing App ID. This work does not change portal settings, provision WeatherKit for Foundation Lab's different bundle ID, or claim WeatherKit was used by these timing runs.

## Verification

| Check | Result and scope |
| --- | --- |
| VisitTiming package | **28/28 tests passed**: publication-derived scenarios, actual forecast replays, source/date/zone checks, stale/unknown data and storage recovery. Deliberate mutations are labeled engineering fault injections. [Log](visit-timing-2026-11-05/timing-tests.log) |
| Published scenarios through Mac executable | **17/17 expected statuses** across all 11 facilities: Friday entry versus continued stay, weekend schedules, missing schedules, split sessions, Monday closure and the MACAN notice. Fixed dates are 5–9 November; these are not observed visits or an independent quality benchmark. [Cases, inputs and hashes](visit-timing-2026-11-05/published-cases/summary.json) |
| Existing package regression | **57/57 TripIntelligence** and **29/29 PreferenceLearning** tests passed. [Foundation log](visit-timing-2026-11-05/legacy-tests.log), [preference log](visit-timing-2026-11-05/preference-tests.log) |
| Simulator UI | **4/4 passed**, iPhone 18 Pro / iOS 27.2: two existing preference tests and two timing tests. Covered sourced closure/unknown/weekend states, relaunch/history/export, old tabs and preservation across tab switches. Timing UI cases use the real dated catalog, without a weather-provider substitute. [Summary](visit-timing-2026-11-05/ui-summary.json), [log](visit-timing-2026-11-05/ui-tests.log), [screenshots](../../../../docs/missing-evidence.md#missing-f0105973d3ff) |
| Actual Mac providers | Four actual MapKit/Open-Meteo runs completed; observations below. Development integration checks, not independent forecast/latency validation. |
| iOS builds | Simulator build/tests and signed physical-device build passed. [Signed build](visit-timing-2026-11-05/device-build.log) |
| Physical iPhone | **iPhone 17, iOS 27.0.1 (24A446)**: build 7 installed after unlock. One scripted MapKit → Open-Meteo → timing → saved JSON run completed in **1.407 s**, status context_ranked, three alternatives. [Run](visit-timing-2026-11-05/iphone/run.json), [console](visit-timing-2026-11-05/iphone/console.log), [install](visit-timing-2026-11-05/iphone/install.log) |
| Preservation and formatting | All **34 other files** in the 36-file prior-source/resource baseline stayed identical. App entry adds tab/launch flags; project configuration adds package/version. Strict formatting passed. [Audit](visit-timing-2026-11-05/preservation.json) |

Initial UI attempts failed because assertions searched for virtualized List rows outside the viewport; corrected tests navigate to controls/results. The completed-result check led to retaining completed output while cancelling only pending work when leaving the tab. Failed attempts remain under [development evidence](../../../../docs/missing-evidence.md#missing-fef66625f823).

The phone run is a pipeline smoke, not a full physical-device UI walkthrough or field trip. The harness stopped its attached process after capturing completed JSON; signal 15 in the console is that controlled stop. A subsequent cleanup renamed private API fields with explicit JSON coding keys; its actual Mac check and signed build passed. Reinstalling that final cleanup binary encountered a CoreDevice connection error. Physical evidence therefore belongs to the successfully installed build-7 binary before that naming-only cleanup; the byte-identical final binary has not been revalidated on iPhone. Locked-device and later connection failures are preserved and are not successful runs.

## Actual context observations

| Actual run, 5 November | Observation |
| --- | --- |
| [GBK lower rain](../../../../docs/missing-evidence.md#missing-736d450a9cee) | 1.480 s; 24 forecast hours, three alternatives. The eligible morning option had a lower probability than afternoon alternatives. These are forecasts, not observed rainfall. |
| [Ragunan near sunset](../../../../docs/missing-evidence.md#missing-f80bdc554737) | 1.124 s, **no supported option**. Provider sunset was around 17:47 WIB; regular closing was 16:00. Hours were not extended to satisfy the preference. |
| [GBK near sunset](../../../../docs/missing-evidence.md#missing-d9ac9ee1d1b7) | 1.377 s, one separated option inside the afternoon session. Relative-to-sunset heuristic, not verified golden-hour quality. |
| [GBK daylight, final adapter](../../../../docs/missing-evidence.md#missing-926ccf6dc302) | 1.415 s, three alternatives. Entire visits stayed within service sessions and provider daylight. |

These inputs/goals and the phone run differ; times are not comparative speed claims. Internal provider request counts/cache behavior were not measured.

## Feasibility decision and remaining gaps

**Supported:** native code can produce explainable, source-linked visit windows from a small real catalog, preserve unknowns, enforce published rules and apply explicit time preferences to actual environmental context. Model-generated venue knowledge is unnecessary for this bounded calculation.

**Not established:** the best actual experience, crowd/quietness estimates, reliable average stay, seats/coffee/ticket availability, in-venue forecast accuracy or reduced user effort. Holiday exceptions and sudden closures may be missing. Eight library locations share one source; eleven facilities are not eleven independent providers or a representative Jakarta sample.

**Data sustainability is open:** facts are manually curated and bundled. Retrieval/audit is reproducible, but there is no automatic web fact extractor, venue-wide provider or in-app source refresh. Broader coverage needs a maintainable acquisition/review path. Available hours do not establish that all desired venue attributes can be obtained.

**Integration remains next:** options are not inserted into an itinerary or sent to the routing optimizer. Arrival feasibility, travel duration and downstream conflicts are not calculated here. Place-ranking quality, combined preferences and user evaluation remain separate questions.

## Try and reproduce

Open **03 · Waktu**. Choose venue/date, then **Hitung** or **Hitung dari fakta**. For GBK/Ragunan, select a contextual goal and **Ambil prakiraan aktual & hitung**. Published cases retain original dates. After the review window, explicitly recheck facts instead of shifting fixture dates.

From the Foundation Lab folder:

~~~sh
bash scripts/run-visit-time.sh --venue cikini --date 2026-11-06 --start 660 --end 840 --duration 120 --out /tmp/c67-cikini
bash scripts/run-visit-time.sh --live --venue gbk --goal nearSunset --out /tmp/c67-timing-live
swift test --package-path Packages/VisitTiming
python3 scripts/verify-visit-sources.py --out /tmp/c67-source-check.json
# Supply the actual binary path from swift build --package-path Packages/VisitTiming --show-bin-path
python3 scripts/evaluate-visit-times.py /absolute/path/to/visit-time-eval /tmp/c67-timing-cases
~~~

The --timing-ui flag opens this screen with isolated history and actual dated facts. The --timing-smoke flag also runs a fixed GBK/rain-preference brief through actual providers and prints JSON markers. Neither substitutes a fabricated weather response. No commit, push, publication or routing change was performed.
