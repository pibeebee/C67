# Homelab backend completion plan (stages 3B–7)

Status: Explicitly approved by Giovan and executed through final verification/cleanup. See [actual results](homelab-backend-completion-verification.md). Reviewed scope and source hashes below are retained.
Date: 26 October 2026 (Asia/Jakarta).

This replaces the earlier unexecuted graph-only plan. Giovan requested completing the entire agreed backend batch before opening a PR. Product decisions are recorded in ADR-0005; they do not by themselves approve the exact additional shared tables/buckets/worker operations below.

## Fresh read-only preflight

Target: SSH homelab; external Compose project supabase under `/home/giovan/apps/supabase`, docker-compose.yml plus docker-compose.cf-tunnel.yml. Database supabase-db/postgres remains PostgreSQL 17.6 on image `sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00`; its ports are unpublished and only network is supabase_default. Storage image is supabase/storage-api:v1.81.0. All 11 services are healthy.

Storage-policy privilege audit: existing postgres has bucket INSERT/SELECT and CREATE-schema privileges but is not a member of the storage.objects owner (supabase_storage_admin). The existing supabase_admin role is a login superuser; its loopback TCP login was verified read-only using the existing container secret. No role/grant/password change was made. Therefore this batch must use the existing supabase_admin migrator for the four official migrations; do not attempt to weaken table ownership/grants to make postgres work. Audit explicit actor checks/execute grants on resulting definer functions in the matching-image gate.

Shared data: one original Auth account, one catalog version/root, zero trips, zero buckets/objects, three public tables. Official history is exactly 20261023030149, 20261023100158 and 20261023163029. Graph tables are absent. Root free space 63.1 GiB, available RAM 10.6 GiB. Proposed worker directory/project, isolated container name and backup destination are unused. Recheck these facts, manager/labels, capacity, source hashes, private original-record fingerprints and service IDs/start times immediately before writes. Stop/re-plan on unexpected drift.

## Exact write scope and sequence

1. Require passing final implementation CI (database, API/Storage/worker, container smoke, contracts, style and iOS). Keep PR #4 closed. Capture original Auth/catalog/root/Storage fingerprints privately, without personal output.
2. Create exclusively `/home/giovan/backups/c67/2026-10-26-before-backend-completion`, mode 700/files 600; preserve all older backups. Use the reviewed backup tool for postgres/_supabase dumps, roles without passwords, protected config and Storage archives; validate SHA256SUMS and archive readability. This is a same-host recovery point, not off-host disaster recovery. With no existing bucket/object/trip, the current app-data recovery baseline is explicit.
3. Create only c67-db-verify using the exact existing PostgreSQL image, no network/ports/production mounts, read-only root, tmpfs data, user 100:101, one CPU/2GiB, shm128MiB/no-new-privileges. Restore both databases/roles/owners/grants with the proven supabase_admin bootstrap, clone-only operator and explicit database-owner procedure. Keep original dumps untouched.
4. In the isolated clone only, provision one synthetic compatibility account with persisted V1 and V2 trips whose saved stops differ from current source. Capture original responses, ownership/request/revision. Apply the four pending migrations as the existing supabase_admin migrator in order, without seed replay; prove backfilled graphs use saved JSON/unknown historical route facts, v1/v2 payloads and receipt retries survive later edits, and cleanup restores original records. Run all SQL suites and schema/grant/RLS checks. Stop before shared application on restore/backfill/test failure.
5. Provision a new private build directory `/home/giovan/apps/c67-media` (700). Copy only reviewed worker/deploy source/lockfiles, no local node_modules/env/secrets. Build the pinned Node22/sharp image as `c67-media:<reviewed-revision>` on the homelab. The Dockerfile base digest and npm lockfile are pinned; memory/CPU/runtime restrictions are in Compose. Obtain the existing service-role key from the homelab process configuration into a new private mode600 env file; never print/paste it or put it into image/build args. HTTPS origin stays https://supabase.mrt.qzz.io. Do not start the continuous worker before the explicit acceptance suite to avoid competing claims.
6. Use pinned Supabase CLI 2.121.0 as the existing supabase_admin migration account through an owned Mac-loopback SSH tunnel to the freshly resolved internal DB IP/5432. Password stays in memory/subprocess environment only. Dry-run must show exactly these pending versions:
   - 20261024002359_normalize_trip_graph
   - 20261026012332_add_discovery_search
   - 20261026012334_add_trip_edit_receipts
   - 20261026012335_add_private_journal_pipeline

```sh
./node_modules/.bin/supabase db push --db-url 'postgresql://supabase_admin@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --dry-run
./node_modules/.bin/supabase db push --db-url 'postgresql://supabase_admin@127.0.0.1:55432/postgres?sslmode=disable' --skip-vault --yes
```

No include-seed flag or shared reset. The CLI may commit migrations separately: record the actual applied prefix if a later migration fails; do not claim atomicity across all four files. Send NOTIFY pgrst, 'reload schema' without Supabase restart. Verify all seven official versions, new tables/RLS/receipts, private bucket limits/policies and worker-only privileges.

7. Run the existing expanded homelab suite and then the completion suite with `--approved-shared-test`, sequentially. Authorize only their uniquely tagged synthetic accounts/fixtures, exact retry/patch operations and cleanup:
   - Existing suite: two temporary confirmed users, fifteen trips, one unpublished and two synthetic published route versions/their own roots, derived graph rows; patch only the newly created route fixture.
   - Completion suite: two different temporary users, two new synthetic published route versions/roots, one trip with explicit title/reschedule/append/retain choices and concurrent revision attempts, up to ten exact test previews and seven immutable creation/apply receipts, two upload sessions/raw objects (one valid generated PNG and one fake PNG), one processed JPEG and one accepted private journal. It also deliberately expires only its own claimed test lease/session via admin API to prove recovery/no second location gate. Never patch the original catalog/account or unfamiliar jobs.
   - Run manual worker validation for only these jobs using the reviewed source/image and private process env. Repeated/stale calls must not duplicate journals. Exercise raw/ready privacy and failed-image rejection. Cleanup removes exact temporary users/cascading graph/journal/receipt records, their known versions/roots, and worker candidate bytes through Storage API before SQL purging. No SQL deletion of storage.objects. Inspect absence through API/database privately. If preflight discovers existing non-test worker jobs, stop and re-plan rather than process them as acceptance fixtures.
8. Start the new external Compose project c67-media with only its one worker, image tag pinned to reviewed code, mode600 env, no published ports, read-only root/tmpfs, dropped capabilities, one CPU/512MiB/PID cap, bounded logs and heartbeat health. Its ongoing authorized behavior is polling this backend's private journal queue, normalizing images and reconciling exact eligible orphan/raw paths under ADR-0005; it does not scan unrelated buckets/services. Verify the image/labels/limits/network/mounts, initial heartbeat and healthy/idle polling. Do not modify existing Supabase/Portainer/Cloudflare resources. No user-facing ingress is added.
9. Run read-only health and final integrity checks. Expect the original account/catalog/root unchanged, zero test trips/graphs/journals/jobs/receipts/objects and exactly two new empty private buckets, with seven applied migrations. Existing 11 Supabase container IDs/start times must be unchanged and healthy; the new media worker is separately healthy. Inspect and remove only the isolated test container, close only the owned tunnel, retain private backups/results and remove temporary local diagnostics that could contain secrets.
10. Record actual evidence/limitations in the repo and only then open one new review PR for this complete backend batch. No merge is included.

## Risk, downtime and rollback

This adds graph/discovery/edit/private-journal schema, immutable private receipts/previews, two private Storage buckets/policies and one ongoing image worker. It changes the maintenance boundary for graph-affecting fields and pins device-location/album behavior to the explicit selected development policy. Existing zero app-data state limits backfill, but DDL locks/build/polling load can affect latency. No Supabase restart or planned downtime; the worker is a new separate service.

Initial technical limits (GPS/time/size/dimensions/rate) need device/field tuning. The worker uses a broad server-only service role because it spans Auth-protected Storage and SQL jobs; isolation/private env and denied client worker RPCs are mandatory. No promise of unforgeable GPS or image authenticity, completed/skip policy, native integration, production capacity, scheduled/off-host disaster recovery or full object-service restore is made.

Stop before shared application on failed CI/restore/backfill/schema tests. On a partially applied migration prefix, retain backups and official history, stop further apply and re-plan; do not write fake receipts. On post-commit validation failure, stop new C67 writes/worker startup, retain diagnostics and assess exact data. Do not automatically DROP schemas/buckets/objects, delete history, prune resources or restore over shared data. A destructive rollback needs its own current-data plan. If only the new worker fails, it may remain stopped with its private files/backup intact; do not restart the Supabase stack to repair it.

## Approval boundary

Approval requested: new exclusive private backup; exact isolated restore/backfill/SQL fixtures/container cleanup; source/image build and private env installation for new c67-media; the four official migrations/two private buckets/cache refresh using the verified existing supabase_admin account (no new grants/roles); bounded synthetic Auth/API/Storage/worker acceptance and exact cleanup; startup/verification of the single ongoing media worker. This supersedes graph-only scope and does not authorize other product features, public publishing, network/control-plane changes or a merge.

The [homelab-ops skill](/Users/giovan/.codex/skills/homelab-ops/SKILL.md) requires a fresh preflight and separate explicit approval of the exact operations. The prior approval covered stage 3A, and closing PR #4 did not approve these newly defined runtime/bucket writes. Finish all reviewable source/CI work before asking.

## Reviewed implementation inputs

Reviewed source checkpoint: c55aef6. Source hashes below pin the migration/test/contract/runtime inputs; documentation-only evidence commits may follow. Execution must recheck all hashes and require successful final CI before any write.

```text
fdf59616474cb8bf323ce9e7bc34febbbfa3bda77ccb23d371446beaa63528f6  server/supabase/migrations/20261023030149_starter_rundowns_and_trips.sql
078a973b101e278c160ec61a2aaad152bb8c2e811827a1bc42576e4a12efe6de  server/supabase/migrations/20261023100158_add_private_trip_reads.sql
1809f92aee9d92b1a813c3dec5090e55eb284fae7eaf2166fbcc5adcab1eea66  server/supabase/migrations/20261023163029_add_trip_model_foundation.sql
5304b9c27a33e9e88b85e72b3134c3c5e882bd651b4943f63d531d3bdceaaa2d  server/supabase/migrations/20261024002359_normalize_trip_graph.sql
682c9dcb15c54ddf9c47241668008c8aba0a5ed326f5546d7b3f8a1d8c255c15  server/supabase/migrations/20261026012332_add_discovery_search.sql
ed74480d32721ac8ceff05d08df1342e5e594c29b73b078f658dfa4151b4f80d  server/supabase/migrations/20261026012334_add_trip_edit_receipts.sql
1442abb1b9cbe8f2b9a4477abb76031b41a3bb2c9ae047afbd287859f1ca50f7  server/supabase/migrations/20261026012335_add_private_journal_pipeline.sql
bf85292517e2f9bf070e1ac2afb746372dd4ca49649943e5795d49fe5c2554e8  server/supabase/tests/backend_completion.test.sql
0d624706223585ac8b856e81288ff70c90e185839598cc7f10ce662f8f32a824  server/supabase/tests/starter.test.sql
f08958b62013c44bddd2cf968d3ac3902c1b76b1bb40a5afd1dd7660071b89b5  server/supabase/tests/trip_graph.test.sql
f8c2287172aa06ccb8daa6f9172d3101bf0e79995d2d2419892d081e84a29ae1  server/supabase/tests/trip_model.test.sql
59f305468f384180b82a7cc9886696c5d0b68d3e651853bf33f8d1a8ef58b34a  server/supabase/tests/trip_reads.test.sql
764ae2f0165fd83d48d57e2ae8e104c274739e4f6c577d735996a9c1a5313bb7  contracts/api/openapi.json
a8794cc43b42c79eee0c116cc6321d89e573db4cddc7a27624aefd3976b5a6f4  contracts/fixtures/route-template-separate.json
24450082a7a3ad14cefcca554905b446ee27a3fd55cc805545e68317c93456ed  contracts/fixtures/route-template-first-stop.json
5ad85d5ca4e22a4134532f9115b836750ab3d1e9390522880fdabc88550a55e3  server/scripts/test_local_api.py
efba48da4209698dab5fa966b6ca0cf601a58cd96831a6e9d2846d215e835bf3  server/scripts/test_homelab_api.py
b08db36117d4d45d699b4227db2adcf589c32563d17fd74f4237cfc95685610e  server/scripts/test_backend_completion.py
ccd1a93ff49ba907491660e37876bf160c10de4d3ba761a4081bd122e2c893d4  server/scripts/ops_status.py
24a0e6aa54c84c189e941ae636af7f0209de2a914be6e1dbc4b0712730113aa8  server/scripts/backup_homelab.py
a115c683219a09b4a4aed933fec5cce69e79275345d01bee0d2730309cdd4204  server/scripts/test_worker_container.py
324f60323713d4813c232e0456eb13fe721c34fb5d14bb92a40fb22c10be07b7  server/workers/media/image.mjs
445708c00b2d72ae797f1c9445704b56437a21dc1b7dba98bd43b0d572fa4d35  server/workers/media/worker.mjs
1b6f6005b16a4bd064462797c0ae5b123570a8cb29fb6c03954e9067319d0e09  server/workers/media/Dockerfile
0a53fbed1414715bd5fe5e43500135cb9042e09440c79adda8ea369eef95a67b  server/workers/media/package.json
67c54e2a0ac16cf1f16d0cef2b009934d1dee1738ca0a54de138853de6c6214c  server/workers/media/package-lock.json
57cdf084abb13d4187efef4574da0adecb86aa66f41ee7be41f35982a01540a6  server/deploy/media-worker.compose.yml
```

Execution adjustment: shared Storage requests from Python-urllib were rejected by the existing Cloudflare Browser Integrity Check (1010); read-only comparison proved C67-Approved-Verification/1.0 and the worker client succeed. The binary acceptance client now uses the same truthful C67 User-Agent as its already-reviewed JSON client. Only the test input hash above changes; migrations, worker image, gateway and Storage policy are unchanged.
