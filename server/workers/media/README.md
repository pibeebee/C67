# Private media worker

Node 22 + locked sharp/libvips worker; no HTTP listener. The production Docker image includes only runtime dependencies. All credentials stay in server-only environment variables. Do not use an anon/client key as a worker credential or print service JWTs.

```sh
npm ci --ignore-scripts
npm test
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node worker.mjs --once
```

The last example is illustrative: load private env/process configuration rather than entering a real key into shell history. `--once` claims at most one queued job and performs eligible cleanup. Continuous mode polls every five seconds, renews its health marker only after a successful cycle and prints only sanitized failure messages.

Raw JPEG/PNG must be ≤5MiB and decode within 20MP/20 seconds; processed JPEG fits 2048×2048, auto-rotated, EXIF stripped. Rejecting input is separate from accepting a journal. Failed network/Storage calls retain the lease for bounded recovery; a stale lease cannot finalize a journal. Storage IO happens outside database locks. Output retries cannot overwrite a different processed object.

Cleanup processes only SQL-provided exact candidate paths, deletes through the Storage API, and only then purges eligible session rows. Committed journals with leftover raw input get reconciled. Removed accounts/trips make jobs eligible for byte cleanup. A rejected/expired owned session is retained for 24 hours for client status/recovery. No SQL mutation of storage.objects is used.

See [ADR-0005](../../../docs/decisions/0005-backend-mvp.md), [operations runbook](../../../docs/backend-operations.md) and the separately approved deployment plan. Local acceptance does not authorize running this worker on a shared service.
