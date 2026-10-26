# Backend stages 3B–7: shared verification complete

Date: 26 October 2026 (Asia/Jakarta). Giovan explicitly approved the [consolidated operational plan](homelab-backend-completion-plan.md). Execution completed through backup/restore/backfill, four official migrations, real HTTPS/Storage/worker acceptance, cleanup and restricted continuous worker startup. No rollback was needed. This completes the agreed server slice in ADR-0005; it does not implement native app integration or production field validation.

## Inputs and successful gates

The reviewed source checkpoint c55aef6 and documentation checkpoint e32e283 passed all four CI jobs; [run 40256508924](https://github.com/pibeebee/C67/actions/runs/40256508924) verifies the latter. Actual disposable results: 167/167 SQL assertions, clean public-schema lint, 66 retained HTTP checks, 16 complete-backend checks, two image-decoder tests, read-only health and production Docker image smoke under filesystem/resource restrictions. Runtime npm audit reported zero known vulnerabilities. No Mac Docker was started.

Source hashes in the plan matched before execution. The one subsequent source adjustment is the acceptance binary client's truthful C67 User-Agent (548158b), matching the already-used JSON client's header. SQL migrations, contracts and worker image did not change during deployment. Its updated test hash is recorded in the plan.

Shared target: external Compose supabase under `/home/giovan/apps/supabase`, database supabase-db/postgres, PostgreSQL 17.6 image `sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00`. Preflight found 11 healthy unchanged services, Storage v1.81.0, one existing Auth account/catalog/root, no trips/buckets/objects and exactly three migrations. New media directory/project and isolated test name were unused.

The existing postgres account had bucket INSERT/SELECT but did not own storage.objects. Existing supabase_admin superuser login was verified read-only and used as the migration account, including in the isolated gate. No shared role, password or ownership grant was changed to obtain access.

## Private recovery point and matching-image restore

Created exclusively `/home/giovan/backups/c67/2026-10-26-before-backend-completion`, directory 700, every file 600. It contains postgres/_supabase custom dumps, roles without passwords, protected config/Storage archives, SHA256SUMS and private gate/build/final reports. Previous backups remain intact. Archive readability, final checksums and permissions pass. This is a private same-host logical recovery point, not off-host/scheduled disaster recovery or a full object-service restore.

Restored both databases with roles/owners/grants into c67-db-verify on the exact shared image. Isolation: no network/ports/production mounts, read-only root, tmpfs data, user 100:101, one CPU/2GiB, shm128MiB/no-new-privileges. The proven supabase_admin bootstrap, clone-only restore operator and explicit database owners worked.

Inserted only a synthetic compatibility account and persisted pre-graph V1/V2 trips with copied stops distinct from the current source. Applied the four new migrations as supabase_admin. Verified unchanged old responses, owner/request/revision, saved historical graph values and unknown route facts, stable occurrence IDs, and permanent original creation retries after later edits. Removed the exact compatibility records and compared the original fingerprints/counts. All five rollback SQL suites passed **167/167 assertions**; RLS, private buckets/Storage policies, denied client worker access and private receipt-schema grants passed. The shared baseline remained unchanged until this entire gate completed.

## Official application and edge adjustment

Pinned CLI 2.121.0 ran through an owned loopback SSH tunnel with the existing password only in process memory/environment. Dry-run identified exactly the four approved versions; apply succeeded without seed reload/reset. A schema-cache notification refreshed PostgREST without restarting any Supabase container. The tunnel was closed.

Official history now contains exactly:

- 20261023030149 — starter
- 20261023100158 — private reads
- 20261023163029 — destination model
- 20261024002359 — normalized graph
- 20261026012332 — discovery
- 20261026012334 — edit receipts
- 20261026012335 — private journal pipeline

The retained HTTPS suite passed **67/67 checks** with the original account preserved. The completion suite initially failed before Storage: Cloudflare returned plain-text 403/code1010 to Python-urllib. Cleanup passed after every failed attempt. Read-only comparison showed the same endpoint returned 200 for the C67 verification/worker clients. The binary client now sends the same truthful C67 User-Agent as the JSON suite; no Cloudflare/gateway/policy configuration was changed. This is consistent with [Cloudflare's documented 1010 browser-signature boundary](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/error-1010/).

The complete HTTPS suite then passed **17/17 checks**. Total final shared acceptance: **84 checks**. Evidence covers discovery cursor filters, owner/revision edit races, reschedule root/day/date consistency, explicit append/retain overlap choices, permanent receipts after edits/journals, session-start reported location, pending-plan protection, raw/processed object privacy, leased worker recovery after delay, stale finalization denial, accepted private JPEG/journal/album and fake-image rejection. All test images/locations were synthetic; device-location truth and photo authenticity are not certified.

## Worker and final integrity

Built pinned source as c67-media:e32e283 under new private `/home/giovan/apps/c67-media`. The deployed worker source is unchanged by the acceptance-header fix. The official Node22 base digest and npm lockfile are pinned. Image ID: `sha256:091386f17d14a22a86984a64db0001c1224a2702bb072877b64c4835dc3f8db7`. Server-only env is mode600, outside image/build context. The continuous worker remained stopped while manual acceptance used exact synthetic upload IDs, avoiding queue races or unrelated jobs.

After cleanup, started only external Compose c67-media's one worker. Heartbeat is healthy. Live inspection verified exact image, read-only root/tmpfs, no production bind mounts or published ports, all capabilities dropped/no-new-privileges, one CPU/512MiB/PID128 and its own c67-media_default network. Existing 11 Supabase container IDs/start times are unchanged and all healthy; PostgreSQL remains unpublished on supabase_default. Read-only API health passed.

Final verified data: one original Auth account, one original catalog version/root, zero trips/sources/days/stops/legs/journals/uploads/receipts/previews, zero Storage objects, and two empty private journal buckets. Original Auth/catalog/root fingerprints match. Exact synthetic accounts/fixtures/objects were removed through the approved APIs; Storage bytes were deleted through Storage API before session purge, never SQL deletion of storage.objects. The isolated container's ID/label/mount/network were checked before removing only it. Backups/results remain private; temporary local CLI diagnostics were removed.

## Handoff and limits

The agreed server batch is deployed and verified. One new review PR is prepared only after this verified execution, preserving closed PR #4 and branch history; no merge is authorized by deployment. The iOS data owner can adopt the documented discovery/graph/edit/upload/album contracts and keep existing callers compatible. See [ADR-0005](decisions/0005-backend-mvp.md) and [operations](backend-operations.md).

The selected scope is curated catalog, private albums, location at upload-session creation, planned-only editing/merge and protected pending/accepted journal plans. No public creator publishing, completed/skip/ended_early lifecycle, route optimizer/provider integration or native authentication/HEIC conversion is claimed. Physical iPhone/field GPS, adversarial sensor authenticity, queue/load capacity, scheduled/off-host backup, RPO/RTO and full Storage service restore remain separate evidence. Initial GPS/time/size/rate limits are development defaults to be tuned from device/field results.
