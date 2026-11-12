# From the earlier labs to Pocket Engine

The app switched to Apple-first discovery and routing with an independent place catalog. It reuses the 62-label taxonomy and bounded scheduling lessons. Google Places and the earlier 982-place dataset are not inputs to the new app or this acceptance run.

| Source or experiment | What it established | Repo location |
| --- | --- | --- |
| Itinerary, routing, weather and preference learning | Replays isolate feasibility and timing; route estimates are not measured journeys. | [Previous journey](../JOURNEY.md), [standalone TripSense](../../tripsense-poc/README.md) |
| Preference Lab | Compared category evidence, text, E5, and the earlier Jev labeling workflow. Historical Google adapters are preserved for code provenance; do not run the Google workflows. | [Source and reports](../apps/c67-preference-lab/README.md) |
| Independent venue collection | OSM/Overture coverage and enrichment explored with source-specific controls. The old parity run is historical evidence; raw Google data is excluded. | [Pilot](../apps/c67-open-venue-pilot/README.md), [aggregate parity report](../evidence/open-venue-pilot/google-parity-982-2026-11-11/REPORT.md) |
| Venue Context Lab | Compared Firecrawl and Playwright evidence retrieval. Evidence and source quality remain separate from ranking. | [Source and protocol](../apps/c67-venue-context-lab/README.md) |
| Isolated performance benchmark | Preserves the benchmark harness, protocol and report. Historical physical-device measurements are not evidence for this release. | [Performance report](../apps/c67-performance-benchmark/REPORT.md) |
| Pocket Engine Lab | Preserves the original standalone app, independent inputs, server, routing/solver benchmarks, and the synthetic Luna vs Foundation Models comparison. | [Lab](../apps/c67-pocket-engine-lab/README.md), [statistics](../apps/c67-pocket-engine-lab/docs/TEST_STATISTICS_2026-11-12.md) |
| Integrated Pocket Engine | The shipping app uses the maintained package and C67Data adapter. The stand-alone lab remains separate. | [Native integration](../../docs/pocket-engine-integration.md), [live acceptance](../../docs/tasks/pocket-live-testflight-handoff.md) |

The previously published planner, Foundation Models, local server, integrated app and native routing projects remain in place. Five additional project snapshots were imported here. [Original source checksums](../evidence/2026-11-12-source-snapshot.json) identify the selected inputs before formatting and removal of private endpoint details. Local data directories, tokens, real device dumps, raw provider responses, generated projects, model binaries and build outputs are excluded. Private historical references to excluded artifacts do not imply the files are available on GitHub.

For source-only reproduction, generate project files from their YAML with XcodeGen. Copy the example run configuration before generating either Preference Lab or Venue Context Lab. Restore verified public E5 assets with [the pinned bootstrap](../scripts/bootstrap.py) if needed. Endpoint placeholders must be replaced only in private local config; archived live Google and provider workflows are not a prerequisite for reproducing the Pocket pilot. Run the current native checks in the handoff for the product path.
