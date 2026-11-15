# Homelab plan: normalized trip graph (stage 3B)

Status: Superseded by the consolidated stages 3B–7 plan after Giovan closed PR #4 and expanded the task. No execution of this standalone plan occurred. See [completion plan](homelab-backend-completion-plan.md).
Date: 24 October 2026 (Asia/Jakarta).

## Fresh read-only preflight

SSH homelab, external Compose project supabase under `/home/giovan/apps/supabase` with docker-compose.yml/docker-compose.cf-tunnel.yml. Database supabase-db/postgres is PostgreSQL 17.6 on image `sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00`. Database ports remain unpublished and its only network is supabase_default.

Observed: 11/11 healthy services, one existing Auth user, one catalog version/root, zero trips, three public tables and exactly migrations 20261023030149, 20261023100158 and 20261023163029. Graph tables/RPCs are absent. The one existing source stop array satisfies UUID/title/contiguous-order requirements; there are no persisted shared trip arrays. Root free space is 63.1 GiB. Backup destination and temporary container name are unused. Recheck all assumptions, ownership, image, capacity, original record fingerprints and source hashes immediately before approved writes; stop/re-plan on drift.

## Exact requested operations

1. Require successful CI for the reviewed implementation and the hashes below. Capture Auth identity, catalog/root content and container ID/start-time fingerprints privately.
2. Create exclusively `/home/giovan/backups/c67/2026-10-24-before-trip-graph`, mode 700 and every file 600. Preserve previous backups. Dump postgres and _supabase in custom format, roles without passwords, protected configuration/storage archives and SHA256SUMS using the [foundation procedure](homelab-execution-plan.md). Validate archive readability/checksums without exposing contents. This remains a same-host logical recovery point.
3. Create only c67-db-verify on the exact existing image: no network/ports/production mounts, read-only root, tmpfs-only data, user 100:101, 2 GiB RAM, one CPU, shm 128 MiB, no-new-privileges. Restore both databases/roles/owners/grants with the proven supabase_admin bootstrap, clone-only restore operator and explicit database-owner corrections. Compare original records/history after restore. Keep original backups unchanged.
4. In the clone only, create one synthetic compatibility Auth user with two persisted pre-migration trips (V1 unknown zone, V2 explicit zone), including saved stop values distinct from current source content. Capture complete old responses, owner/request IDs and revisions. Apply only 20261024002359_normalize_trip_graph.sql in one transaction. Prove both old responses/retries unchanged, stored graph uses those saved stops, no current-source geometry/basis is invented, occurrence IDs remain stable on reload, and source/day/endpoint FKs validate. Remove exactly those compatibility records and compare the original baseline again. No old migration/seed replay.
5. Run all four rollback-based pgTAP suites and require 141/141 assertions (14+26+39+62), including explicit O≠L≠S1 and landing=first_stop cases, RLS, immutable graph and cross-aggregate/day/source rejection. Verify seven public tables, ten application RPCs, all graph grants/RLS/constraints/index and unchanged original records. Stop before shared application on any restore/backfill/test failure.
6. Open an owned SSH tunnel on unused Mac loopback port 55432 to freshly resolved internal DB IP/5432. Obtain the password only in process memory/subprocess environment. Use pinned CLI 2.121.0 from server/; require exactly the reviewed migration in dry-run and never include seed.

```sh
./node_modules/.bin/supabase db push --db-url 'postgresql://postgres@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --dry-run
./node_modules/.bin/supabase db push --db-url 'postgresql://postgres@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --yes
```

7. Send NOTIFY pgrst, 'reload schema' without restarting services. Verify official history now includes the fourth version, expected functions/grants/RLS, and original records unchanged.
8. Run `.venv/bin/python server/scripts/test_homelab_api.py --approved-shared-test` with the existing strict HTTPS origin/TLS guards. Authorize only two uniquely tagged confirmed Auth users without email, their fifteen trips (five V1, six V2, four V3), one temporary unpublished version/root plus two synthetic published route versions/their own roots, and their exact cleanup. Derived test graph rows are expected to be fifteen sources, fifteen days, thirty stops and twenty-one legs. Tests use real password/refresh sessions and four-way retries. Only the two newly created route fixtures may be patched for source-change validation; preserve the original catalog. Expected total is 67 shared HTTP checks (66 common plus account preservation); record actual output before claiming it.
9. Cleanup deletes only temporary users/cascading trips/graph rows, then exact fixture versions/roots after verifying no extra version reference. Verify one original user, one original catalog/root, zero trips and zero graph rows, four official migration versions, valid constraints and all 11 services healthy with unchanged IDs/start times. Inspect isolated container ID/label/mount/network, then stop/remove only that owned container. Close only the owned tunnel. Retain private backups and a safe final report.

## Risk, downtime and rollback

This migration adds four owner-scoped graph tables, optional source route metadata, V3 command metadata, internal validation/population/immutability guards, three opt-in RPCs and compatible replacements of V1/V2 creation to share-lock source metadata during copying. Historical trips normalize their saved JSON; incomplete route facts remain unknown. Graph child mutations and root changes to stops/start/zone/basis/origin are blocked until an explicit graph editing command exists. This also restricts privileged maintenance writes to those fields; approved future edits need their own migration/command.

Existing zero-trip state limits backfill work. DDL locks and temporary test load can affect latency; no restart/downtime is planned. No shared reset/seed reload, native change, provider/scheduler, lifecycle/merge/source-rights policy, SMTP or ingress change is included. No Mac Docker is needed.

A failed restore/backfill/test gate stops before shared writes. A failed migration must not be marked applied. On post-commit verification failure, stop C67 writes and retain backup/diagnostics; do not automatically DROP graph data/guards, delete history or restore over shared data. Review any destructive rollback against actual data separately; none is pre-authorized here.

## Pinned inputs

```text
5304b9c27a33e9e88b85e72b3134c3c5e882bd651b4943f63d531d3bdceaaa2d  server/supabase/migrations/20261024002359_normalize_trip_graph.sql
0d624706223585ac8b856e81288ff70c90e185839598cc7f10ce662f8f32a824  server/supabase/tests/starter.test.sql
f08958b62013c44bddd2cf968d3ac3902c1b76b1bb40a5afd1dd7660071b89b5  server/supabase/tests/trip_graph.test.sql
f8c2287172aa06ccb8daa6f9172d3101bf0e79995d2d2419892d081e84a29ae1  server/supabase/tests/trip_model.test.sql
59f305468f384180b82a7cc9886696c5d0b68d3e651853bf33f8d1a8ef58b34a  server/supabase/tests/trip_reads.test.sql
5ad85d5ca4e22a4134532f9115b836750ab3d1e9390522880fdabc88550a55e3  server/scripts/test_local_api.py
efba48da4209698dab5fa966b6ca0cf601a58cd96831a6e9d2846d215e835bf3  server/scripts/test_homelab_api.py
a8794cc43b42c79eee0c116cc6321d89e573db4cddc7a27624aefd3976b5a6f4  contracts/fixtures/route-template-separate.json
24450082a7a3ad14cefcca554905b446ee27a3fd55cc805545e68317c93456ed  contracts/fixtures/route-template-first-stop.json
```

Approval covers the private backup, exact isolated restore/backfill/SQL test and container cleanup, one official shared migration/cache refresh, and the bounded temporary HTTP records/patches/cleanup above. It does not authorize merging the PR or subsequent features.

[homelab-ops/SKILL.md](</Users/giovan/.codex/skills/homelab-ops/SKILL.md>) requires “Wait for a separate explicit approval after presenting the preflight.” The earlier approval covered stage 3A only.
