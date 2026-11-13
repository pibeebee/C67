# TransJakarta API and data feasibility research

Research date — 6 November 2026, Asia/Jakarta

## Finding and recommended starting point

The verified operator source is a public **GTFS Schedule ZIP** with an explicit **CC BY 4.0** license. It contains the network and timing inputs needed to investigate a TransJakarta travel option. An application must supply journey planning and walking connections when consuming this feed directly. The operator's PPID download link resolves to the same file inspected in this research. [Operator publication and license](https://ppid.transjakarta.co.id/informasi/berkala) [Official download](https://gtfs.transjakarta.co.id/files/file_gtfs.zip)

For this POC, the recommended starting point is a bounded **TransJakarta BRT plus walking** experiment using the dated official feed and existing MapKit walking support. Keep headway-based wait assumptions visible when evaluating itinerary feasibility. Actual bus arrival prediction requires an additional verified realtime source. This recommendation is an engineering assessment based on the inspected data and the application's current capabilities.

## Source and API comparison

| Source | Capabilities | Access and cost observed | Verification and limitations |
| --- | --- | --- | --- |
| Official operator GTFS | Routes, stop hierarchy, trip patterns, stop times, service calendars, frequency windows, shapes and fares | ZIP downloaded with HTTP 200 without credentials. CC BY 4.0 | Contents inspected directly. Journey routing is application work. Realtime arrival prediction is unavailable from this static archive |
| API Indonesia | JSON route/stop lookup, nearest stops, fares and headways | `x-api-key`. Product page lists Rp2 per successful request | Documentation reviewed. An unauthenticated request returned HTTP 401. Full data responses and dataset refresh were not verified |
| RuangAPI | Visible route, stop and fare endpoints | `x-api-key`. Catalog lists free access and Rp5/request PAYG | HTTP 401 confirmed without a key. Catalog advertises six endpoints while three are displayed. Additional capabilities and plan details need confirmation |
| Google Routes API | Origin/destination transit routing, walking steps, transit details and mode preferences | Google Maps Platform key and billing configuration | Official documentation reviewed. Jakarta/TransJakarta route responses were not exercised. BUS preference can still return other transit modes, and the request schema has no operator selector |
| Community `open-tj` SDK | Documents application REST access and MQTT vehicle tracking | README describes JWT REST authentication and MQTT access | Explicitly unofficial. Realtime payloads, freshness, developer access terms, quotas and support were not verified against the operator |

Provider pages were checked on the research date. Source references are supplied at the end of the relevant paragraphs below.

### Official GTFS source

The PPID page explicitly publishes the schedule feed and its reuse license. Attribution should identify PT Transportasi Jakarta, link CC BY 4.0 and the source, and identify modifications when the dataset is transformed. [Operator publication](https://ppid.transjakarta.co.id/informasi/berkala) [License](https://creativecommons.org/licenses/by/4.0/)

### Documented REST providers

API Indonesia publishes seven TransJakarta endpoints under `https://use.apiindonesia.id`. The useful resources are `/api/v1/transjakarta/rute`, `/rute/:id`, `/halte`, `/halte/nearby`, `/halte/:id`, `/tarif` and `/jadwal`, with the shared TransJakarta prefix on each path. Its product page describes a normalized static dataset with shapes omitted. The documented stop grouping and missing per-trip timing interface need checking for pattern-sensitive routing. [API Indonesia product](https://apiindonesia.id/produk/transjakarta/) [API reference](https://docs.apiindonesia.id/#transjakarta)

RuangAPI publishes `https://api.ruangapi.id/v1/indonesia:transjakarta` with visible `/rute`, `/halte` and `/tarif` resources. Its catalog requires an API key and describes a one-hour cache. Authenticated content, dataset timestamp, request limits and the difference between advertised and displayed endpoint counts remain unverified. [RuangAPI catalog](https://ruangapi.id/api/indonesia/transjakarta)

Direct probes without API keys returned HTTP 401 JSON responses from both REST providers. This confirms an authentication boundary and endpoint response availability. Data accuracy and authenticated behavior still need verification.

### Realtime access

The searched official operator pages establish a public static feed. A documented public operator GTFS Realtime or developer REST contract for arrivals was not found in those sources. The community SDK describes REST and MQTT surfaces, including `tijeapi.transjakarta.co.id`, while explicitly declaring its unofficial status. Its documentation is a lead for a separate realtime investigation. SDK licensing does not establish operator data-access terms. [Community SDK documentation](https://github.com/BroNils/open-tj)

In the GTFS standard, `VehiclePosition` describes observed vehicle location and `TripUpdate` can carry predicted stop arrival/departure events. A vehicle coordinate alone leaves prediction work to the consumer. Frequency records with `exact_times=0` describe service headways rather than exact departures. [GTFS Schedule reference](https://gtfs.org/documentation/schedule/reference/#frequenciestxt) [GTFS Realtime reference](https://gtfs.org/documentation/realtime/reference/)

## Direct feed inspection

The following measurements describe the downloaded archive, as opposed to counts advertised in a third-party catalog.

| Measurement | Observed value |
| --- | --- |
| Retrieval UTC | 2026-11-06T06:44:35.882825+00:00 |
| HTTP status | 200 |
| HTTP Last-Modified | Fri, 30 Oct 2026 09:51:57 GMT |
| Download size | 2,498,913 bytes |
| SHA256 | `376b11f72ac30f9f4eb972ae32c7f1a3251b416dc3cd77cc573475a3b2676b9c` |
| Operator | PT Transportasi Jakarta, agency ID `Tije` |
| Time zone | `Asia/Jakarta` |
| Routes | 241 |
| Routes labeled BRT | 31 |
| Stop records | 8,139, including parent stations and platforms |
| Trip patterns | 694 |
| Stop-time records | 25,688 |
| Frequency records | 747 |
| Shape points | 244,302 |

The archive includes `agency.txt`, `routes.txt`, `stops.txt`, `trips.txt`, `stop_times.txt`, `calendar.txt`, `frequencies.txt`, `shapes.txt`, `transfers.txt`, fare tables and ticketing extensions. It contains neither `feed_info.txt` nor `calendar_dates.txt`. The HTTP modification header therefore serves as observed server metadata. It does not provide an operator feed version or an operational freshness guarantee.

Of the 747 frequency records, **746 have `exact_times=0`**. One Mikrotrans pattern has `exact_times=1`. Most feed timing must be interpreted as frequency-based operation. A headway must not be displayed as a verified countdown to a bus arrival. The reference schema and Context7 documentation were consulted to check this interpretation. [GTFS frequency specification](https://gtfs.org/documentation/schedule/reference/#frequenciestxt)

There are 8,139 stop records, with 7,805 explicit `location_type=0`, 274 parent stations and 60 blank types. Boarding platforms, parent stations and similarly named roadside stops require identity-aware grouping. Simple nearest-coordinate lookup still needs a walking access check.

The seven service calendars include two expired service IDs, `HJ` and `X`. Neither is referenced by an inspected trip pattern. Active trip patterns still need date/day filtering. Holiday-specific exceptions cannot be inferred from the absence of `calendar_dates.txt`. References from trips to routes and from stop times/frequencies to trips/stops had zero missing IDs in the checks performed. These checks are narrower than complete GTFS validation.

Route categories include BRT, Mikrotrans, Angkutan Umum Integrasi, Transjabodetabek, Rusun, Royaltrans and Bus Wisata. **31 BRT route records** does not imply 31 main corridors. A strict busway option should filter the observed service category in addition to the bus route type.

API Indonesia's documentation mentions 240 routes and 8,091 stops, whereas this operator archive contains 241 and 8,139 respectively. The examples may reflect an older snapshot. Authenticated responses and refresh metadata need checking before choosing the wrapper as the authoritative input.

## Applicability to Bundaran HI and Blok M

Route `1` is labeled **Blok M - Kota**, category **BRT**, operator **Tije**. The archive contains 18 trip patterns for that route, including short turns, loops and direction variants.

| Observed trip pattern | Relevant ordered stops | Service/frequency evidence |
| --- | --- | --- |
| `1-P96` | Blok M `P00017` at sequence 0, Bundaran HI Astra `G00034` at sequence 10 | `SH` daily calendar, 1,200-second headway, `exact_times=0` |
| `1-P97` | Bundaran HI Astra `G00031` at sequence 3, Blok M `P00017` at sequence 13 | `SH` daily calendar, 1,200-second headway, `exact_times=0` |
| `1-P28` | Blok M and Bundaran HI each occur more than once in the loop | Direction alone is insufficient to identify one ordered boarding/alighting pair |

These are candidate patterns for the first POC test. They establish that relevant ordered stops exist in the feed. The research did not perform a live bus journey, verify the next departure, measure station access or generate a door-to-door bus itinerary.

The current MapKit landmark pin for Bundaran HI and the GTFS boarding platform are distinct locations. The MRT Blok M center used for the venue catchment is also distinct from the TransJakarta Blok M stop. Walks must connect the actual origin, boarding point, alighting point and destination.

## Current application implications

The integrated request and Jakarta draft currently enforce automobile/on-demand-car planning. The vendored core contains `.transit`, but its adapter calls MapKit `calculateETA()` and does not establish TransJakarta operator, stop sequence or transfer details. The existing Native Routing Lab report recorded unavailable Jakarta transit requests. Apple's current Transit coverage list omits Indonesia. [Apple Transit coverage](https://www.apple.com/ios/feature-availability/#maps-transit) [Existing Jakarta routing evidence](../../native-routing-lab/docs/verification/JAKARTA_ROUTING_REPORT_2026-11-03.md)

A generic transit ETA cannot establish that a journey uses TransJakarta BRT. The future transport option needs operator/category identity, boarding and alighting stops, direction/pattern, walking legs, waiting assumptions and estimate provenance in the result.

For direct GTFS consumption, the minimum travel-time composition is access walking, estimated initial waiting, in-vehicle travel from ordered stop-time offsets, transfer walking/waiting when applicable and egress walking. Waiting uncertainty must be represented explicitly. The existing car ETA is insufficient input for these components.

If Google Routes is considered, request transit alternatives and inspect each returned step's vehicle and agency details before labeling it TransJakarta. Its documented transit preferences are advisory, and transit requests do not support intermediate waypoints. An itinerary would require time-dependent per-leg routing plus the application's sequencing logic. Google-provider response validation and billing remain an additional dependency. [Transit routing guide](https://developers.google.com/maps/documentation/routes/transit-route) [Transit preferences schema](https://developers.google.com/maps/documentation/routes/reference/rest/v2/TransitPreferences)

## Proposed next experiment

Start with strict TransJakarta BRT plus walking around the existing Bundaran HI/Blok M scenario. Use a dated operator-feed snapshot and verify one directed journey each way before adding transfers or comparing multiple itinerary orders.

The test should measure actual access walks, retain platform/direction identity, account for one initial wait per boarding, enforce service calendar/frequency windows, and export the timing assumptions used. Exercise repeated stops in loop patterns, reverse-direction boarding, service end, expired feed/calendar inputs, missing access paths and a deadline that becomes infeasible after waiting.

The resulting estimate should carry its source and uncertainty into proposal review, revision and acceptance. Candidate mode comparisons should evaluate the same departure time and complete travel duration. Human field observation is needed to assess waiting assumptions and itinerary usefulness.

The data-source choice is ready for a bounded static-data POC. A production realtime promise requires verified operator access, usable freshness/prediction metadata and field/provider acceptance. Transport-mode implementation and provider credentials are outside the completed research step.

## Evidence and limitations

Raw download metadata, ZIP, parsed route-1 sequences, reference checks and unauthenticated REST responses are stored under ignored `poc-journey/.verification/transjakarta-research-2026-11-06/`. The ZIP was inspected in place using Python's standard library. No dependency installation was required.

Context7 returned no relevant TransJakarta-specific library. Its official GTFS documentation index was used for the frequency/realtime semantics. Google Routes documentation was read directly from Google's developer site because the resolver did not return a matching Routes API collection.

Authenticated vendor data, third-party transit routing responses, realtime vehicle feeds, bus arrival predictions and physical access/journey observations remain unverified. Prices and service capabilities quoted here describe provider documentation observed on the research date.
