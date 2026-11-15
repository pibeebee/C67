# Task: Implement personal AI trip planning across C67

Status: Done — local repository implementation; not committed or shared-deployed
Owner: Giovan (requesting owner); Codex (implementation)
Branch: gi/ai-trip-planning
Updated: 30 October 2026

## Outcome and authorization

Giovan authorized end-to-end repository changes for the current AI trip-planning direction and delegated routine implementation decisions while away. He explicitly requested no iOS app tests; no Swift package, Simulator or device tests will be run for this task. Non-iOS verification remains in scope. Commit, push, paid provider calls and shared deployment are not required for this repository implementation.

## Bounded implementation decisions

- One-day plans, one to six user-selected destinations, explicit origin, visit durations, departure and finish-by instants and destination time zone. Finish-by means finishing the final visit, without an implicit return-home leg.
- AI recommendations are grounded in provider data. A bounded scheduler evaluates candidate orders, then the model selects/explains an evaluated candidate. No silent destination removal or automatic deadline extension.
- Optional AI place suggestions require user selection. Live mode never falls back to synthetic route/weather/model data.
- A new personal-planning aggregate preserves existing rundown/version APIs, fixtures, migrations and journal guards. Proposal application is owner/revision/request-bound and remains explicit.
- Native UI uses the existing VIPER/domain/data boundaries. The default mock flow is clearly synthetic and memory-only. Live HTTP configuration is explicit and server secrets remain server-only.
- Node/TypeScript planning API and worker, PostgreSQL durable jobs, an OpenAI-compatible hosted model adapter, Apple Maps/Weather adapters and a bounded read-only public-site research adapter. No browser dependency is installed on the iPhone.
- SQL migrations are prepared locally. No shared Supabase reset or deployment is authorized as an incidental check.

## Work sequence

1. Define authoritative schemas/fixtures and domain entities for inputs, jobs, proposals, personal plans and events.
2. Implement and test scheduler, source normalization, provider boundaries, job processing, HTTP behavior and mock failure cases.
3. Add additive SQL/RPCs for owner-scoped creation/reads, leased worker processing and atomic proposal/event commands.
4. Implement mock/live Swift adapters and native Planning/Active Trip screens, map search and location input; preserve Account and legacy catalog access.
5. Synchronize configuration, generated project, context, ADRs, setup and handoff.
6. Run contract/server checks, formatter/static checks and available isolated SQL checks. Record unavailable checks accurately. No iOS tests.

## Acceptance

- [x] New plans do not need a creator/version ID.
- [x] Optional candidates, initial planning, proposal review/apply, saved plans, start/visit/extend/replan work across the defined boundaries.
- [x] Unknown inputs/provider failure, infeasible schedules, stale results, retries and account transitions preserve user intent and ownership.
- [x] Existing wire contracts retain their meanings and existing protected data is not rewritten.
- [x] Provider credentials and deployment needs are documented without claiming live provider acceptance.
- [x] Non-iOS checks and precise iOS verification exclusions are recorded.

## Verification and handoff

The default iOS feature and composition root now use personal planning. Domain/Data own typed models, transport, mock behavior, session-ticket validation and pending-command recovery. The existing Discovery flow remains under `--legacy-catalog`; its smoke-test launch argument was updated but the test was not run. MapKit search/markers/directions and requested foreground location are wired. Date input displays the destination zone; stale proposals and account transitions cannot replace current private state. The bundled privacy manifest declares the new app-only UserDefaults use for pending-command recovery.

The separate planning API/worker implements bounded model/order/scheduler/provider/site steps and typed failures. OpenAPI 0.6 adds owner/worker/HTTP contracts and four synthetic fixtures, synchronized to Swift. The additive SQL migration adds independent owner trips, private jobs/events/receipts and service-only leases. Original paths/schemas/security entries remain semantically unchanged, and all 19 pre-existing tracked migrations/fixtures/seed files remain byte-identical.

| Verification on 30 October 2026 | Result / precise scope |
|---|---|
| Planning backend | `npm run check`, `npm run format:check` and `npm test`: 21/21 Node tests/subtests pass. Directed 48-minute matrix, preferred-window/deadline conflicts, six-stop bounds, cancellation, live-adapter stub/signing/attribution, foreign reads, retries and active replan are covered. No real provider HTTP calls. |
| New migration | Executed on disposable PGlite PostgreSQL 18.6 with simulated Auth roles/claims. Six lifecycle/authorization subtests cover owner isolation, denied direct/worker writes, changed-input identity, equivalent UUID/time/optional re-encoding, leases, invalid arithmetic, single apply, arrival/extension/stale results and completed-history preservation. No homelab mutation or shared data used. |
| Shared Swift package | `swift build --package-path packages/C67Backend`: pass. Build only; no package tests. |
| Native app | Generic iOS Simulator-target `xcodebuild ... CODE_SIGNING_ALLOWED=NO C67_DATA_MODE=mock build`: pass with Xcode 27.1. Only the existing no-AppIntents metadata warning. No Simulator launched, UI interaction/device walkthrough or iOS test executed. |
| Swift layout | Pinned formatter applied and checked. |
| Contract/resources | OpenAPI validation, fixture schemas, exact bundled copies and unchanged original synthetic SQL seed pass. Python scripts compile. |
| Configuration/context | XcodeGen project regenerated; Info.plist and workflow/project/Compose YAML parse. `docker compose ... config --quiet` passes with a null test env file. Local Markdown links and old-contract/data compatibility checks pass. |
| Diff hygiene | Whitespace and tracked/untracked-file review; no credentials, generated build output or operational env included. |

Full Supabase pgTAP/lint/Auth HTTP suites, matching-image PostgreSQL 17, new Docker image/runtime and real provider requests were not run. Local Docker daemon is unavailable; no substitute shared reset/deployment was attempted. New GitHub CI configuration is prepared, not observed as run. The explicit iOS-test exclusion was honored.

## Handoff

- Open `apps/ios/C67.xcodeproj` in mock mode for the new default flow. Synthetic trips last only for the app session.
- Use [planning setup](../../server/planning/README.md), [ADR-0009](../architecture/decisions/0009-personal-planning-implementation.md), [planning semantics](../architecture/ai-trip-planning.md) and [team handoff](../guides/team-starter.md) for the implementation and next acceptance layers.
- New shared migration/service/gateway deployment needs a concrete matching-image recovery/operational scope. Existing deployed Auth/server/media evidence remains separate.
- Live use needs private Apple/Maps/Weather and model credentials plus an explicit model, provider capability/attribution/data-sharing/storage review and measured cost/quality. No paid model selected or credentials configured.
- Personal journal/album integration, destination editing within an existing trip, skip/partial completion, undo, background/automatic recalculation, multi-day/transit and production retention remain separately scoped work. No product differentiation, travel accuracy or field/device readiness claim follows from synthetic checks.
- Changes are on `gi/ai-trip-planning`; no commit, push, PR, merge or deployment was performed.
