# Homelab C67 foundation verification

Date: 23 October 2026 (Asia/Jakarta). Scope: the explicitly approved [execution plan](homelab-execution-plan.md), following [read-only preflight](homelab-preflight.md). Result: complete for the starter backend foundation; trip list/detail feature work remains step 2.

## Outcome

Migration `20261023030149` and its synthetic catalog seed are now applied to the shared Supabase development instance. Two matching-image database restores, isolated SQL tests and shared HTTP acceptance checks passed. Existing Auth identity was preserved; all temporary verification records and the test container were removed.

## Backup and restore evidence

- Private backup: `/home/giovan/backups/c67/2026-10-23-before-starter` on `homelab`.
- Directory/parent mode 700; every backup/diagnostic file mode 600.
- Archives: `postgres.dump`, `platform-metadata.dump`, `roles.sql` (no role passwords), `supabase-config.tar.gz`, `supabase-storage.tar.gz`; `SHA256SUMS` verified.
- Config and storage archives are readable. Source configuration/secret values were never displayed or committed.
- Both custom-format dumps restored into the isolated matching PostgreSQL 17.6 image with original roles, object ownership and privileges. Auth identity/count matched the source baseline before test mutations.
- This is a same-host recovery point. It does not demonstrate off-host disaster recovery, automated backup scheduling or production recovery time.

### Restore compatibility adjustments

The first isolated restore stopped on PostgreSQL 17 role membership grantor checks. Reusing the source bootstrap identity `supabase_admin` made the original `GRANTED BY` records restorable; only its duplicate CREATE ROLE statement was omitted from the execution stream. The untouched role dump is retained. A separate isolated restore-operator role was then created for the drill.

A subsequent migration probe found that database-level ownership was not restored by plain pg_dump archives. Source owners were inspected and applied only to the clone: `postgres` database owned by `postgres`, `_supabase` owned by `supabase_admin`. With roles and database ownership aligned, migration and tests passed. No shared role, owner or service configuration was changed to resolve these issues.

## Isolated SQL evidence

- Image: `supabase/postgres:17.6.1.136`, existing exact image ID recorded in the execution plan.
- Temporary container: `c67-db-verify`, network `none`, no published ports or production mounts, read-only root, tmpfs data, one CPU and 2 GiB memory limit.
- Exact repository migration and seed applied in a single transaction to the restored test database.
- Existing pgTAP suite: **14/14 assertions passed**; synthetic inserts and pgTAP extension creation rolled back inside its test transaction.
- Shared schema/account baseline remained unchanged until this gate passed.
- Test container ID/label/isolation verified before stopping and removing it. No persistent test volume was created.

## Shared application evidence

- Pinned official Supabase CLI 2.121.0 used through an owned, temporary SSH tunnel bound only to Mac loopback.
- CLI dry-run identified the approved migration; apply used `--skip-vault --include-seed --yes`.
- CLI created its own `supabase_migrations.schema_migrations` history; version present: `20261023030149`.
- Shared PostgreSQL was not reset; its port remains unpublished. No Mac Docker startup or shared-container restart was needed.
- PostgREST schema cache refreshed using NOTIFY.
- Final schema: two public tables, three starter RPCs; RLS enabled on both tables; one authoritative synthetic rundown version; zero remaining trips.

## Shared HTTP evidence

Command from repository root:

```sh
.venv/bin/python -u server/scripts/test_homelab_api.py --approved-shared-test
```

**28/28 checks passed**, covering actual password sessions for two temporary accounts, refresh, required/invalid sessions, published catalog/detail, snapshot/instant preservation, idempotent retries, changed-input conflicts, direct-write denial, hidden drafts, bidirectional account isolation and four concurrent retries producing one trip identity.

Temporary users were provisioned via the Auth admin API with confirmed synthetic example.invalid addresses. No confirmation email was sent and shared confirmation/SMTP policy was not changed. User-session JWTs, not the service role, exercised private trip access. The service role was used only for metadata/provisioning/fixture setup and cleanup.

Envoy returns plain-text HTTP 401 for missing credentials. The remote runner accepts gateway error bodies at that boundary while still asserting PostgREST error codes/envelopes where contracted. The local-only suite remains unchanged and cannot silently target the homelab.

Final SQL and API cleanup checks confirmed the original one-account identity set is preserved, no extra users/trips/drafts remain, and the synthetic seed persists. All 11 existing Supabase containers remained running and healthy at final inspection. The owned SSH tunnel is closed.

## Source and local checks

- Migration, seed and pgTAP source hashes match the approved execution plan.
- OpenAPI, fixture schemas, Swift fixture copy and SQL seed consistency validation passed.
- Python verification scripts parse; git whitespace checks pass. Updated GitHub Actions were not run remotely for this unpushed branch.
- Safe remote execution summary: `final-verification.json` inside the private backup directory.

## Remaining boundaries

No native iOS login/keychain/session UI integration, physical device/GPS, media pipeline, merge, new trip list/detail endpoints, load testing, off-site backup or scheduled backup was implemented. No keys/passwords/sessions were placed in Git or app configuration. No commit/push was requested or performed.

Next task: scope step 2 (private trip list and consistent trip detail snapshot) against the shared contract and iOS data owner. The existing `create_trip` path is now verified on the actual development backend.
