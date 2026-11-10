# Teammate handoff

PR #12 contributes [Journey Showcase](apps/c67-journey-showcase/README.md) with its required shared engine. The original production and Context Lab applications retain current main, as do the standalone Foundation Lab/Trip Integration diagnostic screens and UI tests. Read the [scoped repair task](docs/tasks/pr12-journey-fixes-2026-11-09.md) before applying older consolidation results to this revision.

## Latest entry point — Context Lab

Read [the 9 November handoff](docs/context-lab-handoff-2026-11-09.md) and [current CBL section 0I](docs/source-records/CBL.md). Context Lab v0.5 is the active experiment, using a local Mac service, Google Places, device E5 and OpenRouter. Follow its [app setup](apps/c67-local-server-lab/ContextHarness/README.md). The instructions below retain the earlier Trip Integration checkpoint.

## 1. Read the earlier native boundary

Start with [STATUS](STATUS.md) and [JOURNEY](JOURNEY.md). The native recommendation path no longer needs the team's OpenRouter/backend service. It still uses Apple's online Maps/Weather services for live data. Local E5 handles semantic ranking; native gates, sourced hours and the routing engine own factual/time constraints.

The current integrated flow is **pre-trip**. Earlier active-trip arrival/skip/replanning work lives in Native Routing Lab and has separate evidence. Neither implies that the full production C67 app already integrates these results.

## 2. Bootstrap and run deterministic checks

From the repository root:

```sh
python3 poc-journey/scripts/bootstrap.py
python3 poc-journey/scripts/verify_portability.py
bash poc-journey/scripts/verify.sh packages
bash poc-journey/scripts/verify.sh cli
bash poc-journey/scripts/verify.sh native
bash poc-journey/scripts/verify.sh build
```

Outputs go to a fresh ignored `.verification/` folder, not the preserved evidence. For UI replay, choose an installed iOS 26+ Simulator and pass its destination:

```sh
P3_SIMULATOR_DESTINATION='platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  bash poc-journey/scripts/verify.sh ui
P3_SIMULATOR_DESTINATION='platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  bash poc-journey/scripts/verify.sh native-ui
```

Fixtures are explicitly synthetic, even when the system Map loads real base-map tiles. The fixture path does not exercise real WeatherKit authentication or establish iPhone inference.

`native-ui` selects the planner portability regression only: confirmation, synthetic report navigation and rejection of invalid imported JSON. It uses the existing separate Jakarta UI-test storage and does not execute all retained legacy group/diary UI tests.

## 3. Open the app

Open `apps/c67-journey-showcase/C67JourneyShowcase.xcodeproj`, scheme `C67JourneyShowcase`, for the guided user flow. Trip Integration remains the shared engine and diagnostic application. The normal launch does not automatically call providers. Optional preferences can be skipped, but a skipped profile must be described as general rather than personalized. Review destinations and any ambiguous MapKit branch before calculating a route.

The following diagnostic launch flags belong to Trip Integration, not Showcase. Use `--p3-replay` only for the fixed synthetic scenario. Debug-only `--p3-live-eval` runs real provider/evaluation scenarios with **separate** storage under `Documents/P3LiveEval`; it does not modify the normal accepted itinerary. It keeps the screen awake while the evaluation screen is visible. Normal launch restores normal screen behavior.

## 4. Configure live signing and WeatherKit separately

The recorded build used Team `DP5XP7C2AM` and Bundle ID `giovanchristoffel.c67-trip-integration`. These identifiers are evidence, not credentials or a promise of access for the next developer. Use a team/App ID you can sign; override `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` locally without committing personal provisioning data.

Enable WeatherKit under both App Capabilities and App Services for the matching App ID, update provisioning, build/sign and install on the physical iPhone. Follow [Apple's native WeatherKit setup](https://developer.apple.com/help/account/services/weatherkit/). No REST JWT key is needed by this native `WeatherService` client. Start with the one-point diagnosis **without fallback**; Open-Meteo success is not Apple Weather authentication evidence.

The Foundation Models experiment additionally needs supported hardware, enabled/available Apple Intelligence, downloaded model and supported language. It uses English model inputs; unsupported/unavailable paths remain explicit. P3 E5 ranking is a different local runtime and must not be presented as Apple Foundation Models inference.

## 5. Understand data and proposals

- Jakarta/WIB, one day, maximum six destinations and return to the selected origin. Current Showcase supports car/taxi or TJ plus walking, with at most one transfer. Choose destination areas and required sourced spots before recommendation. Consult the current report for evidence limits; not every city/venue/service combination is covered.
- Every chosen destination remains; a missing fact or impossible deadline is a visible correction/conflict, not silent removal.
- Area-level preference claims cannot be borrowed from another room or branch. Cikini's English MapKit alias still requires the Cikini address.
- Published hours and full-stay entry/session rules are hard checks. Rain/daylight/sunset advice is contextual; the route does not promise every preferred window is globally optimized.
- Snapshot/source dates stay fixed. Recheck stale facts as a new dated catalog for a new live run; never shift historical fixture dates to hide expiry.
- Extra 30 minutes creates a new pre-trip proposal. Accept/reject/version guards preserve the accepted baseline. No automatic user-trip mutation is delegated to a model.

## 6. Continue with a bounded task

The next teammate should first reproduce the imported fixture checks, then choose one task: broaden sourced venue coverage, observe recommendation relevance/user effort, measure/request-budget routing performance, or integrate the earlier active-trip lifecycle. Record the selected task and new evidence before porting anything into production VIPER/domain/data modules.

The original three-place device run took approximately 29.5 seconds; the preference stage's first E5 call took approximately 0.78 seconds, with a later cache hit around 1.3 ms. Warm-cache latency is not new inference speed. Do not change the locked adaptive hybrid algorithm solely to improve a benchmark without a separate decision and validation.

## Historical inputs

The full [CBL source record](docs/source-records/CBL.md) preserves earlier decisions and later corrections. The [teammate's first Foundation Models report](docs/source-records/foundation-models-teammate-report.md) has result-file references that were not supplied beside it; those are gaps, not inferred successful runs. New explanatory documentation is English; archival inputs retain their language and attribution.

## Delivery and review

The handoff is published for review in [C67 PR #10](https://github.com/pibeebee/C67/pull/10), branch `gi/poc-journey-handoff`. The initial import commit is [0094e3a](https://github.com/pibeebee/C67/commit/0094e3a7061617733b43d79e824d1a5b74864291); subsequent delivery documentation and CI corrections, if any, are visible in the PR history. Follow the PR checks for the current CI outcome. No merge or deployment is part of this delivery.

## Current consolidated entry point — 9 November 2026

Start with [Showcase](apps/c67-journey-showcase/README.md) for Demo/Live mode selection, custom origins, area/spot preferences, map controls, TJ details, reviewed save/revision and exports. Use Trip Integration for engine changes and diagnostics, and the sibling Foundation Lab packages for preference and timing rules. Keep Native Routing Lab and CLI independently runnable.

The [consolidation report](docs/consolidation-report-2026-11-09.md) records this checkout's checks. Use the [evidence policy](evidence/README.md) when changing maintained imported source: historical publication hashes remain fixed, and functional changes require a reviewed development-ledger entry. Tests run offline fixtures unless a separate provider/device task explicitly says otherwise.

## Local Context Lab editor extension — 9 November 2026

The local feature branch adds pre-departure itinerary editing and the shared TJ engine to Context Lab. See the [editor task](docs/tasks/context-itinerary-editor.md), [app usage](apps/c67-local-server-lab/ContextHarness/README.md#itinerary-editor-and-transjakarta-local-development), and [new report](apps/c67-local-server-lab/docs/ITINERARY_EDITOR_RESULTS_2026-11-09.md). This is separate from the dated v0.5/provider evidence above.
