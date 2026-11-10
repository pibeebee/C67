# C67 PoC journey

This folder hands over itinerary, recommendation, routing and weather experiments, with six project roots, fixtures/tests/runners, dated reports and a public evidence inventory. The production C67 app remains a separate implementation.

**Start here:** choose the [Context Lab handoff](docs/context-lab-handoff-2026-11-09.md) for the Mac-local backend and dynamic context experiment, or [Journey Showcase](apps/c67-journey-showcase/README.md) for the guided TJ itinerary flow. See [status](STATUS.md) and the [experiment journey](JOURNEY.md) for their separate evidence.

| Project | Purpose | Entry point |
| --- | --- | --- |
| [Context Lab](apps/c67-local-server-lab/ContextHarness/README.md) | Dynamic Google discovery, E5, OpenRouter, hours/weather/ETA, sourced sunset and interactive map | `apps/c67-local-server-lab/ContextHarness/project.yml`, scheme `C67ContextLab` |
| [Journey Showcase](apps/c67-journey-showcase/README.md) | Guided create/review/save itinerary UI, TJ details, custom origins/areas/required spots and interactive road maps | `apps/c67-journey-showcase/C67JourneyShowcase.xcodeproj`, scheme `C67JourneyShowcase` |
| [Trip Integration](apps/c67-trip-integration/README.md) | Preferences → sourced visit timing → adaptive route → weather → reviewed proposal; pre-trip duration revision | `apps/c67-trip-integration/C67TripIntegration.xcodeproj`, scheme `C67TripIntegration` |
| [Foundation Lab](apps/c67-foundation-lab/README.md) | Five experiments: FM, Minat, Waktu, Cocok, E5; shared packages and Mac evaluators | `apps/c67-foundation-lab/C67FoundationLab.xcodeproj`, scheme `C67FoundationLab` |
| [Native Routing Lab](apps/native-routing-lab/README.md) | Adaptive hybrid routing, local storage, manual active-trip replanning, standalone Weather Lab and retained legacy screens | `apps/native-routing-lab/poc-c67.xcodeproj`, scheme `poc-c67` |
| [CLI experiments](apps/ai-trip-planner/README.md) | Hosted-AI/research history and later deterministic Google-provider CLI; optional credentials | `apps/ai-trip-planner/package.json` |

The main C67 app still targets iOS 18. These experimental apps/packages declare iOS/macOS 26 where required; original device evidence used iOS 27.0.1 and Xcode 27.2. Do not assume back-deployment or production integration.

## First checkout

Requirements: Python 3.11+, compatible macOS with Xcode 26.6+ (Swift 6.3+; checked with Xcode 26.6 and local 27.2), Node 24+ for the CLI. Apple Silicon is the verified architecture. SDK/compiler compatibility does not establish an iOS 26 runtime test.

```sh
python3 poc-journey/scripts/bootstrap.py
python3 poc-journey/scripts/verify_portability.py
bash poc-journey/scripts/verify.sh packages
```

Bootstrap restores the exact public E5 model/tokenizer by revision and checksum for Foundation Lab and copies the verified assets into Context Lab when present. About 135 MB is downloaded once; weights are not committed. It does not invoke a model, call MapKit/WeatherKit, configure credentials or change another application. See [third-party attribution](THIRD_PARTY.md).

## What is complete and what is missing

The handoff includes maintained source, tests, local package dependencies, protocol inputs, original reports, compacted build/test logs and safe structured provider evidence. [Evidence guide](evidence/README.md) describes redaction, exclusions and original versus published hashes. [Missing evidence](docs/missing-evidence.md) explicitly records unavailable external artifacts; no dummy results were created to fill gaps.

The historical original-location P3 run passed 35 package tests, two Simulator replay UI tests and seven scripted real-iPhone cases. Those numbers do not establish user benefit or a live run from this imported location. See [STATUS](STATUS.md) for the actual checks and remaining work.

## Journey Showcase capabilities

New Showcase trips use the combined sourced Jakarta catalog. Choose an origin, interests, destination areas and required catalog spots; review locations and calculate a one-day return itinerary. Car/taxi and the attributed TJ network with walking and at most one transfer share the existing audit and proposal lifecycle. Embedded/full-screen maps provide zoom and road/GTFS geometry. Demo and Live have separate storage and explicit provenance.

The scope and execution results are recorded in the [9 November consolidation report](docs/consolidation-report-2026-11-09.md). See [custom inputs](docs/tasks/journey-custom-origins-and-areas.md), [TJ results](apps/c67-trip-integration/docs/transjakarta/FINAL-REPORT-2026-11-06.md), and [evidence policy](evidence/README.md).

## Context Lab records

- [Full CBL source record, updated 9 November](docs/source-records/CBL.md)
- [Blind spots and their dated status](docs/source-records/BLINDSPOT.md)
- [Context Lab source/evidence publication inventory](evidence/context-lab-publication.json)
- [Source export verification](evidence/context-lab-relocation-2026-11-09.md)
