# Server

Supabase is the backend foundation. The existing homelab installation is separate from this local development starter. These files do not deploy anything there.

```text
server/
├── package.json / package-lock.json  # pinned Supabase CLI
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

From this directory run `npm ci`, `npm run start`, `npm run db:reset`, and `npm run db:test`. Docker must be running. Reset is explicitly local and removes local development data. Stop the local stack with `npm run stop`.

The first migration defines curated `rundown_versions`, private `trips`, RLS, and `list_rundowns`, `get_rundown`, `create_trip` RPCs. Clients can read published synthetic versions; authenticated travellers can create and read only their own trips. Direct client table writes are revoked. No bucket or media upload policy is created before the journal/media scope is agreed.

Create new migrations through `npm run supabase -- migration new <name>`. Do not restore a second history under `database/`. Commit migration, contract, fixture and relevant tests together. Run the local database tests before requesting remote deployment.

The pgTAP tests use two synthetic users in a rolled-back transaction. They exercise roles/claims directly, not the Auth HTTP service or a real sign-in session. See [Getting started](../docs/getting-started.md) and [Verification](../docs/verification.md).

References: [Supabase migrations](https://supabase.com/docs/guides/local-development/database-migrations), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
