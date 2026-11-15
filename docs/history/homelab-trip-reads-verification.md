# Homelab private trip reads: verified

Date: 23 October 2026 (Asia/Jakarta). Giovan explicitly approved the [concrete plan](homelab-trip-reads-plan.md). Execution completed through cleanup. No service restart, shared reset or seed reload was performed.

## Inputs and environment

The implementation is `fa274b1`; documentation checkpoint `4a425bb` passed all four [CI jobs](https://github.com/pibeebee/C67/actions/runs/39937821831): database, contracts, style and iOS. CI verified 40 pgTAP assertions, SQL lint and 39 local HTTP checks on disposable PostgreSQL 17.11. This execution separately tested the actual homelab PostgreSQL 17.6 image.

Shared target: SSH `homelab`, external Compose project `supabase`, container `supabase-db`, database `postgres`. Its image remained `sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00`. Preflight rechecked Compose ownership/configuration validity, health, database port isolation, available capacity, source hashes and the baseline. There was one existing Auth user, two public tables, one synthetic catalog version, zero trips and only starter migration `20261023030149`.

Applied migration: `server/supabase/migrations/20261023100158_add_private_trip_reads.sql`, SHA256 `078a973b101e278c160ec61a2aaad152bb8c2e811827a1bc42576e4a12efe6de`. The exact implementation/test hashes in the approved plan matched before execution.

## Backup and isolated restore gate

A new private recovery point was created exclusively at `/home/giovan/backups/c67/2026-10-23-before-trip-reads`. It contains custom-format dumps of `postgres` and `_supabase`, roles without passwords, protected configuration and storage archives, SHA256SUMS, and private baseline/result records. Directory mode is 700; every file is 600. Archive readability and checksums were verified, including a final checksum recheck. The earlier foundation backup was preserved.

Both databases were completely restored, preserving roles/owners/grants, into `c67-db-verify` on the exact shared image. Isolation: no network or ports, read-only root, tmpfs-only data, no production mounts, user 100:101, 2 GiB RAM, one CPU and no-new-privileges. The corrected `supabase_admin` bootstrap and explicit database-owner procedure from the foundation verification worked without repair. The original Auth fingerprint, catalog fingerprint, counts and migration history matched the backup baseline.

Only the new migration was applied to the clone in one transaction; the starter migration and seed were not rerun. Both pgTAP suites passed: **40/40 assertions**. RLS, five RPCs, the finite-start constraint, index validity and authenticated/anonymous execute permissions were verified. All synthetic SQL tests rolled back. The shared baseline remained unchanged throughout this gate.

## Official migration and real HTTP verification

Supabase CLI 2.121.0 ran through a process-owned SSH tunnel bound only to Mac loopback. The dry-run identified exactly `20261023100158`; the apply succeeded without `--include-seed`. Passwords stayed in process memory and subprocess environment. The tunnel was closed. `NOTIFY pgrst, 'reload schema'` refreshed the Data API without a restart.

Official migration history now contains exactly `20261023030149` and `20261023100158`. Both new RPCs are stable security-invoker functions. RLS remains enabled, anonymous execution is denied, authenticated execution is granted, and the new index/constraint are valid.

The separately approved homelab HTTP runner passed **40/40 checks** against the HTTPS endpoint with strict TLS and expected-origin guards. Two temporary confirmed accounts were provisioned without email; actual password/refresh sessions exercised ownership. Checks included:

- Empty/default owner lists and complete stored snapshot responses.
- Start-time/UUID ordering, stable repeated pages and traversal without gaps/duplicates at tied timestamps.
- Cross-account cursor rejection, malformed/incomplete/invalid-UTF8/oversized cursor rejection, and invalid/null limits/IDs.
- Uniform 404s for foreign and missing detail, owner-only results, and non-finite start rejection.
- Existing catalog visibility, private-session requirements, copy behavior, retries/conflicts, four concurrent retries, denied direct writes and refresh access.

The two users, their five trips and one temporary unpublished catalog row were removed. The original account identity and catalog fingerprint were unchanged; only one Auth user and one catalog row remain, with zero trips. The isolated container ID/label/mount/network guards were checked before stopping/removing that exact container. All 11 shared services are healthy; PostgreSQL remains unpublished on `supabase_default`. No rollback was needed. A safe final report is retained in the private backup directory.

## Boundaries and next owner

The shared server now supports both private trip reads. Native Swift repository/mock methods, login/session storage and UI integration remain separate work for the iOS data owner; deployed RPC success does not demonstrate on-device integration. This verification does not establish load capacity, full timezone/revision behavior, expired-token handling or field usability. Backups are same-host logical recovery points, not off-host disaster recovery or a scheduled backup system.
