# Homelab plan: private trip reads

Status: Prepared; awaiting separate approval. No step 2 homelab mutation has run.
Date: 23 October 2026 (Asia/Jakarta).

## Read-only preflight

SSH alias `homelab`, external Compose project `supabase` in `/home/giovan/apps/supabase`, configuration files `docker-compose.yml` and `docker-compose.cf-tunnel.yml`. The database container is `supabase-db`, PostgreSQL 17.6, image `sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00`. Existing Compose ownership was confirmed; no service recreation is proposed.

Fresh inspection found 11/11 healthy services, database ports unpublished, two public tables, one existing Auth account, one synthetic catalog version, zero trips/non-finite starts, and only migration `20261023030149`. The new RPCs are absent. Root free space is 63.1 GiB and available RAM 10.8 GiB. Target backup directory and temporary container name are unused. Recheck all assumptions immediately before approved writes; stop on drift.

## Exact approved scope requested

1. Require successful CI for this implementation, then recheck source hashes below and the shared baseline. Capture existing Auth IDs/fingerprint privately; do not print personal records.
2. Create exclusively `/home/giovan/backups/c67/2026-10-23-before-trip-reads`, directory mode 700 and files 600. Use `pg_dump --format=custom` for `postgres` and `_supabase`, `pg_dumpall --roles-only --no-role-passwords`, and private configuration/storage archives with SHA256SUMS, as in the [foundation procedure](homelab-execution-plan.md). Preserve the previous backup. Validate checksums/archive readability without exposing contents. Same-host logical backup is the recovery boundary.
3. Restore both databases/roles/owners/grants into a new `c67-db-verify` container using the exact existing image. No network/ports/production mounts; read-only root, tmpfs-only data, user 100:101, 2 GiB RAM, one CPU, shm 128 MiB, no-new-privileges. Use the corrected bootstrap procedure below. Compare the restored Auth fingerprint, counts and migration history to the backup baseline.
4. Apply only `20261023100158_add_private_trip_reads.sql` in the clone with `psql -X -v ON_ERROR_STOP=1 --single-transaction`. Do not rerun the starter migration or seed. Run both rolled-back pgTAP files and require 40/40 passing assertions. Verify five RPCs, RLS, index, finite-date constraint and the unchanged restored baseline after tests. Gate shared application on a complete successful restore and SQL run.
5. Open a process-owned SSH tunnel on unused Mac loopback port 55432 to the freshly resolved internal DB IP/5432. Obtain the database password through SSH into subprocess environment memory only. Use pinned Supabase CLI 2.121.0 from `server/` with the following commands; require exactly the one new pending migration. No seed flag is allowed.

```sh
./node_modules/.bin/supabase db push --db-url 'postgresql://postgres@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --dry-run
./node_modules/.bin/supabase db push --db-url 'postgresql://postgres@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --yes
```

6. Send `NOTIFY pgrst, 'reload schema';` without restarting services. Verify official history now has exactly versions `20261023030149` and `20261023100158`, plus the expected functions/grants/index/constraint.
7. Run `.venv/bin/python server/scripts/test_homelab_api.py --approved-shared-test` from the repository root. This creates only two uniquely tagged temporary confirmed Auth users without email, five personal trips, and one unpublished negative-test catalog row. It obtains actual password sessions and tests refresh, privacy, retries and new list/detail RPCs. Admin access provisions/cleans fixtures; traveller JWTs prove account isolation. Strict TLS and expected-origin guards remain enabled. Expected suite: 40 HTTP checks (39 common plus the shared gateway check); record actual output before claiming a count.
8. Remove only this run's temporary users/cascading trips and draft; assert the original Auth identity is unchanged, original catalog remains, and no trips remain. Verify all 11 services healthy and DB ports unchanged. Inspect the temporary container ID/label and then stop/remove only that container; close only this process's tunnel. Retain private backups and a safe result record.

## Corrected isolated restore bootstrap

Use the [foundation restore adjustments](homelab-verification.md): initialize `supabase_admin` as the bootstrap superuser (matching source bootstrap role/OID), restore roles with only the duplicate `CREATE ROLE supabase_admin;` omitted from the replay stream, then create `c67_restore_operator` as a clone-only superuser for restore. Do not alter the original backup. Restore both databases with `pg_restore --exit-on-error`, preserving ownership/grants. Set clone database owners to `postgres` for database `postgres` and `supabase_admin` for `_supabase`; database-level owner restoration is separate from pg_dump. Use Unix socket `/tmp`, no listening TCP, and required preload libraries `pg_stat_statements,pg_net`. None of these clone-only settings changes shared roles or configuration.

## Risk, downtime and rollback

The additive migration creates two read RPCs, one index, and a finite-start constraint. Existing zero-trip state makes index/constraint work small. Short DDL locks and extra test load can affect latency; no service downtime/restart is planned. No shared reset, seed reload, Auth/SMTP change, iOS change, Mac Docker or ingress change is included.

A failed restore/test gate stops before shared schema changes. A failed migration transaction must not be recorded as applied. If verification fails after commit, stop further C67 writes and retain diagnostics/backups; do not automatically drop functions/index/constraint, delete migration history or restore over shared data. Review any destructive rollback against actual data separately.

Approval covers the private backup, isolated container lifecycle, one official migration, schema-cache notification, two temporary test accounts and their exact records/cleanup through verification. It does not cover merging the PR or other roadmap features.

## Pinned implementation inputs

```text
078a973b101e278c160ec61a2aaad152bb8c2e811827a1bc42576e4a12efe6de  server/supabase/migrations/20261023100158_add_private_trip_reads.sql
0d624706223585ac8b856e81288ff70c90e185839598cc7f10ce662f8f32a824  server/supabase/tests/starter.test.sql
59f305468f384180b82a7cc9886696c5d0b68d3e651853bf33f8d1a8ef58b34a  server/supabase/tests/trip_reads.test.sql
1921631ac7f1607d197c3308a20a65f6890e1333b4efa12fe8a2469b32a3db76  server/scripts/test_local_api.py
6c771a1c038a73065ebd7b8307a4e15d8b6dbe8df3466f0e3a7172b4f6a6dcb9  server/scripts/test_homelab_api.py
```

Operational approval is required by [homelab-ops](</Users/giovan/.codex/skills/homelab-ops/SKILL.md>): “Treat the user's initial write request as intent, not approval of the resulting exact plan. Wait for a separate explicit approval after presenting the preflight.” The earlier foundation approval covered the starter migration only.
