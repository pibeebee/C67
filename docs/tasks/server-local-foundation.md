# Task: Verify the local backend foundation

Status: Ready for review
Owner: Giovan
Reviewers: To be assigned before opening a PR
Branch: gi/server-local-foundation

## Outcome

The existing Supabase starter can be built from migrations and synthetic seed, tested at the database boundary, and exercised through real local Auth/API HTTP requests with two isolated accounts.

## Scope and dependencies

- Allowed areas: local server tooling/tests, the existing database CI job and setup/verification documentation.
- Environment: disposable local `c67-starter` only. Docker Desktop was started for this task; existing homelab services and credentials are separate.
- Authorized actions: implement and verify foundation step 1, including rebuilding only the newly created fixture-only local database after inspecting its contents.
- Deferred: new trip APIs, domain normalization, native app Auth, media, merge and shared deployment.
- Later authorized scope: the approved homelab backup/restore/deployment and shared HTTP checks are complete. The user subsequently approved a Git/PR checkpoint before step 2. See [homelab results](../homelab-verification.md).

## References

- [Server guide](../../server/README.md)
- [Server instructions](../../server/AGENTS.md)
- [Backend decision](../decisions/0002-server-architecture.md)
- [Existing contract](../../contracts/README.md)
- [Verification evidence](../verification.md#local-backend-foundation--23-october-2026)

## Acceptance criteria

- [x] Pinned tooling starts the local stack and applies the existing migration/seed.
- [x] A guarded fixture-only local rebuild reproduces the same baseline.
- [x] All existing pgTAP checks pass and public-schema lint reports no errors.
- [x] Two synthetic users sign up/login through Auth HTTP and receive real sessions.
- [x] Private reads are isolated by owner; invalid/missing sessions and direct write bypasses fail.
- [x] Snapshot copy, retry identity, changed-input conflicts and concurrent retries work through HTTP.
- [x] Temporary test data is cleaned up and cleanup is verified.
- [x] Setup, CI commands, results and unverified boundaries are documented.

## Verification plan and results

From `server/`: `npm ci`, `npm run start`, fixture-only preflight, `npm run db:reset`, `npm run db:test`, `npm run db:lint`, `npm run api:test`, then `npm run stop`.

Database: 14 checks pass. HTTP: 27 checks pass. Lint: no public-schema errors. Root contract/fixture validation also passes. Detailed environment and limitations are in [Verification](../verification.md).

## Result and handoff

- Added a local-only HTTP acceptance suite and npm commands; extended the existing database CI job.
- Kept migration history, seed fixtures, API contract and native app behavior unchanged.
- The local database was rebuilt only after confirming zero accounts/trips and the expected fixture count. Test data was removed; the stack was stopped with its local volume retained.
- No server secrets were copied into the app or committed files.
- Updated CI is configured but has not run on GitHub for this branch.
- Next task: separately scope trip list/detail persistence APIs with the iOS data owner (step 2).
- Commit/push status: prepared for the authorized checkpoint PR; final identifiers are reported at handoff.
