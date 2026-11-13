# Five-destination context results — 7 November 2026

**Code validation update.** Subsequent review reproduced and corrected cache-budget pruning, partial-batch decoding and search-coverage/auditor defects. The figures below describe the original executions. [Validation findings and before/after evidence](BENCHMARK_CODE_VALIDATION_2026-11-07.md).

Actual user brief retained: park afternoon, museums flexible, total waiting <=30min. This is an autonomous five-stop extension; the user has not reviewed its itinerary.

Final places: Museum Nasional90min, Museum Bank Indonesia60min, Museum Seni Rupa dan Keramik60min, Museum Sejarah Jakarta60min, Lapangan Banteng60min. Tomorrow8 November,09–19WIB, automobile, same hotel origin/return. Total dwell330min; no destination or duration removed.

## Primary paired live comparison

Same engine as the three-stop pilot, shared fresh context, exact departure ETA, per-plan cache only. N3 is the original subset but now departs09:00; do not directly equate it with the earlier11:00 run. N3cap24/N5cap64, three repetitions each. The following processing medians include failed attempts; they are not successful itinerary latencies when ready=0.

| Stops | Strategy | Ready / attempts | Median attempt seconds | Actual ETA calls |
| --- | --- | ---: | ---: | --- |
|3|beam|3/3|22.79|[19, 19, 19]|
|3|firstFeasible|3/3|9.58|[8, 8, 8]|
|3|selectiveOrders|3/3|14.38|[12, 12, 12]|
|5|beam|0/3|70.84|[59, 59, 59]|
|5|firstFeasible|0/3|71.32|[59, 59, 60]|
|5|selectiveOrders|0/3|18.02|[15, 15, 15]|

No-candidate-within-search and incomplete-travel-data outcomes are retained. Neither proves the real trip globally infeasible. Some attempts encountered unavailable ETA evidence; unavailable co-occurrence alone does not establish the cause of every failed search.

## Bounded diagnostics

After primary failures, a declared exploratory diagnostic uses beamWidth1, geographically authored input order BI→Arts→History→National→Park and the same firstFeasible engine. It preserves the30min wait cap. If executed, a separate60min control is explicitly a counterfactual, not success for the actual user constraint. Google place IDs are pinned; Apple searches, five Google details and WeatherKit are fetched fresh. Timing is fresh-process with pinned Google IDs, not completely uncached Google text discovery.

### diagnostic30

Status: `incomplete_travel_data`; 0 stops, 59 ETA calls. Route processing70.09s; complete pipeline76.84s, discovery5.21s, enrichment1.52s. Wait cap30min, actual wait0.00min. Search parameters changed after observing primary results; no independent held-out superiority claim.

Diagnostic trace: 59 observations, 1 unavailable. Sanitized unavailable pairs/notes: [('park', 'gallery', 'The data couldn’t be read because it is missing.')]

### diagnostic60

Status: `candidate`; 5 stops, 6 ETA calls. Route processing6.47s; complete pipeline12.44s, discovery4.85s, enrichment1.12s. Wait cap60min, actual wait39.93min. Search parameters changed after observing primary results; no independent held-out superiority claim.

| Visit ID | Start–end WIB |
| --- | --- |
|gallery|09:30–10:30|
|arts|10:45–11:45|
|history|12:00–13:00|
|museum|13:30–15:00|
|park|15:15–16:15|

Return16:29; travel80.00min, waiting39.93min, dwell330min. Preferred-start penalty[0, 0, 0, 0].

Diagnostic trace: 6 observations, 0 unavailable. Sanitized unavailable pairs/notes: []

## Grid waiting finding

The successful60min counterfactual waits39.93min. Every individual wait is exactly rounding the observed arrival up to the next15-minute visit grid (5.62/12.72/8.08/6.82/6.70min). These are scheduling waits, not measured queues. This is a concrete candidate cause of excessive waiting. A finer/continuous grid would change departures and requires fresh ETA validation; it has not been tested live and is not asserted to satisfy30min. Calculation (original local evidence, omitted from this publication).

## Independent five-stop fixtures

24 new seeded fixtures,12 development/12 holdout, six families,120 possible orders with independently enumerated admissible slots, directed FIFO ETA and full waiting/dwell/session/return rules.180 actual policy outputs independently audited;4 corruption types rejected. Holdout has10 feasible and2 infeasible cases. These are authored stress controls, not representative Jakarta or human accuracy.

| Full-context policy | ETA cap | Returned /10 feasible | Preference gaps among returned | Exact model-score match /10 |
| --- | ---: | ---: | ---: | ---: |
|beam|24|1|0|0|
|beam|48|1|0|0|
|beam|96|9|2|1|
|beam|512|9|2|1|
|firstFeasible|24|7|2|0|
|firstFeasible|48|9|3|0|
|firstFeasible|96|9|3|0|
|selectiveOrders|24|6|2|0|
|selectiveOrders|48|6|2|0|
|selectiveOrders|96|6|2|0|

Even high-budget beam misses one feasible fixture and is not exact. Technical invariant tests do not establish search completeness, optimum, or user satisfaction. The three-stop high-budget score agreement does not generalize automatically to five stops.

## Identity and source limitations

Mandiri lookup returned parking/access-named candidates; Wayang lookup returned a same-named place in another district. Both were rejected before routing. Google History Museum search contained multiple nearby same-named pins; the selected canonical record has Taman FatahillahNo.1, matching the independent Apple museum. Area gate narrowed to100m for that museum. Failed searches remain in the ledger; no silent first-result selection or Google coordinates forwarded to Apple.

Primary recovery pins stable Google IDs and fetches fresh details, including all five current schedules. Google History Museum hours09–15 conflict with a city publication describing weekend09–20; planner uses the narrower returned window. No last-entry/ticket availability or physical admission claim. Park/indoor scopes and waiting/access weather uncertainty remain as in the earlier pilot.

Official sources inspected: [History museum](https://www.mitramuseumjakarta.id/sejarah), [city museum weekend policy](https://m.beritajakarta.id/read/144576/resmi-lima-museum-di-jakarta-buka-hingga-malam-setiap-akhir-pekan), [Mandiri identity](https://linktr.ee/MuseumMandiri). Source conflicts were not resolved by assuming a later closing time.

## Conclusion

No five-stop itinerary meeting the actual30min waiting constraint was found in this campaign. That is a limitation of the tested bounded policies/data/grid, not proof that the real trip is impossible. A five-stop candidate was found only under the exploratory60min cap, actually waiting39.93min, with6ETA calls; it is not a passing result for the actual brief. More search calls alone did not resolve the primary failures. Next investigation should test15min versus finer/continuous starts under the unchanged30min hard cap, with fresh exact-departure ETA, and improve order/slot candidate coverage. No further live experiment is started here.

## Evidence and reproduction

- [Prospective protocol and amendments](CONTEXT_FIVE_PROTOCOL_2026-11-07.md).
- Primary report (original local evidence, omitted from this publication), independent live audit (original local evidence, omitted from this publication).
- Independent fixture audit (original local evidence, omitted from this publication), reference (original local evidence, omitted from this publication).
- Verification and provider ledger (original local evidence, omitted from this publication).

Analysis of saved output needs no API calls. Use `python3 scripts/context-pilot-fixtures.py audit artifacts/context-five-2026-11-07` and `python3 scripts/audit-context-pilot-live.py artifacts/context-five-2026-11-07/live-resolved`. New live reproduction incurs provider calls and should use new directories/future dates. No production integration, homelab, simulator/iPhone installation, commit or publication.

## Live rerun after suspected connectivity issue

On 7 November at 14.31 WIB, the same five stops, trip date, geographic input order, search width of one, 15-minute grid, 64-call ETA cap and 30-minute waiting limit were tested in a fresh process. The run ended with `incomplete_travel_data` after 71.50 seconds of route processing. Apple returned usable ETAs for 55 of 59 exact queries. The earlier run returned 58 of the same 59. The earlier missing ETA recovered, and four different queries lacked usable ETAs in the rerun. ETA values agreed wherever both runs had a value. Comparison and control data (original local evidence, omitted from this publication).

A separate probe reissued the four unavailable requests and one working control. All five received HTTP 200. Three unavailable ETAs recovered. For Lapangan Banteng to Museum Sejarah Jakarta at 13.45 WIB, the HTTP 200 response contained destination and transport mode but omitted both distance and travel time. This identifies an incomplete provider response for that request. HTTP and schema observations (original local evidence, omitted from this publication).

The 60-minute control found the same five-stop candidate using six valid ETAs in 6.51 seconds of route processing. Its first four legs had the same ETA values as the 30-minute rerun and accumulated 33 minutes 14 seconds of waiting before the fourth visit. Total waiting was 39 minutes 56 seconds, entirely from rounding arrivals up to the next 15-minute start on this candidate. The control therefore exceeded the user's 30-minute cap even with all six ETAs available. The five-stop search at 30 minutes remained bounded. Audited control (original local evidence, omitted from this publication).
