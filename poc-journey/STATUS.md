# Capability and verification status

Snapshot date: **5 November 2026**. These are technical experiments with bounded data. There has been no participant study demonstrating satisfaction or reduced input effort.

| Capability / project | Original evidence | Limit |
| --- | --- | --- |
| Deterministic CLI | Source, synthetic tests and recorded Google-provider experiments retained | Japan transit coverage was unsupported; provider credentials are optional, not configured by this import |
| Native adaptive hybrid routing | Benchmark, Jakarta fixture tests and Mac live validation; actual initial/dirty source snapshot retained | Bounded heuristic, not a global optimality proof |
| Local/active native replanning | P0/P1/P2A/P2B reports, local/fixture tests and Simulator observations | Distinct from the integrated app's pre-trip changes; physical trip reliability remains open |
| Standalone Weather Lab | Native/fixture evidence, initial auth failure, later user-reported success | User report is labeled separately from directly captured JSON; P3 has its own physical API proof |
| Foundation Models | Guided generation, locale/availability/fallback evidence and Mac/iPhone runs | English task scope; personal-fit quality and factual time discovery remain limited |
| Local preferences + MapKit/E5 | Native fact gates, live search and device inference | Ranking a bounded catalog is not a probability of satisfaction |
| Sourced visit timing | Published regular hours, session/entry rules, weather/solar context and extreme tests | Capacity, queues, holidays and venue conditions not guaranteed |
| Preference quality / E5 benefit | Category/BM25/E5 comparisons and repeated cases retained | Repetitions are correlated; NDCG 0.977 is not 97.7% personal accuracy |
| P3 integration v0.1 build 3 | **35/35 package, 2/2 Simulator UI, 7/7 scripted iPhone live cases** in the original location | iPhone 17 / iOS 27.0.1, Xcode 27.2; live 1–3 venues; pre-trip only |

## Relocation verification

This import changes location, public metadata and Swift layout. [Relocation results](evidence/relocation-verification.md) records checks actually run against these published copies. Historical pass counts are not automatically inherited by the import or by production C67.

The relocated copies passed 220 package tests, 55 CLI tests, 126 native fixture tests, 12 Simulator UI tests and three unsigned Simulator builds. No new physical-device or live-provider run is claimed by this handoff.

## Current development entry point

Use Trip Integration, with the sibling Foundation Lab packages unchanged in responsibility. Keep the native lab and CLI as independent experiments. The main C67 application's iOS 18/VIPER/backend architecture has not been replaced.

## Still open

Broader venue facts; held-out recommendation relevance; manual physical network interruption/background/input changes; four-to-six-place live scaling; iOS 26 runtime; RAM/energy; actual trip observations; and user-effort/benefit validation. [Missing records](docs/missing-evidence.md) are explicit.
