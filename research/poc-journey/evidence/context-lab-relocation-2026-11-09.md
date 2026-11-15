# Context Lab source export verification — 9 November 2026

The source export is based on C67 main commit `48d7139`, with the current workspace Context Lab v0.5 (5) added under `apps/c67-local-server-lab`. Earlier PoC folders retain their existing versions. Source copies follow the repository formatter. The model bytes were restored from the original machine's already-downloaded assets and verified against the immutable upstream manifest. SwiftPM checkout/artifact caches were reused for compilation.

## Checks executed on the exported copy

| Check | Result |
| --- | --- |
| Shared/model bootstrap checksum verification | Passed for Foundation Lab and Context Lab resource roots |
| Relative package resolution | Passed for the existing sibling PreferenceLearning, PreferenceQuality, VisitTiming and TripIntegration packages |
| Context Lab Swift package tests | 107 executed, 106 passed, one explicit opt-in benchmark skipped |
| Recommendation tests | 26 passed |
| PlannerLab tests | 34 passed and one benchmark skipped |
| PlaceContext tests | 25 passed |
| DynamicTrip tests | 8 passed |
| ContextPilot tests | 13 passed |
| XcodeGen | Generated the ContextHarness project from the exported spec |
| Unsigned iOS Simulator build | Passed using a private build-only connection resource |
| Repository SwiftFormat 0.64.1 | 0 of 332 Swift source files require formatting |
| Publication/link checks | Executed with the repository scripts after packaging |

The Xcode build emitted an existing deprecated Foundation Models initializer warning in the shared TripIntelligence package. No source behavior was changed to hide it.

The generic Simulator build used Xcode 27.2 on macOS with the installed SDK, without installing or running the exported app. Original v0.5 UI evidence comes from the recorded live Simulator campaign at the original location. This export did not invoke OpenRouter, Google Places, WeatherKit or live routing.

## Publication boundaries

The updated CBL source record is imported in Indonesian. Its previous 5 November publication is retained under a dated filename. Public links point at existing imported apps or retained context where possible. The [new publication inventory](context-lab-publication.json) records unavailable original evidence links, original SHA-256 and publication SHA-256. Missing raw artifacts are not reconstructed.

Reviewed screenshots and compact route/latency audits are included. Private environment files, connection resources, provider keys, model binaries, caches, derived data, raw provider archives and opaque xcresult bundles are ignored or omitted. The Xcode project is regenerated from the YAML source.

The legacy `freeze.py` command checks byte-identical original source manifests from the 6 November A/B/C campaign. The repository's formatted historical sources have different hashes, so that original-location freeze check is not a new reproduction protocol for this export. Follow the current ContextHarness setup and the package checks above; design a new explicit campaign before comparing routing methods.
