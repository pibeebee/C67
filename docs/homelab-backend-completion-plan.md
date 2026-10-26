# Homelab backend completion plan (stages 3B–7)

Status: Prepared; awaiting separate explicit approval. No shared mutation in this batch has run.
Date: 26 October 2026 (Asia/Jakarta).

This replaces the earlier unexecuted graph-only plan. Giovan requested completing the entire agreed backend batch before opening a PR. Product decisions are recorded in ADR-0005; they do not by themselves approve the exact additional shared tables/buckets/worker operations below.

## Fresh read-only preflight

Target: SSH homelab; external Compose project supabase under `/home/giovan/apps/supabase`, docker-compose.yml plus docker-compose.cf-tunnel.yml. Database supabase-db/postgres remains PostgreSQL 17.6 on image `sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00`; its ports are unpublished and only network is supabase_default. Storage image is supabase/storage-api:v1.81.0. All 11 services are healthy.

Shared data: one original Auth account, one catalog version/root, zero trips, zero buckets/objects, three public tables. Official history is exactly 20261023030149, 20261023100158 and 20261023163029. Graph tables are absent. Root free space 63.1 GiB, available RAM 10.6 GiB. Proposed worker directory/project, isolated container name and backup destination are unused. Recheck these facts, manager/labels, capacity, source hashes, private original-record fingerprints and service IDs/start times immediately before writes. Stop/re-plan on unexpected drift.

## Exact write scope and sequence

1. Require passing final implementation CI (database, API/Storage/worker, container smoke, contracts, style and iOS). Keep PR #4 closed. Capture original Auth/catalog/root/Storage fingerprints privately, without personal output.
2. Create exclusively `/home/giovan/backups/c67/2026-10-26-before-backend-completion`, mode 700/files 600; preserve all older backups. Use the reviewed backup tool for postgres/_supabase dumps, roles without passwords, protected config and Storage archives; validate SHA256SUMS and archive readability. This is a same-host recovery point, not off-host disaster recovery. With no existing bucket/object/trip, the current app-data recovery baseline is explicit.
3. Create only c67-db-verify using the exact existing PostgreSQL image, no network/ports/production mounts, read-only root, tmpfs data, user 100:101, one CPU/2GiB, shm128MiB/no-new-privileges. Restore both databases/roles/owners/grants with the proven supabase_admin bootstrap, clone-only operator and explicit database-owner procedure. Keep original dumps untouched.
4. In the isolated clone only, provision one synthetic compatibility account with persisted V1 and V2 trips whose saved stops differ from current source. Capture original responses, ownership/request/revision. Apply the four pending migrations in order, without seed replay; prove backfilled graphs use saved JSON/unknown historical route facts, v1/v2 payloads and receipt retries survive later edits, and cleanup restores original records. Run all SQL suites and schema/grant/RLS checks. Stop before shared application on restore/backfill/test failure.
5. Provision a new private build directory `/home/giovan/apps/c67-media` (700). Copy only reviewed worker/deploy source/lockfiles, no local node_modules/env/secrets. Build the pinned Node22/sharp image as `c67-media:<reviewed-revision>` on the homelab. The Dockerfile base digest and npm lockfile are pinned; memory/CPU/runtime restrictions are in Compose. Obtain the existing service-role key from the homelab process configuration into a new private mode600 env file; never print/paste it or put it into image/build args. HTTPS origin stays https://supabase.mrt.qzz.io. Do not start the continuous worker before the explicit acceptance suite to avoid competing claims.
6. Use pinned Supabase CLI 2.121.0 through an owned Mac-loopback SSH tunnel to the freshly resolved internal DB IP/5432. Password stays in memory/subprocess environment only. Dry-run must show exactly these pending versions:
   - 20261024002359_normalize_trip_graph
   - 20261026012332_add_discovery_search
   - 20261026012334_add_trip_edit_receipts
   - 20261026012335_add_private_journal_pipeline

```sh
./node_modules/.bin/supabase db push --db-url 'postgresql://postgres@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --dry-run
./node_modules/.bin/supabase db push --db-url 'postgresql://postgres@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --yes
```

No include-seed flag or shared reset. The CLI may commit migrations separately: record the actual applied prefix if a later migration fails; do not claim atomicity across all four files. Send NOTIFY pgrst, 'reload schema' without Supabase restart. Verify all seven official versions, new tables/RLS/receipts, private bucket limits/policies and worker-only privileges.

7. Run the existing expanded homelab suite and then the completion suite with `--approved-shared-test`, sequentially. Authorize only their uniquely tagged synthetic accounts/fixtures, exact retry/patch operations and cleanup:
   - Existing suite: two temporary confirmed users, fifteen trips, one unpublished and two synthetic published route versions/their own roots, derived graph rows; patch only the newly created route fixture.
   - Completion suite: two different temporary users, two new synthetic published route versions/roots, one trip with explicit title/reschedule/append/retain choices and concurrent revision attempts, three preview command receipts plus other exact test previews/receipts, two upload sessions/raw objects (one valid generated PNG and one fake PNG), one processed JPEG and one accepted private journal. It also deliberately expires only its own claimed test lease/session via admin API to prove recovery/no second location gate. Never patch the original catalog/account or unfamiliar jobs.
   - Run manual worker validation for only these jobs using the reviewed source/image and private process env. Repeated/stale calls must not duplicate journals. Exercise raw/ready privacy and failed-image rejection. Cleanup removes exact temporary users/cascading graph/journal/receipt records, their known versions/roots, and worker candidate bytes through Storage API before SQL purging. No SQL deletion of storage.objects. Inspect absence through API/database privately. If preflight discovers existing non-test worker jobs, stop and re-plan rather than process them as acceptance fixtures.
8. Start the new external Compose project c67-media with only its one worker, image tag pinned to reviewed code, mode600 env, no published ports, read-only root/tmpfs, dropped capabilities, one CPU/512MiB/PID cap, bounded logs and heartbeat health. Its ongoing authorized behavior is polling this backend's private journal queue, normalizing images and reconciling exact eligible orphan/raw paths under ADR-0005; it does not scan unrelated buckets/services. Verify the image/labels/limits/network/mounts, initial heartbeat and healthy/idle polling. Do not modify existing Supabase/Portainer/Cloudflare resources. No user-facing ingress is added.
9. Run read-only health and final integrity checks. Expect the original account/catalog/root unchanged, zero test trips/graphs/journals/jobs/receipts/objects and exactly two new empty private buckets, with seven applied migrations. Existing 11 Supabase container IDs/start times must be unchanged and healthy; the new media worker is separately healthy. Inspect and remove only the isolated test container, close only the owned tunnel, retain private backups/results and remove temporary local diagnostics that could contain secrets.
10. Record actual evidence/limitations in the repo and only then open one new review PR for this complete backend batch. No merge is included.

## Risk, downtime and rollback

This adds graph/discovery/edit/private-journal schema, immutable private receipts/previews, two private Storage buckets/policies and one ongoing image worker. It changes the maintenance boundary for graph-affecting fields and pins device-location/album behavior to the explicit selected development policy. Existing zero app-data state limits backfill, but DDL locks/build/polling load can affect latency. No Supabase restart or planned downtime; the worker is a new separate service.

Initial technical limits (GPS/time/size/dimensions/rate) need device/field tuning. The worker uses a broad server-only service role because it spans Auth-protected Storage and SQL jobs; isolation/private env and denied client worker RPCs are mandatory. No promise of unforgeable GPS or image authenticity, completed/skip policy, native integration, production capacity, scheduled/off-host disaster recovery or full object-service restore is made.

Stop before shared application on failed CI/restore/backfill/schema tests. On a partially applied migration prefix, retain backups and official history, stop further apply and re-plan; do not write fake receipts. On post-commit validation failure, stop new C67 writes/worker startup, retain diagnostics and assess exact data. Do not automatically DROP schemas/buckets/objects, delete history, prune resources or restore over shared data. A destructive rollback needs its own current-data plan. If only the new worker fails, it may remain stopped with its private files/backup intact; do not restart the Supabase stack to repair it.

## Approval boundary

Approval requested: new exclusive private backup; exact isolated restore/backfill/SQL fixtures/container cleanup; source/image build and private env installation for new c67-media; the four official migrations/two private buckets/cache refresh; bounded synthetic Auth/API/Storage/worker acceptance and exact cleanup; startup/verification of the single ongoing media worker. This supersedes graph-only scope and does not authorize other product features, public publishing, network/control-plane changes or a merge.

The [homelab-ops skill](/Users/giovan/.codex/skills/homelab-ops/SKILL.md) requires a fresh preflight and separate explicit approval of the exact operations. The prior approval covered stage 3A, and closing PR #4 did not approve these newly defined runtime/bucket writes. Finish all reviewable source/CI work before asking.

## Reviewed implementation inputs

Final source/test/image/lockfile hashes are appended after the final implementation checks, before execution. No write is authorized by a plan with missing/stale hashes.
