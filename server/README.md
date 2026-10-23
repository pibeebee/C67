# Server

Supabase is the backend foundation. Local commands below use a separate disposable stack. The starter migration/seed have also been applied to the shared homelab through the explicitly approved procedure; see [homelab verification](../docs/homelab-verification.md). Local scripts do not deploy there automatically.

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
├── workers/media/                   # reserved, no running worker
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

- `db:test`: 40 pgTAP checks of grants, RLS, snapshot copying, retry behavior and private trip reads. Synthetic role/claim tests run in a rolled-back transaction.
- `db:lint`: checks the local public schema and exits nonzero for schema errors.
- `api:test`: 39 HTTP checks through Auth, the gateway and Data API. It signs up two unique synthetic accounts, performs password login and refresh, checks both directions of account isolation, tests denied direct writes and hidden drafts, sends four concurrent retries of one command, and verifies private list/detail pagination, cursor validation and persisted snapshots.

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

The additive migration adds `list_my_trips` and `get_trip_snapshot` with the existing Trip shape. See the [wire contract](../contracts/README.md) and [task](../docs/tasks/private-trip-reads.md). The updated suites target both migrations; previous foundation results do not verify these new RPCs. Shared deployment remains pending a separate reviewed operational plan. The native Swift adapter and UI do not call these RPCs yet.
