<div align="center">
  <img src="apps/ios/Resources/Brand.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="Travelant app icon">
  <h1>Travelant</h1>
  <p>Plan a day out around your interests, places, and available time.</p>
  <p><a href="#get-started">Get started</a> · <a href="#how-it-works">How it works</a> · <a href="#repository-map">Repository map</a> · <a href="#verification">Verification</a> · <a href="docs/README.md">Documentation</a></p>
</div>

Travelant is an Apple-first iOS trip planner. Choose interests, discover places, review visit availability, and save an itinerary you can adjust during your trip. The current beta focuses on South Jakarta and Kemayoran.

The repository is named **C67**. The app is named **Travelant**, and its on-device recommendation and scheduling core is **Pocket Engine**.

> [!NOTE]
> Travelant is a beta. Existing Simulator and provider checks are documented separately from physical-device testing and real-world recommendation quality. Start with the [verification record](docs/testing/verification.md).

## What you can do

- Choose from seven interest themes and refine them with 62 labels and supported conditions.
- Discover places through Apple MapKit and an independent OSM/Overture catalog.
- Review visit durations, opening/access evidence, preferred times, required stops, and the finish-by time.
- Generate a walking or driving itinerary using Apple route estimates and optional Apple Weather context.
- Let Luna Max choose among locally validated schedule options after you consent to AI processing.
- Review, reorder, save, and reopen trips on your device, then recalculate remaining visits when needed.

Missing hours, access information, weather, and route data remain visible in the planning flow. The [integration guide](docs/guides/pocket-engine-integration.md) explains the current constraints and data boundaries.

## Get started

### Requirements

- macOS with Xcode and an installed iPhone Simulator runtime. The app targets **iOS 18+**, uses Swift 6 language mode, and was most recently checked with Xcode 27.2.
- XcodeGen 2.44+ when editing the project specification.
- Python 3.11+ for repository checks. Node 22.18+ is needed for the earlier HTTP planning service.

```sh
git clone https://github.com/pibeebee/C67.git
cd C67
git switch dev
open apps/ios/C67.xcodeproj
```

Select the **C67** scheme and an iPhone Simulator. Choose a starting point on the Trip screen, tap **+ → Get Recommendations**, and complete the preferences. Review the selected places and visit availability before saving the itinerary.

The default mode is `pocket`. With no read token, discovery can use bundled independent records and Apple search. Catalog sync and optional Luna advice use the Pocket service. Enter the HTTPS URL and invited-beta read token in **Account → Pocket settings**. The token is stored in Keychain.

For isolated UI work, select explicit `mock` mode as described in [Getting started](docs/guides/getting-started.md). Its sample trips stay in memory.

### Pocket service

The maintained Python service lives in `server/pocket/src/`. It serves catalog evidence and constrained Luna advice. Configure its ignored environment file from `.env.example`, then follow the [server guide](server/pocket/README.md).

```sh
cp server/pocket/.env.example server/pocket/.env
# Fill the private tokens and provider settings before starting.
docker compose -f server/pocket/compose.yml up -d --build
```

For the homelab, use the [Cloudflare Tunnel deployment](server/deploy/pocket/README.md). Release builds require an explicit HTTPS host in ignored `apps/ios/Configuration/Production.local.xcconfig`.

> [!IMPORTANT]
> Provider API keys and write tokens stay on the server. Put only client-safe settings in Xcode configuration. Use the read token in Pocket settings, and keep real credentials out of Git and test fixtures.

## How it works

```text
SwiftUI / VIPER
    → C67Domain interfaces
    → C67Data adapters
    → Pocket Engine matching and schedule validation on device
        ├── Apple MapKit / WeatherKit
        └── Pocket server → independent catalog / optional Luna advice
```

Trips are saved on the device. The model receives bounded schedule options and returns a selection ID for local revalidation. The [architecture guide](docs/architecture/architecture.md) describes the current native path and the earlier HTTP planning mode.

## Repository map

| Directory | Contents |
| --- | --- |
| [`apps/ios/`](apps/ios/README.md) | Travelant app, XcodeGen specification, UI, assets, and app/UI tests |
| [`packages/C67Backend/`](packages/C67Backend/README.md) | On-device Domain/Data package and adapters |
| [`packages/PocketEngine/`](packages/PocketEngine/README.md) | Recommendation core, scheduling, taxonomy, and independent catalog resources |
| [`server/`](server/README.md) | Pocket service, earlier HTTP planner, Supabase, media worker, and deployment recipes |
| [`contracts/`](contracts/README.md) | Shared API specification and authoritative synthetic fixtures |
| [`research/`](research/README.md) | PoCs, model evaluations, source records, and historical evidence |
| [`design/`](design/README.md) | Branding sources and design exports |
| [`docs/`](docs/README.md) | Product, architecture, guides, operations, testing, and task records |
| `scripts/` / `tools/` | Repository checks and pinned tool manifests |

The [layout guide](docs/guides/repository-layout.md) maps earlier paths to their current locations. Imported experiment reports retain their original dates, hashes, and historical commands.

## Verification

Run from the repository root.

```sh
swift test --package-path packages/PocketEngine
swift test --package-path packages/C67Backend
python3 -m unittest discover -s server/pocket/tests
python3 -m venv .venv
.venv/bin/pip install -r scripts/requirements.txt
.venv/bin/python scripts/check_contracts.py
```

`bash scripts/verify_local.sh quick` runs the local feature checks. Use `ios-smoke` for app unit tests and two mock UI flows, or `ios-full` for the full mock app/UI suite. PoC verification has its own [entry point](research/README.md).

Work branches target **dev**. Automatic CI runs on **dev → main** promotion PRs. Broader regression and PoC workflows are manual. See [repository settings](docs/operations/repository-settings.md) and [coding conventions](docs/guides/coding-conventions.md).

## Explore the project

- [Product context and planning boundaries](docs/product/product-context.md)
- [Pocket configuration and local storage](docs/guides/pocket-engine-integration.md)
- [PoC and Apple-first transition index](research/poc-journey/docs/apple-first-transition-2026-11-12.md)
- [Live test evidence and beta handoff](docs/tasks/pocket-live-testflight-handoff.md)
- [Release and TestFlight procedure](docs/operations/testflight.md)
