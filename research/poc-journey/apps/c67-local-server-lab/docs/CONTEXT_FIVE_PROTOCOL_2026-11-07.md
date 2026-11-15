# Five-destination context experiment — prospective protocol, 7 November 2026

User explicitly requested five destinations and autonomous decisions while away. Preserve actual brief: park afternoon, museums flexible, total waiting <=30 minutes. Additional destinations selected before provider calls: Museum Mandiri and Museum Sejarah Jakarta. Existing Museum Nasional/Museum BI/park dwell remain90/60/60 min; added museums60 min each, total330 min. Assumptions: tomorrow8 November2026 if run today, automobile, Hotel Indonesia Kempinski origin/return,09–19WIB. No shortening/skipping visits for speed.

## Comparisons and limits

1. New synthetic five-stop fixtures: seed671109,24 cases (12 development/12 holdout), six families, independent enumeration of120 orders and all admissible15-minute slots under30min wait. Same existing engine, no algorithm tuning. High-budget ablation plus policy caps24/48/96. Audit failures/unavailable/non-ready as such; no population accuracy.
2. Real independently searched Google/Apple identities, explicit alias/area gate, five fresh details with reviews held in memory only, WeatherKit park forecast and attribution. Shared snapshot across paired3/5 route jobs, same09–19 window and retained three-stop dwell. No E5/open-ended recommendation/UI claim.
3. Paired N3/N5: three repetitions each of firstFeasible/selectiveOrders/beam, alternate size/method order. N3cap24/N5cap64 actual new ETA calls per job. Same prior goals, wait cap, engine beam width12; no cross-job cache.
4. Two N5 diagnostics, elapsed and weather, cap24 each. If primary N5 misses candidates or best preferred-start penalty remains positive, one explicitly exploratory beam cap96 probe may use the same in-memory context. Preserve primary results; do not tune the algorithm from this probe.
5. One fresh-process five-stop firstFeasible pipeline, cap64, to measure actual discovery-to-result latency if the primary obtains a candidate. If not, retain failure and use remaining budget for diagnosis rather than claiming an itinerary time.

Total hard bounds for this new campaign:20 Google calls,1200 AppleHTTP calls,1000 ETA cells, no automatic provider retry. Primary caps max936cells including optional probe; fresh single<=64.25min wall timeout per command. Existing1.2sec ETA start pacing unchanged. Stop403/401/429 auth/quota; failed calls count. Place/weather freshness900sec may cause a late job to stop; retain it rather than relabeling it infeasible. No raw real Google review/details archive.

Starting account snapshot:5H34% used/66% remaining, weekly39% remaining. Read again at midpoint/end. These are shared account percentages, not elapsed hours. If5Hremaining<=25%, omit optional expansion and finish/checkpoint the required five-stop run/report. No new model, deployment, homelab or physical-device work.

## Accuracy and verification

Automatic checks: all requested stops exactly once; full dwell within returned sessions and requested bounds; exact leg departures, continuity and return; total waiting<=30min; deadline; preference penalties/unknown statuses; actual calls within caps. Python live auditor uses report-specific counts/dwell rather than hard-coded3 and retains non-ready outcomes. Negative controls must reject omitted stop, shortened dwell, wrong departure, wait and preference totals.

Published opening hours can conflict; sample official sources and distinguish Google consistency from real venue/admission verification. Operator pages inspected: https://museum.kemenbud.go.id/museum/profile/Museum%20Mandiri ; https://linktr.ee/MuseumMandiri ; https://www.mitramuseumjakarta.id/sejarah ; https://m.beritajakarta.id/read/144576/resmi-lima-museum-di-jakarta-buka-hingga-malam-setiap-akhir-pekan . Full details may remain unconfirmed; no fabricated last-entry rules.

Human acceptance of the earlier3-stop itinerary is not acceptance of a new5-stop plan. User is away; prepare the actual result for later review, no invented approval or preference change. Start-time15–16 remains an explicit soft proxy, not a hard interpretation of every afternoon experience.

Preserve previous reports/artifacts, before/after source hashes and66original hashes. Current context engine remains frozen; only harness/generator/auditor extended. Comparison to historical5-stop D/E is descriptive because venues, constraints, measurement path and date differ. Primary evidence is paired methods and3/5jobs in this campaign.

## Identity preflight amendment, before any ETA call

First attempt (`live/`) stopped after Apple returned parking and an unrelated access/transport-named candidate for Museum Mandiri.4AppleHTTP/2Google/0ETA. One Apple-only address probe used2HTTP and still did not identify the museum. Preserve that failure. Substitute **Museum Wayang**, same60-minute dwell, retaining five actual destinations; this is operator-selected under the user's autonomy instruction. Its official city museum group includes the same weekend policy: https://www.mitramuseumjakarta.id/wayang .

To retain the original20Google hard cap including failed preflight, primary recovery uses previously verified stable Google place IDs for Museum Nasional and Museum BI (2searches avoided), but fetches/validates fresh details for both. All Apple pins are freshly independently searched. New primary =3Google searches+5details=8; earlier2+recovery8+fresh-process10=20. The final fresh-process control still performs all5Google searches. No raw hours/reviews are reused. Seed IDs and provenance are recorded in `reuse-google-ids.json`. Engine/constraints unchanged.

## Final identity choice, still before any ETA call

Recovery with Museum Wayang also failed the area gate: Apple returned a same-named place in Tanjung Duren, far from the intended Kota Tua museum.4AppleHTTP/0Google/0ETA. Preserve `live-recovery/`. A sequential Apple-only five-query probe (6HTTP) resolved **Museum Seni Rupa dan Keramik** and **Jakarta History Museum** unambiguously in Kota Tua. Final additions are therefore **Museum Seni Rupa dan Keramik +Museum Sejarah Jakarta**,60min each. Use the verified English search queries; Google identities/details must independently agree with their area/name. No Google coordinates supplied to Apple. Earlier Mandiri/Wayang failures and16HTTP preflight cost count in final ledger. No additional Google calls beyond the original2 were consumed before the final campaign. Full museum-hour policy source: https://m.beritajakarta.id/read/144576/resmi-lima-museum-di-jakarta-buka-hingga-malam-setiap-akhir-pekan .

## Duplicate Google identity resolution, before ETA

`live-final/` stopped after2Google/5AppleHTTP/0ETA: Google returned multiple same-named History Museum pins. A single bounded Google search of “Museum Sejarah Jakarta” exposed the canonical **Taman FatahillahNo.1** record and other nearby duplicates/different addresses. Operator selected that address-supported record matching the independently searched Apple museum, rather than first-result selection. Narrow the History Museum identity gate to100m around that verified museum; other targets keep800m. This does not change any route cost/objective.

That same search also returned the canonical Fine Arts/Ceramics museum. Primary uses stable IDs from that probe plus the three earlier verified places, fetches all5details fresh and checks names/locations again. Total Google before primary=5, primary details=5, fresh-control5search+5details=10: still20. All failed attempts and the extra probe count in the ledger. The final5-stop setup is now explicitly operator-confirmed; no general discovery coverage claim.

## Prospective diagnostic branch after initial5-stop non-ready observations

Primary repeats and frozen search engine remain unchanged and will finish. If no primary5-stop candidate is found, replace the optional fresh-all-search run with bounded diagnostic(s) using the remaining10Google calls: pinned Google IDs +5fresh details each, Apple searches/ETA/WeatherKit fresh. First diagnostic preserves actual30min waiting, changes only harness beam width to1 and authored input order MuseumBI→Arts→History→National→Park, firstFeasible cap64. This tests whether slot branching/order explains the failure, not a retuned confirmed winner. Record per-edge actual ETA status/note in a bounded trace. If still non-ready and actual remaining campaign cells>=64, a second60min-wait diagnostic isolates sensitivity to the hard waiting limit. A60min result is a **counterfactual**, never a passing result for the user's30min constraint. Total Google still<=20 and actual campaign ETA<=1000; check ledger before each. No new engine changes and no claims from the original holdout about these exploratory settings.

The diagnostic pipeline includes fresh Apple named search and Google detail/WeatherKit enrichment but reuses Google IDs; do not call its timing full uncached Google named discovery. Instrumentation is confined to diagnostics. Primary executable/source before this extension is retained in `primary-source/`.
