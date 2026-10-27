# C67

An iOS starter for discovering creator travel rundowns, copying a version into a personal trip, and later documenting the journey as an album.

**Starter scope — 23 October 2026:** runnable SwiftUI/VIPER discovery → detail → personal trip in mock mode; a shared Swift package; an RPC contract; and Supabase migrations, synthetic seed, versioned destination-aware trip snapshots and access-policy tests. Journaling, photos, maps, weather, app sign-in and production deployment remain follow-up work.

For AI-assisted team work, start with [AGENTS.md](AGENTS.md) and the [shared workflow](docs/ai/workflow.md).

## Start here

1. Clone the repository and open `ios-ui/C67.xcodeproj` in Xcode 16 or later.
2. Select the **C67** scheme and an iPhone Simulator, then Run. Mock mode needs no credentials or server.
3. Open **Kota Tua Photo Walk**, choose a start time, and tap **Save as my trip**.

Mock trips exist in memory and disappear when the app closes. All displayed starter content is synthetic. This demonstrates software integration, not validated travel information or a completed CBL solution.

Read [Getting started](docs/getting-started.md) for detailed setup, [Architecture](docs/architecture.md) for boundaries, and [Contributing](docs/contributing.md) before opening a PR. Complete the relevant [onboarding checklist](docs/onboarding-checklist.md) and follow [coding conventions](docs/coding-conventions.md).

| Area | Responsibility | Entry point |
|---|---|---|
| `ios-ui/` | SwiftUI, VIPER, navigation and dependency wiring | [UI guide](ios-ui/README.md) |
| `ios-backend/` | On-device domain, repository protocols, mock and remote data | [Client guide](ios-backend/README.md) |
| `server/` | Supabase migrations, RPCs, authorization and future workers | [Server guide](server/README.md) |
| `contracts/` | Authoritative wire contract and synthetic fixtures | [Contract guide](contracts/README.md) |
| `docs/` | Context, decisions, onboarding and first assignments | [Team handoff](docs/team-starter.md) |

The existing self-hosted Supabase is the shared backend foundation. The server migrations and v1/v2 RPCs have been deployed and verified through explicitly approved backup/restore procedures; see [latest server evidence](docs/homelab-backend-completion-verification.md). Native app sign-in and V2 client integration remain follow-up work. Studio access for collaborators is separate from traveller authentication in the app.

Server completion evidence covers discovery, graph, planned edits/merge, private photo validation/journal/album and a restricted homelab worker. The native app remains the starter/mock integration until its data owner adopts those APIs; see [server handoff](docs/tasks/backend-completion.md).
