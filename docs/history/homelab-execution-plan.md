# Homelab C67 execution plan — approved and executed

Date: 23 October 2026 (Asia/Jakarta). Prepared after Giovan requested continuation through verification. The user explicitly approved this concrete plan. Execution and verification are complete; see [actual results and restore adjustments](homelab-verification.md). Command blocks below preserve the reviewed plan; restore-bootstrap and database-owner adjustments are recorded in the results.

## Targets and gates

- Shared target: SSH `homelab`, Compose project `supabase`, container `supabase-db`, database `postgres`, PostgreSQL 17.6.
- Current shared state: one Auth user, no public tables or C67 migration history. Preserve the existing account and current Auth/SMTP settings.
- Backup target: `/home/giovan/backups/c67/2026-10-23-before-starter`; create exclusively, mode 700, files 600. Abort if the destination already exists; do not overwrite a backup.
- Temporary test target: Docker container `c67-db-verify`, using the existing image ID `sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00` (supabase/postgres:17.6.1.136).
- Test isolation: no network, no published ports, no production bind mounts, read-only root filesystem; PostgreSQL data lives only in container tmpfs. Limit: 2 GiB RAM and one CPU. Only the approved, newly created test container may be stopped/removed.
- Do not start Docker on the Mac, reset the shared database, recreate Supabase services, expose PostgreSQL, install PostGIS in the shared database or change public ingress.

Immediately before writing, recheck image ID, container ownership/health, schema absence, account count, free space and source checksums. Abort on unexpected drift. Record an in-memory fingerprint of existing Auth IDs and compare after verification; do not print IDs or private account records.

## 1. Private backups on the homelab

Run through non-interactive SSH, with `umask 077`; all backup streams go to private files, never tool output:

```sh
umask 077
mkdir -p /home/giovan/backups/c67
mkdir /home/giovan/backups/c67/2026-10-23-before-starter
chmod 700 /home/giovan/backups/c67 /home/giovan/backups/c67/2026-10-23-before-starter
```

Inside that new backup directory:

```sh
docker exec supabase-db pg_dump -U postgres -d postgres --format=custom > postgres.dump
docker exec supabase-db pg_dump -U postgres -d _supabase --format=custom > platform-metadata.dump
docker exec supabase-db pg_dumpall -U postgres --roles-only --no-role-passwords > roles.sql
tar -czf supabase-config.tar.gz -C /home/giovan/apps/supabase .env docker-compose.yml docker-compose.cf-tunnel.yml volumes/api/envoy
tar -czf supabase-storage.tar.gz -C /hdd/supabase storage
chmod 600 postgres.dump platform-metadata.dump roles.sql supabase-config.tar.gz supabase-storage.tar.gz
sha256sum postgres.dump platform-metadata.dump roles.sql supabase-config.tar.gz supabase-storage.tar.gz > SHA256SUMS
```

Use subprocess capture for failure diagnostics and suppress sensitive SQL/configuration contents. Stop on the first error. Validate archive readability/listing without printing entries, and verify checksums. Config backup contains secrets; it must remain private on the homelab. Role passwords are excluded from the SQL dump; existing service credentials stay in protected configuration. This is a same-host logical recovery point, not off-host disaster recovery.

## 2. Restore drill and SQL tests in isolation

Create exactly this new container only after confirming the name is unused:

```sh
docker run -d --name c67-db-verify --label c67.purpose=restore-migration-check \
  --network none --read-only --user 100:101 --memory 2g --cpus 1 --shm-size 128m \
  --tmpfs /tmp:rw,nosuid,size=1536m,mode=1777 \
  --entrypoint sh \
  sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00 \
  -ec 'initdb -D /tmp/c67-pg --username=c67_restore_operator --auth=trust >/tmp/init.log 2>&1; exec postgres -D /tmp/c67-pg -k /tmp -c listen_addresses= -c shared_preload_libraries=pg_stat_statements,pg_net'
```

Wait for the Unix socket inside this container. Use `docker exec -i` for all restore/test streams, never attach it to the shared Docker network:

1. Restore `roles.sql` as bootstrap superuser `c67_restore_operator` into the isolated `postgres` database. This bootstrap role has a different name from the source roles and can restore ownership/grants without weakening shared roles.
2. Restore both custom-format database dumps into separate isolated databases, using `pg_restore --exit-on-error` and preserving original owners/privileges. Fail the gate if a complete restore cannot be demonstrated. No shared database is a restore destination.
3. Compare restored counts and the existing Auth-account fingerprint with the backup/source baseline. Check shared-table absence in the restored baseline.
4. Stream the exact repository migration and seed into the restored `postgres` using `psql -X -v ON_ERROR_STOP=1 --single-transaction`. No history receipt is fabricated in this SQL test target.
5. Run the existing `server/supabase/tests/starter.test.sql` on the isolated restored database. Require 14 successful pgTAP assertions and no failures. pgTAP installation and synthetic Auth inserts occur only in this temporary database; the test transaction rolls back.
6. Verify RLS/grants, two tables, three RPCs and exactly one catalog fixture. The shared application phase is blocked unless restore and migration tests pass.

If the matching image requires additional startup compatibility settings, stop before the shared phase and assess them within this isolated target. Never change the production image/configuration to make a test pass.

## 3. Apply using the pinned official migration runner

Keep one authoritative migration source: `server/supabase/migrations/20261023030149_starter_rundowns_and_trips.sql`. Use Supabase CLI 2.121.0 already installed on the Mac; no Mac Docker is needed.

Create a temporary SSH tunnel, owned by the verification process, binding only Mac loopback:

```sh
ssh -o BatchMode=yes -o ConnectTimeout=10 -o ExitOnForwardFailure=yes -N \
  -L 127.0.0.1:55432:192.168.128.2:5432 homelab
```

Resolve/recheck the internal DB IP immediately before creating the tunnel. Abort if local port 55432 is occupied. Obtain the current PostgreSQL password through SSH into process memory only; do not print it, place it in command arguments or persist it in the repository. Provide `SUPABASE_DB_PASSWORD`/`PGPASSWORD` only to the CLI subprocess. Capture CLI output privately in case the runner includes sensitive diagnostics.

Run from `server/`:

```sh
./node_modules/.bin/supabase db push --db-url 'postgresql://postgres@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --dry-run
./node_modules/.bin/supabase db push --db-url 'postgresql://postgres@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --include-seed --yes
```

Transport outside the homelab is encrypted by SSH; PostgreSQL stays unpublished. The official CLI creates/updates its own migration history. Do not write fake receipts or introduce another migration ledger. Dry-run/CLI bootstrap can create migration metadata, so both commands belong to this approved write phase after backup. Only the one reviewed migration may appear as pending. Seed may run separately from the migration transaction; verify its result rather than claiming atomicity across CLI phases. Send `NOTIFY pgrst, 'reload schema';` after application, without restarting containers.

Pinned input hashes:

```text
migration: fdf59616474cb8bf323ce9e7bc34febbbfa3bda77ccb23d371446beaa63528f6
seed:      6104fc58b15c06f7419e97ece01f84205db97c2360e021e140d6f4bb7fad5dc0
pgTAP:     0d624706223585ac8b856e81288ff70c90e185839598cc7f10ce662f8f32a824
```

## 4. Shared HTTP verification and cleanup

Use the prepared `server/scripts/test_homelab_api.py` runner loading ignored `server/.env.local`; preserve the strict loopback-only behavior of the existing local suite. Allow only the known HTTPS homelab origin, verify TLS, reject redirects and never print keys/sessions or response bodies.

- Provision two uniquely tagged temporary Auth users using `POST /auth/v1/admin/users` with synthetic example.invalid addresses, random in-memory passwords and `email_confirm=true`. Do not send confirmation emails or modify global Auth/SMTP settings.
- Obtain actual user sessions through password login; administrative credentials are used only for fixture provisioning and cleanup, never to prove RLS.
- Verify the existing local suite's relevant behavior through the homelab API: catalog/detail, required sessions, copy snapshot, same-request retry, changed-input conflict, direct-write denial, bidirectional account isolation and concurrent retry identity. Test refresh while preserving the existing account.
- Create only one uniquely identified temporary unpublished catalog row for negative read tests. Delete only that row and the two test users/trips in cleanup, verifying their absence.
- Assert that the original Auth-account fingerprint is unchanged, exactly the original account remains, the synthetic seed is present, no test trips remain, migration history has the expected version, and the existing 11 services remain healthy.
- Close only the tunnel started by this run. Stop/remove only `c67-db-verify` after verifying its ID and ownership label; its tmpfs restore data is discarded. Retain the private backups and safe verification report.

Execute the prepared runner only after approval with `.venv/bin/python server/scripts/test_homelab_api.py --approved-shared-test` from the repository root. Its syntax/import/help path has been checked without network calls. The runner is restricted to these exact API/data boundaries; it is not authorized to create or delete any other account, change source data or enable new product policies.

## Risk, downtime, rollback and approval

The shared phase creates the two C67 tables, three functions, their grants/RLS, official migration metadata, one public synthetic catalog fixture, and temporary verification records. An existing Auth account must be preserved. No container restart or service downtime is planned; DDL locks/cache refresh and temporary resource usage can still affect latency.

Backup/restore failure or isolated test failure stops execution before shared application. A failed migration transaction must not be marked applied. If verification fails after commit, stop new C67 writes and retain diagnostics/backups; do not automatically reset/restore the shared database or DROP committed tables. Any destructive rollback is reviewed against actual data first.

Approval sought: execute the phases above, including private backup files, the isolated temporary Docker container, official migration/seed application, two temporary Auth users and their exact cleanup, through the stated verification. No commit/push or broader application feature is included.

Operational reason for the separate approval: [homelab-ops](</Users/giovan/.codex/skills/homelab-ops/SKILL.md>) requires a concrete preflight and a separate approval before remote mutations. Previous read-only inspection did not authorize these write commands.
