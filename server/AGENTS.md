# Server instructions

Apply the [root instructions](../AGENTS.md). Scope: `server/`.

- Follow [the server README](README.md) and [ADR-0002](../docs/decisions/0002-server-architecture.md). The foundation is Supabase PostgreSQL/RLS/RPCs; `package.json` pins CLI tooling, not a custom Node HTTP server.
- Keep one migration history in `supabase/migrations/`. Create a migration from `server/` with `npm run supabase -- migration new <name>`. Add a new migration for shared schema changes; do not rewrite applied history.
- Derive ownership from a verified session on the server, never a submitted `owner_id` or client-side boolean. Preserve RLS and explicit grants on exposed tables. A definer RPC must have a justified privilege boundary, a controlled search path and explicit caller checks.
- Preserve atomic snapshot creation and owner-scoped idempotency. Test changed-input retries and access from another account. Published creator data and traveller copies have different lifecycles.
- Keep `../contracts/api/openapi.json` aligned with RPC inputs, results and errors. Synthetic seed source is `../contracts/fixtures/`; update copies with the root sync script.
- Public synthetic catalog reads are a development policy, not a settled production distribution rule. Media, presence and creator publishing need their own approved contracts; do not create permissive buckets to bypass missing policy.
- Shared development targets the homelab; SQL mutation/reset tests use a separate isolated homelab target. Mac-local Docker is optional, not a prerequisite. Never reset the shared instance or apply migrations as an incidental test. Recheck ownership, backup/recovery and the explicit approved scope before shared changes. Keep operational credentials outside the repo.

## Local commands and verification

Run inside `server/`: `npm ci` installs pinned tooling, `npm run start` starts a local Docker stack, and `npm run db:test` runs pgTAP in that stack. When explicitly authorized to rebuild disposable local data, `npm run db:reset` passes `--local` and deletes/recreates it; confirm the local target and preserve needed data first. Stop your own local stack with `npm run stop`.

For SQL changes, run the database suite after applying the migration locally and run contract checks when wire behavior changes. Tests live in `supabase/tests/`. Direct role/claim tests establish database authorization behavior, not real Auth HTTP/session behavior. If Docker is unavailable, report the database suite as unrun; do not substitute a shared-server reset.

## Homelab workflow

Follow [the verified foundation](../docs/homelab-verification.md) and the approved operational plan for each new change. Create a new migration, prepare contract/acceptance tests locally, test it in isolation on the matching homelab PostgreSQL image, and obtain approval of concrete shared write operations before deployment. Never silently repoint `test_local_api.py` at a remote URL. The separate `test_homelab_api.py` needs explicit approval for its temporary users and cleanup.
