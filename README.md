<div align="center">
  <img src="apps/ios/Resources/Brand.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="Travelants app icon">
  <h1>Travelants</h1>
  <p>Build a day trip around the places you want to visit.</p>
  <p><a href="#get-started">Get started</a> · <a href="#how-it-works">How it works</a> · <a href="#run-the-checks">Run the checks</a> · <a href="docs/README.md">Documentation</a></p>
</div>

Travelants is an iPhone and iPad day-trip planner. Start from your current location or search for a starting point. Find nearby places by interest, or add places you already have in mind. Choose a main stop or let Travelants decide, then review and save your itinerary. During the trip, you can check which stop is next and open Apple Maps for directions.

Travelants can suggest the next day when there is too little time left today. When verified opening hours are unavailable, the planner uses place-category assumptions and marks estimated hours in the itinerary. Saved trips stay on the device.

## Get started

You need macOS and Xcode with an iOS Simulator runtime. The app targets **iOS 18 or later** and uses Swift 6. The 1.0 candidate was verified with Xcode 27.2.

```sh
git clone --branch dev https://github.com/pibeebee/C67.git
cd C67
open apps/ios/C67.xcodeproj
```

Select the **C67** scheme and an iPhone Simulator, then run. Debug defaults to `pocket`, which opens the on-device planner. For isolated UI work, copy [Development.example.xcconfig](apps/ios/Configuration/Development.example.xcconfig) to `Development.local.xcconfig` and set `C67_DATA_MODE = mock`. Mock mode uses synthetic data and keeps trips in memory.

Try a starting point of **Blok M MRT, Jakarta**. Choose **My Places**, add **Taman Bendera Pusaka**, leave **Let Travelants decide** selected, and generate an itinerary.

For a signed device or distribution build, start with [Production.example.xcconfig](apps/ios/Configuration/Production.example.xcconfig) and the [TestFlight guide](docs/operations/testflight.md). Release mode is `pocket-auth` and requires the configured HTTPS endpoints and a Supabase publishable client key.

> [!IMPORTANT]
> Keep local configuration overrides out of Git. Service-role keys, provider keys, and App Review passwords belong in private storage.

## How it works

- **SwiftUI** handles trip creation, itinerary review, saved trips, and progress. Feature modules use View, Presenter, Interactor, Router, and Assembly boundaries.
- **C67Domain, C67Data, and Pocket Engine** build and validate schedules on the device using visit durations, operating hours, and Apple Maps travel estimates. Apple Weather provides context where available. Travelants 1.0 calculates itineraries with external AI disabled.
- **Supabase Auth and Pocket** support Sign in with Apple, authenticated opening-hours checks, and permanent account deletion. Older planning and provider experiments remain available in the repository for development.

| Directory | What you’ll find |
| --- | --- |
| [`apps/ios`](apps/ios/README.md) | App, design assets, XcodeGen specification, and iOS tests |
| [`packages/C67Backend`](packages/C67Backend/README.md) | Swift domain models, authentication, and planning adapters |
| [`packages/PocketEngine`](packages/PocketEngine/README.md) | Recommendation and scheduling core |
| [`server`](server/README.md) | Pocket API, Supabase migrations, and earlier planning services |
| [`contracts`](contracts/README.md) | OpenAPI specification and synthetic fixtures |
| [`docs`](docs/README.md) · [`research`](research/README.md) · [`design`](design/README.md) | Engineering guides, experiments, and design sources |

For a local API setup, see the [Pocket server guide](server/pocket/README.md). For deployment and health checks, see the [deployment guide](server/deploy/pocket/README.md).

## Run the checks

From the repository root:

```sh
swift test --package-path packages/PocketEngine
swift test --package-path packages/C67Backend

python3 -m venv .venv
.venv/bin/python -m pip install -r scripts/requirements.txt -r server/pocket/requirements.txt
.venv/bin/python scripts/check_contracts.py
.venv/bin/python -m unittest discover -s server/pocket/tests
```

For app and UI tests, run `bash scripts/verify_local.sh ios-smoke` or use the **C67** scheme’s Test action. Use XcodeGen 2.44 or later to regenerate the project after editing `apps/ios/project.yml`. See the [verification record](docs/testing/verification.md) for Simulator, production API, and physical-device coverage.

[Travelants Support](https://travelants.giovanc.com/support/) · [Privacy Policy](https://travelants.giovanc.com/privacy-policy/)
