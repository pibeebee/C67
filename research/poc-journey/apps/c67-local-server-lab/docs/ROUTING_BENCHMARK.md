# Routing access benchmark

This development experiment starts from `main` `0a06e1d`. It is a CLI/engine benchmark, independent of ContextHarness editor state and the production C67 app. The editor's live in-session-only persistence policy remains unchanged.

## What is compared

| Variant | Endpoint | Provider |
| --- | --- | --- |
| `apple_pin` | Independently confirmed Apple pin supplied in the manifest | Existing Apple REST ETA pacing; directions for geometry probes |
| `apple_access` | Fresh, public, mode-specific independent access point | Apple REST |
| `google_place_id` | Explicit or conservatively resolved Google Place ID | Google Routes, `TRAFFIC_AWARE` for driving |
| `valhalla_access` | Same independent access selection as Apple access | Local pinned Valhalla/OSM graph, static speeds |

An OSM POI center is not an entrance. A valid access entry needs a source URL, check date, mode, kind, public-access evidence and `sourceSupported` status. The selector rejects unverified, private, stale and mode-incompatible points. A source-supported point is still not field validation. Dataset `reference` is separate from selection; using the same source is labelled consistency only. Distance to a reference never certifies a connected public path through a fence, mall or station.

The sample manifest contains sourced cafe display points for eight Jakarta areas. It intentionally has no invented Apple pins, Google IDs or public entrances. Populate independent access evidence before interpreting the four-way campaign as an access comparison. Google resolution requires an exact normalized name and proximity within 150 m of the independent source; ambiguity remains unresolved. This is a conservative identity check, not door verification.

## Commands

Run from the repository root. Every output directory must be new; existing evidence is never overwritten by the CLI.

```sh
rtk proxy swift run -j 4 -Xswiftc -parse-as-library --package-path poc-journey/apps/c67-local-server-lab routing-bench preflight
rtk proxy swift run -j 4 -Xswiftc -parse-as-library --package-path poc-journey/apps/c67-local-server-lab routing-bench synthetic poc-journey/.verification/routing-demo-01
rtk proxy python3 poc-journey/scripts/audit_routing_benchmark.py poc-journey/.verification/routing-demo-01/observations.json --output poc-journey/.verification/routing-demo-01/summary.json
```

The synthetic campaign repeats three times: 16 synthetic venues × two modes × two approach directions × four variants, 1/3/6-stop optimized/fixed itinerary pairs, six edit operations, shared-TJ direct/transfer/direction and itinerary controls, plus a directed-road adversarial prior. All providers in this campaign are explicitly synthetic. CPU runtime is not API latency, nor a provider speed ranking.

Live commands use process environment only; never put keys on the command line. **Google live is excluded from the current MVP/campaign at the user's request because it is paid.** It is disabled by default even if a key is present; fixture tests remain free. A separately authorized future campaign would need both `ROUTING_GOOGLE_LIVE=1` and `GOOGLE_ROUTES_API_KEY` with Routes/Places access. Apple requires `APPLE_TEAM_ID`, `MAPS_KEY_ID`, `MAPS_KEY_PATH`; no WeatherKit calls are made. `VALHALLA_BASE_URL` must be an HTTP loopback URL such as `http://127.0.0.1:8002`. Missing configuration/access becomes an observation, not a fabricated fallback.

The live itinerary phase currently obtains real visit context through the existing Google Places contract. Disabling paid acquisition therefore also leaves that phase unexecuted until independently sourced visit snapshots are supplied through a future adapter. The local OSM road probe and synthetic context/TJ campaign work without Google. This task does not remove the pre-existing Google Places dependency from the recommendation app.

```sh
rtk proxy swift run -j 4 -Xswiftc -parse-as-library --package-path poc-journey/apps/c67-local-server-lab routing-bench live poc-journey/apps/c67-local-server-lab/fixtures/routing/jakarta-venues.json poc-journey/.verification/routing-live-01
rtk proxy env VALHALLA_BASE_URL=http://127.0.0.1:8002 swift run -j 4 -Xswiftc -parse-as-library --package-path poc-journey/apps/c67-local-server-lab routing-bench local-probe poc-journey/apps/c67-local-server-lab/fixtures/routing/jakarta-venues.json poc-journey/.verification/routing-local-01
```

`local-probe` deliberately measures routes between adjacent sourced OSM POIs. It does not bypass the entrance selector in the main campaign and is labelled `valhalla_poi_probe`, with no access correctness claim. An HTTP network failure is not a successful graph calculation.

## Local graph setup

Use the dedicated `c67-routing` Colima profile; leave the default profile intact. The runtime manifest pins the official container digest and recorded engine version. Download the dated Geofabrik Java PBF from that manifest, verify its published checksum, then extract locally. The extraction helper requires `osmium==4.2.0` in a private virtual environment; a Python 3.14 wheel was used locally. No model/feed files are silently refreshed.

```sh
rtk proxy colima start --profile c67-routing --cpu 4 --memory 6 --disk 20
rtk proxy /path/to/private-osm-env/bin/python poc-journey/scripts/prepare_routing_osm.py /path/to/java.osm.pbf poc-journey/.verification/routing-graph-01 --manifest poc-journey/.verification/routing-venues-01.json
rtk proxy python3 poc-journey/scripts/routing_valhalla.py start --graph poc-journey/.verification/routing-graph-01
rtk proxy python3 poc-journey/scripts/routing_valhalla.py status
rtk proxy python3 poc-journey/scripts/routing_valhalla.py stop
```

The helper binds only `127.0.0.1:8002`, refuses to replace an existing container, and disables unrelated elevation/admin/timezone downloads. This graph is a static-speed experiment, not traffic-aware ETA validation. Nodes, fully retained ways and complete turn restrictions are extracted within documented bounds; boundary-crossing ways are omitted. Test routes must stay away from the cut boundary. Graph preparation/cold start is measured separately from route queries. OSM attribution and ODbL apply; binaries, PBFs, graph tiles and private configuration stay ignored.

## Planning, limits and evidence

- Baseline uses the existing bounded optional/beam planner. Finalists rank up to 720 local permutations, evaluate at most three orders and retain at most two slot states. All candidate validation uses the shared context planner; reduced search can miss better schedules.
- Fixed input order remains fixed. Optional stops may be omitted only as subsequences. Every returned leg, including return, uses its actual requested departure. Matrix values are only search priors; missing cells are never zero.
- Google acquisition, failed requests, routes and matrix share a pre-dispatch cap of **200 requests / 1,000 matrix elements** per invocation. Auth/quota errors are not retried. A campaign stopped by the cap is incomplete, not a routing failure rate. Do not rerun paid campaigns merely to exhaust another budget.
- TJ uses the public shared facade with existing feed/calendar/freshness/access/direct/one-transfer rules. Google/Valhalla walking provenance is explicitly allowed; unknown providers remain invalid. No car fallback is added. Platform coordinate routing still does not prove station-door or crossing access.
- Provider results and snapshots remain in memory. The typed export contains timings, counts and invariant/status metadata; geometry, addresses, reviews, tokens and raw API payloads have no export path. Detailed itinerary quality fields are synthetic-only. Google geometry is not drawn on MapKit. This narrowly scoped design is not a certification of all pre-existing provider uses elsewhere in the app.
- The auditor excludes missing prerequisites from successful-query timing, retains them in outcome denominators, rejects unknown export fields and rejects candidate hard-rule violations. Report sample sizes alongside p50/p95. A faster synthetic run cannot establish field ETA accuracy or entrance correctness.

## Primary references

- [Google waypoint identity and access](https://developers.google.com/maps/documentation/routes/specify_location), [Places entrances](https://developers.google.com/maps/documentation/places/web-service/place-details), [traffic/latency](https://developers.google.com/maps/documentation/routes/config_trade_offs-rm), [display/storage policies](https://developers.google.com/maps/documentation/routes/policies).
- [Apple ETA](https://developer.apple.com/documentation/applemapsserverapi/-v1-etas) and [directions](https://developer.apple.com/documentation/applemapsserverapi/-v1-directions).
- [Valhalla route inputs/results](https://valhalla.github.io/valhalla/api/route/api-reference/), [official container](https://github.com/valhalla/valhalla/blob/master/docker/README.md), [Geofabrik Java](https://download.geofabrik.de/asia/indonesia/java.html), [OSM entrances](https://wiki.openstreetmap.org/wiki/Key:entrance).

See the [execution report](ROUTING_BENCHMARK_RESULTS_2026-11-10.md) for measured outcomes and open prerequisites.

## Matched native Apple versus Valhalla live campaign

The [2026-11-10 live comparison](APPLE_VALHALLA_LIVE_RESULTS_2026-11-10.md) is a separate matched-coordinate experiment. Native `MKDirections` works without the missing Apple REST credentials and is labelled `apple_mapkit_live`. Google remains excluded. This mode compares sourced POI points directly and makes no verified-entrance claim.

After starting the pinned local graph, run these manually on macOS with network access, each with a new output directory:

```sh
rtk proxy swift run -j 4 -Xswiftc -parse-as-library --package-path poc-journey/apps/c67-local-server-lab routing-bench paired-smoke poc-journey/apps/c67-local-server-lab/fixtures/routing/jakarta-venues.json poc-journey/.verification/matched-smoke-01
rtk proxy swift run -j 4 -Xswiftc -parse-as-library --package-path poc-journey/apps/c67-local-server-lab routing-bench paired-live poc-journey/apps/c67-local-server-lab/fixtures/routing/jakarta-venues.json poc-journey/.verification/matched-roads-01
rtk proxy python3 poc-journey/scripts/audit_matched_routing.py poc-journey/.verification/matched-roads-01/paired-observations.json --output poc-journey/.verification/matched-roads-01/summary.json
rtk proxy swift run -j 4 -Xswiftc -parse-as-library --package-path poc-journey/apps/c67-local-server-lab routing-bench controlled-live poc-journey/apps/c67-local-server-lab/fixtures/routing/jakarta-venues.json poc-journey/.verification/matched-controlled-01
rtk proxy swift run -j 4 -Xswiftc -parse-as-library --package-path poc-journey/apps/c67-local-server-lab routing-bench transit-live poc-journey/apps/c67-local-server-lab/fixtures/routing/jakarta-venues.json poc-journey/.verification/matched-transit-01
```

`paired-live` repeats forward/reverse road queries three times and alternates providers. Deliberate native request pacing is separate from service timing. Native calls have a 25-second callback deadline and 320-dispatch cap per invocation; do not bypass throttling by rerunning. Controlled itinerary commands use live route estimates with authored visit constraints, and shared TJ uses static GTFS with live walking. They do not acquire current opening hours/weather or run personalized recommendation/editor acceptance. The report distinguishes arithmetic-budget checks from complete schedules and provider estimates from field accuracy.
