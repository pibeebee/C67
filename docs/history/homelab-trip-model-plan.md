# Homelab plan: trip model foundation (stage 3A)

Status: Explicitly approved by Giovan and executed through verification/cleanup. See [actual results](homelab-trip-model-verification.md). The reviewed scope/hashes below are retained.
Date: 23 October 2026 (Asia/Jakarta).

## Fresh read-only preflight

SSH alias homelab; external Compose project supabase under `/home/giovan/apps/supabase`, using docker-compose.yml and docker-compose.cf-tunnel.yml. Database supabase-db/postgres remains PostgreSQL 17.6 on image `sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00`. Ownership/config paths match the earlier verified external project; database ports are unpublished and its only network is supabase_default.

Inspection found 11/11 healthy services, one existing Auth account, two public tables, one catalog version and zero trips. Official history has exactly 20261023030149 and 20261023100158. The new root table/RPCs are absent; Asia/Tokyo is available in pg_timezone_names. Root free space: 63.1 GiB. The proposed backup destination and temporary container name are unused. Recheck identity, ownership, image, capacity, baseline and source hashes immediately before writes; stop/re-plan on drift.

## Exact requested scope and gates

1. Require successful CI for the reviewed implementation and the hashes below. Capture original Auth/catalog fingerprints privately without printing IDs or personal records.
2. Create exclusively `/home/giovan/backups/c67/2026-10-23-before-trip-model` (700, all files 600); preserve both earlier backups. Dump postgres and _supabase in custom format, roles without passwords, and protected configuration/storage archives, following the [foundation backup procedure](homelab-execution-plan.md). Validate archive readability and SHA256SUMS. This is a private same-host logical recovery point.
3. Create only a new c67-db-verify container on the exact existing image, with no network/ports/production mounts, read-only root, tmpfs-only data, user 100:101, 2 GiB RAM, one CPU, shm 128 MiB and no-new-privileges. Restore both databases/roles/owners/grants with the [corrected bootstrap](homelab-trip-reads-plan.md#corrected-isolated-restore-bootstrap): supabase_admin bootstrap, omit only duplicate bootstrap CREATE ROLE from replay, clone-only c67_restore_operator, explicit clone database owners. Keep original backup untouched. Compare original fingerprints/counts/history after restore.
4. In the isolated clone only, create one clearly synthetic compatibility account/trip before the new migration. Capture its v1 snapshot, apply only 20261023163029_add_trip_model_foundation.sql in one transaction, and prove legacy fields/owner/request identity are preserved with null zone/date, revision 1, planned status and valid derived source attribution. Remove that exact synthetic clone account/trip and verify baseline counts/fingerprints again. Do not rerun old migrations or seed.
5. Run all three rollback-based pgTAP files and require 79/79 assertions (14+26+39). Verify three public tables, one root linked to the catalog version, seven public application RPCs, RLS/grants, immutable source identity, valid constraints/index and unchanged original records. SQL test changes roll back. Stop before shared application if any restore/backfill/test gate fails.
6. Open only a process-owned SSH tunnel from unused Mac loopback port 55432 to the freshly resolved DB IP/5432. Obtain the database password into memory/subprocess environment only. Use pinned CLI 2.121.0 from server/; dry-run must identify exactly the one new migration. Do not include seed.

```sh
./node_modules/.bin/supabase db push --db-url 'postgresql://postgres@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --dry-run
./node_modules/.bin/supabase db push --db-url 'postgresql://postgres@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --yes
```

7. Send NOTIFY pgrst, 'reload schema' without service restarts; verify the third official history version and new schema/grants/functions. Recheck original account/catalog and zero pre-test trips.
8. Run `.venv/bin/python server/scripts/test_homelab_api.py --approved-shared-test`. Authorize exactly two uniquely tagged temporary confirmed Auth accounts without sending email; their eleven trips (five v1, six v2), one temporary unpublished version and its automatically generated root; password/refresh sessions and four-way retry tests; and cleanup of those exact records. The root cleanup first proves it has no other version references. Admin credentials provision/clean fixtures only; traveller JWTs prove privacy. Strict TLS/origin guards stay enabled. Expected: 55 shared HTTP checks (54 common plus preservation), recorded only after actual execution.
9. Verify the original Auth identity/catalog bytes unchanged, one original user, one catalog/version/root, zero trips and three official migration versions, all 11 services healthy, database port/network unchanged. Inspect test-container ID/label/mount/network and stop/remove only that owned container; close only the owned tunnel. Retain protected backups and a safe final result record.

## Risk, downtime and rollback

The shared schema gets one root identity table, version/trip metadata columns, constraints/policy, protected derivation triggers, a compatible replacement of v1 create_trip and two opt-in v2 RPCs. Each existing version receives a new distinct root and version number 1; no similar-title grouping or fabricated destination zone occurs. Existing zero-trip state limits backfill work. Short DDL locks and temporary test load can affect latency; no restart/downtime is planned.

No native change, stop/leg normalization, client edit/merge, lifecycle transition, source-distribution/deletion policy, SMTP change, shared reset/seed reload, Mac Docker or ingress modification is included. A failed transaction must not be marked applied. On post-commit verification failure stop further C67 writes and retain diagnostics/backup; do not automatically DROP/restore/delete migration history. Review a destructive rollback against actual data separately. No automatic rollback is requested.

## Pinned inputs

```text
1809f92aee9d92b1a813c3dec5090e55eb284fae7eaf2166fbcc5adcab1eea66  server/supabase/migrations/20261023163029_add_trip_model_foundation.sql
0d624706223585ac8b856e81288ff70c90e185839598cc7f10ce662f8f32a824  server/supabase/tests/starter.test.sql
59f305468f384180b82a7cc9886696c5d0b68d3e651853bf33f8d1a8ef58b34a  server/supabase/tests/trip_reads.test.sql
f8c2287172aa06ccb8daa6f9172d3101bf0e79995d2d2419892d081e84a29ae1  server/supabase/tests/trip_model.test.sql
67d0e5a78a0a8826f39e9d1c5bb7b65a41cdf1f7d49451554b9b8a78fe388557  server/scripts/test_local_api.py
a89c6630ae70e250fa0b2cc33bb47a0869b77fefc08c655924181920e9da9b66  server/scripts/test_homelab_api.py
```

This requests separate approval for the private backup, isolated restore/backfill/test container and exact cleanup, one official shared migration/cache refresh, and the two-account HTTP verification/cleanup. It does not authorize merging the PR or subsequent model slices.

Approval requirement: [homelab-ops/SKILL.md](</Users/giovan/.codex/skills/homelab-ops/SKILL.md>) states “Wait for a separate explicit approval after presenting the preflight.” The previous approval applied to private trip reads only; Giovan subsequently approved this exact stage 3A plan before execution.
