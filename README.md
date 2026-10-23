# C67

An iOS starter for discovering creator travel rundowns, copying a version into a personal trip, and later documenting the journey as an album.

**Starter scope — 23 October 2026:** runnable SwiftUI/VIPER discovery → detail → personal trip in mock mode; a shared Swift package; an RPC contract; and a local Supabase migration, synthetic seed and access-policy tests. Journaling, photos, maps, weather, app sign-in and production deployment remain follow-up work.

For AI-assisted team work, start with [AGENTS.md](AGENTS.md) and the [shared workflow](docs/ai/workflow.md).

## Start here

1. Clone the repository and open `ios-ui/C67.xcodeproj` in Xcode 16 or later.
2. Select the **C67** scheme and an iPhone Simulator, then Run. Mock mode needs no credentials or server.
3. Open **Kota Tua Photo Walk**, choose a start time, and tap **Save as my trip**.

Mock trips exist in memory and disappear when the app closes. All displayed starter content is synthetic. This demonstrates software integration, not validated travel information or a completed CBL solution.

Read [Getting started](docs/getting-started.md) for detailed setup, [Architecture](docs/architecture.md) for boundaries, and [Contributing](docs/contributing.md) before opening a PR.

| Area | Responsibility | Entry point |
|---|---|---|
| `ios-ui/` | SwiftUI, VIPER, navigation and dependency wiring | [UI guide](ios-ui/README.md) |
| `ios-backend/` | On-device domain, repository protocols, mock and remote data | [Client guide](ios-backend/README.md) |
| `server/` | Supabase migrations, RPCs, authorization and future workers | [Server guide](server/README.md) |
| `contracts/` | Authoritative wire contract and synthetic fixtures | [Contract guide](contracts/README.md) |
| `docs/` | Context, decisions, onboarding and first assignments | [Team handoff](docs/team-starter.md) |

The existing self-hosted Supabase is the shared backend foundation. This starter adds **local development files only**; it does not deploy to or modify the homelab. Studio access for collaborators is separate from traveller authentication in the app.
