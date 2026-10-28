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

The accepted backend foundation is self-hosted Supabase. The repo provides optional local Supabase configuration, SQL RPCs and a single migration history under `server/supabase/migrations/`. It adds no custom Node API server. `server/package.json` pins development tooling only.

The starter stores a published rundown version with ordered stops as a JSON snapshot. `create_trip` copies it into an owner-scoped trip in one database transaction. This intentionally small model does not implement the full proposed relational/PostGIS schema. Future normalized tables require migrations and contract compatibility checks.

RPCs use `contracts/api/openapi.json`. Published synthetic catalog reads are allowed to anonymous and authenticated clients for development. Production catalog/guest access and creator publishing remain product decisions. Trip writes use versioned creation and explicit preview/apply commands with owner checks, fixed empty search paths and revision/receipt boundaries. Clients cannot submit `owner_id` or directly update tables.

Each create command includes a request UUID. A retry with the same owner, UUID, version and timestamp returns the original trip. Reusing that UUID for different input fails with HTTP 409. The UI retains a failed command's UUID in memory; durable offline recovery is not implemented yet.

## Runtime boundaries

Shared development uses the homelab; SQL reset/mutation tests use an isolated homelab target. Mac Docker is optional. The starter is deployed and verified; see [homelab evidence](homelab-verification.md).

Mock saving is memory-only. Live catalog loading and authenticated trip saving use the composition
root's session provider. The Account VIPER feature supports email/password login, registration/confirmation and recovery/reset with PKCE callbacks.
Data owns Keychain persistence, single shared refresh, expiry/rejection, and local-scope logout;
Domain exposes account identity, session-change snapshots and an authentication interface. Private response tickets reject results after login transitions. Auth and RPC share URL validation
and transport coding. Search, owner trip pages and graph DTOs are available to later features;
My Trips/search UI, graph create/edit commands, local trip persistence, native journaling/media,
routing and WeatherKit integration remain later slices. See [Auth/API evidence](tasks/ios-auth-api.md). Server-side private media validation runs in the documented worker. Studio collaborator access does not create traveller sessions.

Keep creator versions separate from personal trips. Keep suggested times, selected start times, forecasts and actual events separate. Server authorization remains authoritative even if the client validates input first.

## Trip model stage 3A

[ADR-0003](decisions/0003-trip-model-foundation.md) adds curated root/version identity, explicit destination zone/date and a server revision behind two new RPCs. The original payloads remain unchanged. The migration is additive; shared deployment is tracked separately. Ordered stop JSON remains until the next stop/leg slice can represent origin, landing and first stop explicitly. No client edit/concurrency/lifecycle policy is enabled by this metadata foundation.

## Trip graph stage 3B

[ADR-0004](decisions/0004-trip-graph.md) normalizes owner source/day/stop/leg rows behind three opt-in endpoints. Seven existing RPC shapes remain compatible. Explicit access/landing_to_first/between_stops edges preserve separate origin/landing/first-stop semantics. Unknown route facts remain null with warnings, and immutable graph guards prevent independent child/root drift. Initial graph creation is one source/day 0; full scheduling, edits/receipts and multi-day/multi-source commands are subsequent work. CI evidence and the unexecuted shared deployment plan are tracked in the [task](tasks/trip-graph.md).

## Consolidated backend completion

[ADR-0005](decisions/0005-backend-mvp.md) adds bounded discovery, immutable private command receipts, revision-checked preview/apply planned edits and explicit source-overlap choices, plus a private session/Storage/worker/journal/album path. The worker performs byte IO outside database locks; only its leased service command accepts journals. Pending/accepted journal plans protect topology and time. Creation receipts remain stable after edits/journals; old RPC wire shapes stay compatible.

Source code and disposable CI evidence are separate from shared deployment. PR #4 is closed by user request. The [completion task](tasks/backend-completion.md) requires one review PR only after the full agreed backend batch is verified; the [new combined homelab plan](homelab-backend-completion-plan.md) needs its own exact operational approval before four migrations/two buckets/new worker are applied.

The consolidated server batch is now [deployed and shared-verified](homelab-backend-completion-verification.md). This supersedes the earlier pending deployment notes for stages 3B–7; native integration and documented production/field boundaries remain separate.
