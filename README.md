# C67

The separate [PoC journey](poc-journey/README.md) contains the itinerary/routing/weather/Foundation Models/embeddings experiments and [teammate handoff](poc-journey/HANDOFF.md). Its apps and evidence are isolated from the production implementation described below.

C67 plans personal trips from the traveller's places, preferences and available time. AI recommends optional additions and a visit order using route, weather and venue context. The traveller reviews a proposal before saving it and can recalculate remaining visits during the trip.

**Repository implementation — 30 October 2026:** the default iOS flow is now Plan → review → My Trips → start/arrive/extend/recalculate. It includes synthetic mock adapters, a separate Node/TypeScript Planning API and worker, Apple Maps/Weather and hosted-model adapters, a bounded public-site reader, OpenAPI 0.6 and an additive SQL migration. This batch is local code, not a shared deployment or live-provider acceptance. Read [implementation/evidence](docs/tasks/ai-trip-planning-implementation.md), [planning design](docs/ai-trip-planning.md) and [ADR-0009](docs/decisions/0009-personal-planning-implementation.md).

## Run the app

1. Open `ios-ui/C67.xcodeproj`, select **C67** and an iPhone Simulator, then Run.
2. In default mock mode, review the sample places, adjust durations/time/preferences and tap **Plan my trip**.
3. Review the synthetic proposal and **Save this trip**. In My Trips, start, manually confirm arrival, extend/finish a visit and recalculate.

Mock mode uses no AI or weather providers; trips remain in memory until the app closes. Place search and requesting current location use Apple platform services only when invoked. The legacy catalog example remains available with the launch argument `--legacy-catalog`.

Live planning requires a configured HTTPS Planning API, the new SQL migration, backend provider credentials and traveller sign-in. Existing Supabase/Auth deployment does not deploy this new service. See [planning setup](server/planning/README.md) and [getting started](docs/getting-started.md). Missing planning configuration leaves Account usable and reports an explicit planning error.

| Area | Responsibility | Entry point |
|---|---|---|
| `ios-ui/` | SwiftUI/VIPER planning, MapKit search, requested location and Account | [UI guide](ios-ui/README.md) |
| `ios-backend/` | Domain models/protocols, mock/live repositories and session handling | [Client guide](ios-backend/README.md) |
| `server/planning/` | Planning HTTP API/worker, scheduler, model and data adapters | [Planning guide](server/planning/README.md) |
| `server/supabase/` | One additive migration history, RPCs, jobs, receipts and RLS | [Server guide](server/README.md) |
| `contracts/` | Authoritative wire contract and synthetic fixtures | [Contract guide](contracts/README.md) |
| `docs/` | Product context, decisions, setup and verification | [Team handoff](docs/team-starter.md) |

Existing creator/version trips, graph, planned edits, private journal/media and authentication retain their contracts. Personal planning has its own aggregate and does not bypass journal guards or invent creator IDs. Native email/password and Sign in with Apple retain their separately recorded [Auth/API](docs/tasks/ios-auth-api.md) and [Apple](docs/tasks/apple-auth.md) evidence; device lifecycle acceptance remains separate.

For team work, start with [AGENTS.md](AGENTS.md), [architecture](docs/architecture.md), [coding conventions](docs/coding-conventions.md) and the [AI workflow](docs/ai/workflow.md). Synthetic integration success does not establish travel accuracy, product validation or production readiness.

## Standalone native AI experiment

[TripSense POC](tripsense-poc/README.md) is an isolated iOS 26+ Foundation Models/MapKit experiment with a separate Xcode project. Its [feasibility report](tripsense-poc/FEASIBILITY.md) separates actual Mac tool-call/routing evidence, synthetic tests and pending physical-iPhone acceptance. It does not replace the C67 app or change shared backend behavior.
