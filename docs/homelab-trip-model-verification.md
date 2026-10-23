# Homelab trip model foundation (stage 3A): verified

Date: 23 October 2026 (Asia/Jakarta). Giovan separately approved the [exact plan](homelab-trip-model-plan.md); execution completed through cleanup. No rollback was needed.

## Reviewed inputs and preflight

Implementation `d9d90f3` and documentation checkpoint `c9164b4` passed all four CI jobs (database, contracts, style and iOS), including [run 39989113194](https://github.com/pibeebee/C67/actions/runs/39989113194). The disposable CI stack passed 79/79 pgTAP assertions, SQL lint and 54/54 HTTP checks. This execution separately verified PostgreSQL 17.6 on the homelab's exact image.

Target: SSH homelab, external Compose project supabase under `/home/giovan/apps/supabase`, database supabase-db/postgres, image `sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00`. Preflight rechecked manager/configuration validity, health, capacity, unpublished database ports and the approved baseline: one Auth account, one catalog version, zero trips, two public tables and two official migration versions. All source hashes matched the plan.

Applied migration: `20261023163029_add_trip_model_foundation.sql`, SHA256 `1809f92aee9d92b1a813c3dec5090e55eb284fae7eaf2166fbcc5adcab1eea66`.

## Backup, restore and real legacy backfill

Created exclusively `/home/giovan/backups/c67/2026-10-23-before-trip-model`, mode 700 with all files 600. It contains postgres/_supabase custom dumps, roles without passwords, protected configuration/storage archives, SHA256SUMS and private baseline/gate/final reports. Both older recovery points remain. Archive readability and checksums were verified; final checksums/permissions also passed. This remains a private same-host logical backup, not scheduled or off-host disaster recovery.

Restored both databases with roles/owners/grants into c67-db-verify on the exact shared image. The corrected supabase_admin bootstrap, clone-only restore operator and explicit database owners worked. The container had no network/ports/production mounts, read-only root, tmpfs-only data, user 100:101, 2 GiB RAM, one CPU and no-new-privileges. Original Auth and catalog-content fingerprints, counts and migration history matched the backup.

Before applying the new migration in the clone, inserted one synthetic Auth account and a genuinely persisted legacy trip with copied title/stops distinct from the source. After migration, verified:

- Exact v1 snapshot, owner and request identity were unchanged.
- Legacy creation retry returned that same stored snapshot.
- Zone/date stayed null, revision was 1 and status planned.
- Source attribution gained a valid separate root, original version ID and version number 1.
- That exact compatibility account/trip was removed and original clone counts/fingerprints restored.

Then ran all three rollback-based pgTAP files: **79/79 assertions passed**. Three-table RLS, seven application RPCs, root/source constraints, index, execute grants and protected trigger helpers were verified. Tests rolled back. The shared database remained unchanged until this complete gate passed.

## Shared deployment and HTTP verification

Pinned Supabase CLI 2.121.0 ran through an owned loopback SSH tunnel with passwords only in process memory/environment. Dry-run identified exactly the new migration; apply succeeded without seed reload. The tunnel was closed. A PostgREST schema-cache notification made the new RPCs available without restart.

Official history now has exactly 20261023030149, 20261023100158 and 20261023163029. Original catalog content remains unchanged, with one newly generated root and version number 1. Source constraints are valid; create_trip_v2 is a protected definer command and get_trip_snapshot_v2 is a stable invoker read. Anonymous V2 execution and direct client root writes are denied; authenticated execution is granted.

The approved HTTPS runner passed **55/55 HTTP checks** with strict TLS/origin guards. Two temporary confirmed accounts obtained actual password/refresh sessions without sending email. Tests covered the existing APIs plus UTC/destination date boundaries, New York DST instants, legacy null-zone reads, V2 source/revision projection, changed-zone/API-generation conflicts, four concurrent V2 retries, direct-write denial and cross-account privacy.

Cleanup removed both temporary users, their eleven trips, the unpublished version and its own generated root (after checking no other version referenced it). The original Auth identity remains; final counts are one Auth user, one catalog version, one root and zero trips. The catalog's complete post-migration attribution/content fingerprint is unchanged by testing.

The isolated container ID/label/mount/network guards were checked before stopping/removing only that container. All **11 services remain healthy**, and every shared container ID/start time matches preflight. PostgreSQL stays unpublished on supabase_default. A private final-verification.json records the safe result. Temporary local CLI diagnostic files were removed.

## Remaining scope

Stage 3A is implemented, deployed and verified. Stage 3B still needs normalized stop/day/source and explicit origin → landing → first-stop → following-stop legs. No native V2 integration, client edit command, expected_revision enforcement, immutable edit receipt, lifecycle transition, publishing/rights policy or full field usability is claimed. Revision metadata alone does not prove optimistic concurrency or retry-after-edit support; see [ADR-0003](decisions/0003-trip-model-foundation.md).
