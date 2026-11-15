# Reuse and provenance

The original routing checkout is `<LOCAL_HOME>/Programming/software/ios/poc-c67`. Ten `NativePlanner` source files are copied into the new local package; originals are not edited. `vendor-manifest.json` records original absolute paths and SHA256 values. Copies allow P3-specific provider injection without modifying the established planner.

- `NativeTripRoutingCore.swift`, the adaptive hybrid policy and the routing objective are retained.
- `NativeTripAppleServices.swift` adds explicitly injected forecasts, a replay ETA closure and a valid-visit-start hook. Injected forecasts bypass the legacy Jakarta Open-Meteo-only branch. The implicit old active-trip simulation branch is replaced by an explicit failure; P3 replay requires dependency injection.
- `NativeTripEngine.swift` asks the P3 visit hook for a full-stay-valid start after actual arrival. No valid start adds a conflict. The opening-source label describes imported evidence, not manual user input.
- During Xcode 27.2 compilation, the copied `NativeTripSearchSupport` async lookup callback needed explicit `@MainActor` isolation. This changes the adapter declaration, not the routing algorithm. The original file is untouched.
- The TransJakarta adapter adds an explicit Jakarta BRT marker, optional per-ETA journey evidence and walking-cache timestamp rebasing. Its injected provider handles walking and static-GTFS corridor-1 estimates. The routing objective and pure optimizer remain shared.
- The wrapper supplies separate P3 log storage, preserves real candidate validation and exports the original report shape. It adds Apple attribution to the report when available.
- P3 `PlaceResolver`, `WeatherCoordinator`, `Catalog`, `IntegrationPipeline` and `Storage` are new. They are **not** automatically validated by previous PoC results.

`PreferenceQuality` and `VisitTiming` are consumed as local sibling packages without edits. The new `quality.json` starts with P2's dated catalog and adds a Cikini reading card whose hash identifies the imported P1 structured fixture; it is explicitly not a hash of downloaded HTML. `timing.json` starts with P1's dated source data and adds official Baca Di Tebet and Erasmus Huis library hours. P3 source IDs use `q-` and `t-` prefixes so older preference and timing snapshots with the same source name and different check timestamps remain distinguishable. Original source IDs follow by removing that prefix; dates and URLs are preserved. IDs link candidate **areas** to venue service schedules; this is not a universal POI database. Missing café hours remain unknown.

The Jakarta operational polygon, source metadata and README are copied into `docs/data/jakarta-boundary`. Attribution: geoBoundaries IDN ADM1 derived from OpenStreetMap, ODbL-1.0; see copied provenance. A search rectangle is only a hint; selected coordinates must pass the polygon.

New hours reviewed from primary pages on 5 November 2026:

- [Baca Di Tebet](https://bacaditebet.id/): Monday closed, Tue–Thu 10:00–18:00, Fri 12:30–21:00, Sat 10:00–22:00, Sun 10:00–18:00 WIB. Library-wide publication; room reservations and café service are not established by these hours.
- [Erasmus Huis library](https://www.netherlandsandyou.nl/web/indonesia/erasmushuis/library): Tue–Sat 10:00–16:00; Monday, Sunday and public holidays closed. A public-holiday calendar has not been integrated, so exceptional closure remains an uncertainty rather than a guarantee of access.

The [research note](../../../docs/context/docs/research/low-compute-recommendation-approaches-2026-11-05.md) is preserved as research. Model2Vec, new encoders and other proposed retrieval replacements are not silently adopted in this integration.
