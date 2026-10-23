# Architecture boundaries

## Dependency direction

```text
SwiftUI View → Presenter → Interactor → RundownRepository protocol (C67Domain)
       navigation uses DiscoveryRoute             ↑
App composition root wires Mock / Supabase adapter (C67Data)
                                                  ↓
                        Supabase Data API → SQL RPC → PostgreSQL + RLS
```

- `C67Domain` owns entities and the repository interface. It imports Foundation, not UI or vendor SDKs.
- `C67Data` implements the interface with a memory-only actor and a URLSession RPC adapter.
- VIPER View, Interactor, Presenter, Router and Assembly live under `ios-ui/Features/Discovery/`. The starter keeps list/detail in one small feature; split the detail module when its behavior needs separate ownership.
- Entity comes from the shared Domain target. Presenter owns display state on the main actor. Router defines destinations; Assembly creates the feature.
- The app composition root selects mock/live. Only this wiring knows concrete adapters.
- Application/Platform are reserved folders. Add targets or shared use cases when needed; do not add a second wrapper around a single repository call solely to fill folders.

## First server slice

The accepted backend foundation is self-hosted Supabase. The repo provides local Supabase development configuration, SQL RPCs and a single migration history under `server/supabase/migrations/`. It adds no custom Node API server. `server/package.json` pins development tooling only.

The starter stores a published rundown version with ordered stops as a JSON snapshot. `create_trip` copies it into an owner-scoped trip in one database transaction. This intentionally small model does not implement the full proposed relational/PostGIS schema. Future normalized tables require migrations and contract compatibility checks.

RPCs use `contracts/api/openapi.json`. Published synthetic catalog reads are allowed to anonymous and authenticated clients for development. Production catalog/guest access and creator publishing remain product decisions. Trip writes are restricted to `create_trip`; its definer function uses a fixed empty search path and verified `auth.uid()`. Clients cannot submit `owner_id` or directly update tables.

Each create command includes a request UUID. A retry with the same owner, UUID, version and timestamp returns the original trip. Reusing that UUID for different input fails with HTTP 409. The UI retains a failed command's UUID in memory; durable offline recovery is not implemented yet.

## Runtime boundaries

Mock saving is memory-only. Live catalog loading is implemented. Live trip saving has an authenticated adapter and SQL contract, but no app sign-in flow. Auth/session refresh, local persistence, journaling/media, map routing, WeatherKit and background jobs are later slices. Studio collaborator access does not create traveller sessions.

Keep creator versions separate from personal trips. Keep suggested times, selected start times, forecasts and actual events separate. Server authorization remains authoritative even if the client validates input first.
