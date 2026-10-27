# Server

Supabase is the backend foundation. Local commands below use a separate disposable stack. The starter migration/seed, private trip reads and V2 model foundation have been applied to the shared homelab through explicitly approved procedures; see [foundation verification](../docs/homelab-verification.md) and [private read verification](../docs/homelab-trip-reads-verification.md). Local scripts do not deploy there automatically.

```text
server/
├── package.json / package-lock.json  # pinned Supabase CLI
├── scripts/test_local_api.py         # local Auth/API integration checks
├── supabase/
│   ├── config.toml                  # isolated local stack
│   ├── migrations/                  # single migration history
│   ├── seed.sql                     # synthetic catalog only
│   ├── tests/                       # pgTAP authorization and retry checks
│   └── functions/                   # future orchestration
├── src/modules/                     # reserved domain grouping, no API executable
├── workers/media/                   # private image worker (deployment approval required)
└── deploy/                          # reserved, no automatic deployment
```

Requirements: Node.js 22+, Python 3.11+ and a running Docker-compatible engine. From this directory run:

```sh
npm ci
npm run start
npm run db:reset
npm run db:test
npm run db:lint
npm run api:test
```

`db:reset` deletes and rebuilds the local development database. Use it only for disposable local data after checking the target and preserving anything needed. `api:test` does not reset the database. Stop your local stack with `npm run stop`; the CLI retains its local database volume for a later start.

The first migration defines curated `rundown_versions`, private `trips`, RLS, and `list_rundowns`, `get_rundown`, `create_trip` RPCs. Clients can read published synthetic versions; authenticated travellers can create and read only their own trips. Direct client table writes are revoked. No bucket or media upload policy is created before the journal/media scope is agreed.

Create new migrations through `npm run supabase -- migration new <name>`. Do not restore a second history under `database/`. Commit migration, contract, fixture and relevant tests together. Run the local database tests before requesting remote deployment.

## Local acceptance checks

- `db:test`: 167 pgTAP checks of grants, RLS, snapshot copying, retry behavior and private trip reads. Synthetic role/claim tests run in a rolled-back transaction.
- `db:lint`: checks the local public schema and exits nonzero for schema errors.
- `api:test`: 66 HTTP checks through Auth, the gateway and Data API. It signs up two unique synthetic accounts, performs password login and refresh, checks both directions of account isolation, tests denied direct writes and hidden drafts, sends four concurrent retries of one command, and verifies private list/detail pagination, cursor validation and persisted snapshots.

The HTTP suite reads keys from the pinned local CLI into memory. It accepts only project `c67-starter` at `http://127.0.0.1:54321`, ignores HTTP proxy settings, rejects redirects, and offers no remote URL option. Local email confirmation must be disabled as in the checked-in development config. No SMTP account, Studio password or hand-copied token is needed.

The suite expects the authoritative catalog fixture to match the local seed. It removes only its own temporary accounts, their trips and its temporary draft in `finally`, verifies cleanup, and fails if cleanup cannot be verified. It never prints or saves credentials or response bodies. Interrupted/killed processes can still leave synthetic records; inspect the local stack before deciding whether to reset it. Avoid running simultaneous copies against the same stack.

The local gateway allows anonymous access to the public synthetic catalog even without an API-key header. Trip authorization is verified using real traveller JWTs, grants and RLS. Client-key enforcement on a shared/production gateway is outside these local results; callers still follow the published contract and send `apikey`.

See [Getting started](../docs/getting-started.md), [Verification](../docs/verification.md), and the [foundation task](../docs/tasks/server-local-foundation.md). These checks do not implement the native iOS sign-in flow or deploy the schema to the homelab.

References: [Supabase migrations](https://supabase.com/docs/guides/local-development/database-migrations), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).

## Shared homelab verification

`server/.env.local` is ignored by Git and must have mode 600. The approved remote runner reads `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`; it accepts only the configured homelab HTTPS origin and preserves strict TLS checks. Use the root `.venv` with the existing pinned Python requirements.

```sh
.venv/bin/python server/scripts/test_homelab_api.py --help
```

Actual execution additionally requires `--approved-shared-test` and prior authorization for two temporary confirmed Auth users, test trips/draft and cleanup. It is never run automatically in CI. It reuses the local behavioral suite without weakening that suite's loopback guard. Shared Auth confirmation stays enabled; temporary accounts are provisioned through the admin API without sending emails. See the [approved procedure](../docs/homelab-execution-plan.md) and [results](../docs/homelab-verification.md).

## Private trip reads (step 2)

The additive migration adds `list_my_trips` and `get_trip_snapshot` with the existing Trip shape. See the [wire contract](../contracts/README.md) and [task](../docs/tasks/private-trip-reads.md). The updated suites target both migrations and passed CI: 40/40 pgTAP assertions, clean SQL lint and 39/39 HTTP checks. See [verification evidence](../docs/verification.md). Shared deployment and cleanup are complete under the [approved operational plan](../docs/homelab-trip-reads-plan.md): 40/40 isolated homelab SQL assertions and 40/40 shared HTTP checks passed. The native Swift adapter and UI do not call these RPCs yet.

## Trip model foundation (stage 3A)

The next additive migration separates curated rundown root/version identity and adds server-derived destination date, explicit IANA zone, revision and planned status. `create_trip_v2` / `get_trip_snapshot_v2` return the opt-in V2 shape; all existing RPC shapes remain compatible. See [ADR-0003](../docs/decisions/0003-trip-model-foundation.md), [contract](../contracts/README.md) and [task](../docs/tasks/trip-model-foundation.md). Implementation `d9d90f3` passed 79/79 pgTAP assertions, clean SQL lint and 54/54 HTTP checks in CI, plus contract validation. The [approved shared execution](../docs/homelab-trip-model-verification.md) is complete: both databases restored, persisted legacy backfill verified, 79/79 isolated SQL assertions and 55/55 shared HTTP checks passed; original data/services preserved and temporary records/container removed.

## Normalized graph (stage 3B)

The next migration adds immutable owner-scoped source/day/stop/leg rows and opt-in create_trip_v3/get_trip_graph plus published get_rundown_route. Existing RPC shapes remain compatible. See [ADR-0004](../docs/decisions/0004-trip-graph.md) and [task](../docs/tasks/trip-graph.md). Implementation dd94b14 passes CI: 141/141 pgTAP assertions, clean SQL lint and 66/66 HTTP checks. Matching-image/shared verification completed under the [consolidated plan](../docs/homelab-backend-completion-plan.md).

## Backend completion batch (stages 3B–7)

PR #4 was closed at Giovan's request. Work stays on `gi/trip-graph`; branch CI runs on pushes without a PR. One new review PR is opened only after the agreed batch is complete and verified. See [completion task](../docs/tasks/backend-completion.md).

The batch adds discovery, immutable creation/apply receipts, planned preview/apply edits and explicit merge choices, private session/Storage/journal/album APIs, and the image worker with operational tooling. No native UI/Auth, public creator publishing, completed/skip/ended_early policy or automatic route/weather provider is introduced. [ADR-0005](../docs/decisions/0005-backend-mvp.md) records the human-approved product boundaries.

The database CI additionally installs/tests the locked media worker, runs `scripts/test_backend_completion.py`, the read-only `scripts/ops_status.py`, and `scripts/test_worker_container.py`. The container check is Linux/disposable-CI-only and does not start Mac Docker. Shared equivalents require the refreshed concrete plan and explicit approval; do not infer shared verification from CI.

Worker configuration: [media README](workers/media/README.md), [Compose](deploy/media-worker.compose.yml), [operations runbook](../docs/backend-operations.md). Copy real env into private server configuration with mode 600; the `.env.example` has no credential values. Source/API handlers never print secrets, response bodies or personal records.

The consolidated batch has now completed [approved shared deployment and verification](../docs/homelab-backend-completion-verification.md): 167 isolated SQL assertions, 84 shared HTTP checks, private Storage and healthy restricted worker. The earlier pending notes describe implementation checkpoints; shared verification is no longer pending. Native integration remains a separate handoff.
