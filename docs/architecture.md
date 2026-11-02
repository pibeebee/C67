# Architecture boundaries

Updated 30 October 2026. [ADR-0009](decisions/0009-personal-planning-implementation.md) records the implemented personal-planning slice. The new service and migration are prepared in the repository; the existing homelab deployment does not yet include them.

## Dependency direction

```text
SwiftUI Planning/Account → Presenter → Interactor → C67Domain protocols
              ↑ app composition wires C67Data adapters
              │                  ↓ traveller session ticket
              │           HTTPPlanningRepository
              │                  ↓ HTTPS + JWT
              │           Node Planning API → owner-scoped Supabase RPCs
              │                                      ↓
              │                         durable private jobs / trip revisions / receipts
              │                                      ↑ leased service RPCs
              └──── proposals and events ← Planning worker
                                              ├─ hosted model API
                                              ├─ Apple Maps Server API / WeatherKit REST
                                              ├─ bounded public HTTPS text reader
                                              └─ deterministic schedule validation
```

`C67Domain` imports Foundation and owns personal inputs, proposals, jobs, trips, events and `PlanningRepository`. `C67Data` owns Codable DTOs, synthetic mock behavior, HTTP transport, one pending-command recovery record and existing Keychain-backed Auth/session handling. It sends traveller JWTs to the Planning API; model, Apple and service-role secrets stay server-only.

`Features/Planning` follows the native View/Presenter/Interactor/Assembly boundary. Views forward user actions; presentation owns main-actor state; platform helpers own MapKit search/directions and requested Core Location. Account remains the existing VIPER feature. `App/CompositionRoot` selects explicit mock/live adapters. Mock is labelled synthetic and memory-only; missing live planning configuration reports a visible error while Account remains available.

## Planning API, worker and storage

`server/planning` owns a separate dependency-free Node runtime; `server/package.json` still pins Supabase development tooling. HTTP handlers forward traveller tokens to owner RPCs. PostgreSQL verifies the session, ownership, request identity and current trip revision. They do not trust submitted owner IDs. The worker uses server-only service credentials with a renewable lease and performs external I/O outside database transactions.

The scheduler evaluates bounded orders, refreshes candidate-leg ETAs at candidate departure times and validates time arithmetic and destination preservation. The model proposes/selects/explains orders without writing rows or supplying unchecked travel times. Provider context carries source/check time; weather includes attribution. Unavailable route data fails explicitly, while missing weather/venue context is explained. Live mode never substitutes synthetic data.

The additive personal aggregate stores the accepted plan, immutable root input, revision, manual visit state and private event history. Jobs are durable, owner-bound and rate limited; receipts make apply/events idempotent. Active replanning derives only remaining visits, pins a confirmed current stop first, retains completed rows and requires a reviewed revision-bound apply. See [planning semantics and limits](ai-trip-planning.md) and [wire contract](../contracts/README.md).

## Existing catalog, graph and media boundaries

The old `RundownRepository`, Discovery example and creator root/version identities remain intact; launch `--legacy-catalog` to inspect that native example. Original creation, v2/v3 snapshots, graph, planned edits, private upload/session/worker/journal and album operations retain their wire meanings and data guards. Personal planning is not forced through invented creator IDs, and it does not bypass topology/time protection for journal-backed trips.

Earlier architectural decisions remain historical references: [trip identity](decisions/0003-trip-model-foundation.md), [graph](decisions/0004-trip-graph.md), [planned edit/media](decisions/0005-backend-mvp.md), [native sessions](decisions/0006-native-auth-session.md) and [AI direction](decisions/0008-ai-trip-planning-direction.md). The existing server batch is [shared-verified](homelab-backend-completion-verification.md); its evidence does not cover the new Planning service.

## Operational and verification boundaries

There is one additive SQL migration history in `server/supabase/migrations`. Local embedded PostgreSQL tests exercise the new migration with simulated Auth roles/claims and no shared data; they do not reproduce GoTrue, PostgREST, the matching-image Supabase stack or concurrent multi-connection locking. Full stack CI remains separate. Shared migrations, gateway exposure and container deployment require a concrete operational plan; no reset or incidental deployment is part of this implementation.

See [implementation evidence](tasks/ai-trip-planning-implementation.md) for backend tests, contract checks and build-only iOS verification. Real providers, signed-device behavior, end-user interactions and product evaluation remain acceptance layers, not conclusions from compilation or synthetic tests.
