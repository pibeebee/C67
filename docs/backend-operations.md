# Backend operations and recovery

The backend remains Supabase Auth/PostgreSQL/RLS/RPC/Storage plus one private image worker. Shared writes follow the concrete reviewed homelab plan. Use existing external Compose ownership under `/home/giovan/apps`; never reset shared data or replace Portainer-managed resources from this runbook.

## Safe inventory and health

From the repository root, `.venv/bin/python server/scripts/ops_status.py --homelab` is read-only and prints only health/schema presence. It checks strict HTTPS origin/TLS and never prints credentials, session bodies, account IDs or private album records. A changed Auth baseline triggers a preflight review rather than deleting unfamiliar accounts. Local CI runs the same read-only checks against loopback.

Inspect Compose labels/path, images, health, network/ports and ownership through SSH before any mutation. The media project is separate from Supabase; it publishes no ports. Inspect only its exact container after deployment. Its health check requires a successful polling/cleanup heartbeat within three minutes. Container ID/start time changes in the Supabase project are unexpected for a schema/worker deployment.

## Worker failure

A sanitized cycle error means that iteration failed; it is not proof of data loss. Inspect worker health and bounded sanitized logs, API health and queue counts. Never dump env, container commands with credentials, response bodies or private input data. Verify the worker has the server-only service role, correct HTTPS origin, compatible image/CPU resources and Storage reachability.

A processing lease expires after two minutes; the next worker can reclaim it, up to five attempts. A stale lease cannot finalize. A committed processed object may remain after a crash; deterministic create-only retry compares bytes before reusing it. A job committed ready before raw deletion is reconciled by the raw-cleanup query. Exhausted jobs become cleanup candidates after lease expiry, leaving no falsely accepted journal. Diagnose repeating errors before restarting any resource.

To stop/restart a worker, review its exact ID/manager and obtain approval of the scoped action. Do not restart the entire Supabase stack to repair an image decoder. The production Compose restricts memory/CPU/PIDs, capabilities, filesystem and log growth. A real queue/load budget must be measured before public use.

## Private object and account cleanup

Client raw access is insert-only for the exact unexpired session path. Processed reads require an accepted owner journal. No public bucket or permanent signed URL is generated. Session metadata is not directly client-readable. Location/sample is evaluated once before upload; raw coordinates are not persisted.

Worker cleanup deletes exact candidate paths through Storage's API and then purges the SQL job row. Never DELETE storage.objects via SQL: those rows are metadata, not the bytes. User/trip removal or a rejected/expired session is reconciled through the same queue. Rejected/expired owned sessions have a 24-hour grace; unowned jobs can be cleaned immediately. Off-service private copies/downloads cannot be revoked remotely.

## Backup and restore

`server/scripts/backup_homelab.py --approved-backup --name <new-reviewed-name>` implements an exclusive private same-host backup. Authorization is required before running it. It records postgres/_supabase custom dumps, roles without passwords, configuration and Storage archives, with mode 700/600 and SHA256SUMS. It never overwrites an existing backup and does not restore to shared data. Review capacity and avoid concurrent application writes when a consistent cross-database/Storage recovery point is required; pg_dump alone is not atomic across Storage and databases.

The deployment gate restores both databases/roles/owners/grants on the exact image with no network/production mounts. Use the proven supabase_admin bootstrap, clone-only operator and explicit database owners. Exercise persisted creation/backfill/receipt behavior, rollback SQL tests and compare original fingerprints. Database restore and file archive readability do not establish successful full object-Storage service recovery; record that additional layer separately.

Backups are presently same-host recovery points. Scheduled/off-host destination, encryption/key ownership, retention and RPO/RTO need actual configured storage and an approved operational schedule; do not claim them from this tool. No cron or recurring Codex automation is created by this runbook.

## Migration and rollback gates

Check exact hashes, main/branch history, shared schema and data before applying. For this Storage-policy batch, use the existing verified supabase_admin migration account: postgres is not the storage.objects owner/member. Do not grant new ownership/role permissions just to bypass this boundary. Use the pinned official CLI through an owned loopback SSH tunnel; secrets stay in process environment/memory. Require the exact pending migration list, no seed reload, and schema-cache NOTIFY without restart.

After application run real Auth/API/Storage/worker acceptance with only approved synthetic accounts/fixtures and exact cleanup. Verify original records and migration history, private bucket policies, object absence after cleanup and service IDs/health. No merge occurs as an incidental deployment step.

A failed isolated restore/test gate stops shared application. A failed migration must not receive a fake history receipt. If post-commit validation fails, stop new C67 writes and retain diagnostics/backup. Never automatically DROP graph/journal data, remove history, prune resources or restore over the shared instance; review a concrete rollback against current data first.

## Deployed baseline — 26 October 2026

[Execution evidence](homelab-backend-completion-verification.md) records seven migration versions, two private buckets, one healthy c67-media worker and the unchanged 11-service Supabase project. The worker release/env is under `/home/giovan/apps/c67-media/release/server/`, image tag c67-media:e32e283. The latest private recovery point is `/home/giovan/backups/c67/2026-10-26-before-backend-completion`. Future lifecycle changes still need a current scoped preflight/approval.
