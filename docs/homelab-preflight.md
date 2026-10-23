# Homelab backend foundation preflight

Date: 23 October 2026 (Asia/Jakarta). Scope: read-only SSH inspection authorized by Giovan after API credential validation. This report records observed state and a proposed deployment sequence; no remote mutation is authorized by this document.

## Outcome

The existing Supabase platform is healthy. The C67 application schema has not been installed in the inspected `postgres` database. It is not merely hidden from the Data API. Prepare backup/recovery and an isolated test target before applying the starter migration to the shared development instance.

## Verified target and ownership

- SSH alias/hostname: `homelab`; operator: `giovan`.
- Compose project: `supabase`, directory `/home/giovan/apps/supabase`.
- Files: `docker-compose.yml` and `docker-compose.cf-tunnel.yml`; rendered configuration passes `docker compose config --quiet`.
- Selected Supabase containers carry external Compose paths and no Portainer ownership label hints. Recheck ownership before any lifecycle operation; this inspection did not change container state.
- All 11 Supabase containers are running and report healthy.
- `.env` on the host has mode `600`. Values were not displayed or copied.

## Database and compatibility

| Item | Observation |
|---|---|
| Database container/image | `supabase-db`, `supabase/postgres:17.6.1.136` |
| PostgreSQL runtime | 17.6; the Mac-local tests ran on 17.11, so patch/image parity has not been tested |
| Database sizes | `postgres`: about 11 MB; `_supabase`: about 7.8 MB |
| Installed extensions relevant here | pgcrypto 1.3, uuid-ossp 1.1 |
| Available but uninstalled | PostGIS 3.3.7, pgTAP 1.3.3 |
| First migration requirements | Two tables, three RPCs, UUID generation, grants/RLS and transactional copy; no PostGIS/pgTAP runtime requirement |
| Operator privileges | `postgres` can CREATE in public and REFERENCES auth.users; it is not superuser and does bypass RLS |

The major PostgreSQL version matches the local baseline. Source review found no requirement in the first migration that depends on PostGIS or a different major version. This is a compatibility assessment, not execution evidence on the homelab image. Run the migration and pgTAP in an isolated matching environment before shared application.

## Schema, history and access

- No tables were found in `public`; `supabase_migrations.schema_migrations` is absent.
- `public.rundown_versions` and `public.trips` are absent.
- `list_rundowns()`, `get_rundown(uuid)` and `create_trip(uuid,timestamptz,uuid)` are absent.
- No public-table RLS policies or anon/authenticated/service_role table grants exist to audit for C67 yet.
- PostgREST exposes `public,graphql_public`, with anonymous role `anon`. No exposure change is needed for the starter's chosen public schema.
- `anon` and `authenticated` are non-login roles without BYPASSRLS. `service_role` has BYPASSRLS, as expected for administrative access. RLS tests must use user identities, not the service role.
- One existing Auth user is present; no account identifiers or content were read. Storage has zero bucket records and zero object records. Existing Auth data must be preserved.

## Network, storage and Auth

- Database has no published host port and joins only `supabase_default`.
- REST/Auth/Storage stay on the internal Supabase network. The Envoy gateway joins that network and `cf-tunnel`.
- Database data: `/home/giovan/apps/supabase/volumes/db/data`.
- Storage bytes: `/hdd/supabase/storage`; a database dump alone is not a backup of those bytes.
- Email signup is enabled, and email auto-confirmation is disabled on the shared instance.
- The local HTTP suite deliberately requires loopback and disabled email confirmation. Do not point it at the homelab or change shared Auth settings to make it pass. A later remote integration suite needs a separate approved scope for two temporary users and cleanup, without sending test emails.
- SSH/container access is sufficient for inspection; no PostgreSQL port exposure or database password copied to the Mac was needed.

## Backup, test isolation and capacity

- No separate Supabase test instance was found in the running/stopped container inventory.
- No Supabase/C67 backup was found at the inspected candidates: the app's `backup`/`backups` directories, `/home/giovan/backups`, `/hdd/backups` and `/hdd-external/backups`.
- No Supabase backup timer or direct Supabase backup entry was found among readable system/user timers and the user's crontab. Accessible cron script paths concerned the AdGuard watchdog. Root crontab was not readable with non-interactive privileges. This is bounded evidence; it does not prove no backup exists anywhere.
- PostgreSQL archive_mode is off. No archive/restore or off-host backup was demonstrated.
- Observed free space: root 63.1 GiB, `/hdd` 219.5 GiB, `/hdd-external` 784.9 GiB. Available RAM: about 10.3 GiB. These are snapshots, not reserved capacity or load-test evidence.

## Proposed application sequence (not executed)

1. Recheck exact target, schema absence, account count, Compose ownership and source checksums immediately before writes.
2. Define an isolated test target on the homelab with the matching PostgreSQL image and required platform roles/Auth schema. Keep it separate from shared database/storage paths and public ingress. Run migration/seed and pgTAP there; the account-level HTTP path additionally needs its own Auth/gateway test scope.
3. Create a permission-restricted backup destination and capture a logical custom-format dump of the current shared `postgres` database plus protected copies of the owning Compose/configuration. Do not print configuration or secrets. Verify the archive and restore it in isolation; preserve the existing Auth user. Include separate Storage-byte backup when assets are introduced.
4. Review and approve the pinned migration runner and migration-history initialization for this self-hosted target. Use a single history at `server/supabase/migrations/`; do not fake a CLI receipt or apply an untracked second migration history.
5. Apply only migration `20261023030149_starter_rundowns_and_trips.sql` and the authoritative synthetic seed through the reviewed runner. Business DDL/seed should be atomic; record the applied migration through the same supported history mechanism. No database reset, container recreation, Auth/SMTP change, or PostGIS installation is part of this baseline.
6. Refresh the PostgREST schema cache and verify the three RPCs and table grants/RLS. Verify the existing Auth account remains. Then run a separately scoped two-account integration check and remove only its test data.
7. Publish the verified development endpoint/contract to the iOS data owner and begin step 2: private trip list/detail APIs. Keep secrets outside Git and the iOS app.

### Risk, downtime and rollback boundary

- Target: only the application objects in `postgres.public` and the approved migration ledger. Auth and Storage platform schemas are not migration targets.
- Expected service interruption: no restart is proposed. DDL locks and gateway cache refresh may briefly affect requests; no zero-downtime guarantee is established by inspection.
- Before commit: a failed atomic migration should roll back without partial C67 objects. After commit: freeze new C67 writes and review a targeted reversal against the actual rows/dependencies; do not automatically DROP tables or restore the whole database over an existing Auth account.
- Existing migrations contain no remote reset. Never reuse the local `db:reset` workflow against this shared target.
- Execution requires approval of the concrete commands/runner, backup/restore result, risk and rollback plan. This report does not request or assume that approval.

## Sources and evidence boundary

- [Backend architecture decision](decisions/0002-server-architecture.md)
- [Server guide](../server/README.md)
- [Migration](../server/supabase/migrations/20261023030149_starter_rundowns_and_trips.sql)
- [Seed](../server/supabase/seed.sql)
- [Local verification](verification.md#local-backend-foundation--23-october-2026)

Live SQL inspection used BEGIN READ ONLY with a statement timeout, followed by ROLLBACK. No migrations, extension installation, account creation, backup writes, restart, reset, network changes or deployment occurred. Previous API checks validated legacy keys separately; no secrets are recorded here.

Source checksums at inspection:

```text
server/supabase/migrations/20261023030149_starter_rundowns_and_trips.sql  sha256:fdf59616474cb8bf323ce9e7bc34febbbfa3bda77ccb23d371446beaa63528f6
server/supabase/seed.sql  sha256:6104fc58b15c06f7419e97ece01f84205db97c2360e021e140d6f4bb7fad5dc0
```
