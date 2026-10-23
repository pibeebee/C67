# Starter verification

**23 October 2026.** These checks concern the starter, not the deployed homelab or product validation.

| Check | Result / boundary |
|---|---|
| Swift package | 4 tests pass: snapshot/retry behavior, missing-session boundary, configuration validation, RPC headers/error/date decoding |
| iOS Simulator build | Pass with Xcode 27.1 / Swift 6.4; deployment target iOS 18 |
| Mock UI smoke test | 1 test passes on iPhone 18 Pro Simulator, iOS 27.0: discovery → detail → save |
| Configuration | Dummy live mode/client key and local URL confirmed in the built Info.plist; no live server request implied |
| API contract | OpenAPI 3.1 validates; all three JSON fixtures validate; bundled catalog and SQL seed match the authoritative fixture |
| Configuration formats | XcodeGen/workflow YAML and local Supabase TOML parse |
| Project generator | XcodeGen 2.45.4 |
| Supabase CLI | 2.121.0 pinned with npm lockfile; config and migration name generated through CLI |
| Database runtime | Verified locally on 23 October: clean startup and guarded local rebuild apply the migration/seed; 14/14 pgTAP checks pass and public-schema lint reports no errors. See local foundation evidence below. |
| GitHub Actions | Baseline commit `640f035` passed `ios`, `contracts` and `database`; new conventions/formatter PR is checked separately |
| Auth / homelab | Local tests and shared homelab integration verified; shared suite passes 28 checks and preserves the existing account. Native iOS login and real-person app sessions remain untested. See homelab evidence below. |
| Physical device / offline / field use | Not tested; mock trips are memory-only |

Before shared backend deployment, rerun local database/API checks for the proposed revision, review the homelab database version and existing schema, implement/verify the native traveller session path, and prepare a separate operational deployment plan. The local development stack is not an export of homelab credentials or data.

## Team-conventions setup

- The checksum-verified SwiftFormat 0.64.1 runner successfully downloaded its pinned macOS release, formatted two Swift files for layout only, and passed `--check` for all 15 Swift files.
- The shared package still passes all 4 tests after formatting. Contract/fixture checks, Markdown links/fences, Python syntax and workflow YAML checks pass.
- GitHub protection/merge settings are documented in [Repository settings](repository-settings.md) and verified by reading back the GitHub API.
- Main requires an eligible human approval. Ownership, CODEOWNERS and collaborator roles were explicitly skipped; the setup PR is not automatically merged.

## Local backend foundation — 23 October 2026

Scope: [foundation task](tasks/server-local-foundation.md), branch `gi/server-local-foundation`, based on main commit `1dd5eeb`. No domain migration, wire contract, native app feature or shared-server configuration was changed.

Environment: macOS arm64, Docker Desktop engine 29.6.1, Node.js 24.14.0, Python 3.14.6, pinned Supabase CLI 2.121.0, local PostgreSQL 17.11. Docker had no pre-existing containers or volumes before the C67 stack was started. The existing migration and synthetic seed applied successfully at first startup.

| Check | Actual result |
|---|---|
| Reproducible local rebuild | Before reset, confirmed `c67-starter` had zero Auth users, zero trips and exactly the authoritative catalog fixture. `npm run db:reset` targeted only local data and reapplied schema/migration/seed successfully. |
| Database | `npm run db:test`: 14/14 pgTAP checks pass after the rebuild. |
| SQL lint | `npm run db:lint`: no public-schema errors. |
| HTTP/Auth | `npm run api:test`: 27/27 checks pass, including two signup/password sessions, token refresh, invalid-token rejection and missing-session denial. |
| Ownership and writes | Account A/B isolation works in both directions through direct Data API reads; anonymous reads and direct insert/update/delete are rejected; unpublished content is hidden through both RPC and direct reads. |
| Copy/retry | Response matches the source snapshot, timezone offsets preserve the same instant, identical retries return one trip, changed input returns 409, and four concurrent same-command requests return one persisted trip identity. |
| Cleanup | Temporary users, their cascading trips and the temporary draft are removed and their absence verified. |
| Contract/fixtures | `.venv/bin/python scripts/check_contracts.py` passes OpenAPI, fixture schema, package copy and SQL seed consistency checks. |
| CI configuration | The existing database job now includes pinned Python 3.12, SQL lint and local HTTP tests. Updated GitHub Actions have not been run remotely for this branch. |

The local gateway permits reading the public synthetic catalog without an API-key header. This is not evidence of API-key enforcement at the homelab gateway. Private trip commands are still rejected without a valid traveller session; ownership enforcement was tested independently of client-key presence.

The HTTP suite uses Python's standard library and obtains local credentials in memory; keys, passwords, sessions and response bodies are not recorded in the repository. No test user or private trip is part of the seed. The database stack is stopped after verification, with its fixture-only local volume retained for the next start.

Unverified: native iOS login/session storage, Simulator/live wiring, physical devices, expired-token behavior, deployed homelab/API compatibility, storage/media, database load, backup/restore and product policy. No commit, push or deployment was performed. The work intentionally ends at foundation step 1.

## Shared homelab foundation — 23 October 2026

The approved deployment is complete. See [Homelab verification](homelab-verification.md) for exact evidence and recovery limits: private backups verified, both databases restored in isolation on PostgreSQL 17.6, 14/14 isolated pgTAP checks and 28/28 shared HTTP checks passed, official migration history recorded, all 11 services healthy, existing Auth account preserved and temporary records/container removed. These results supersede the earlier local-only homelab boundary for the starter foundation. Native iOS integration and step 2 APIs remain separate work.

## Private trip reads — in progress

The additive contract, SQL migration, 26 new pgTAP checks and private-read HTTP checks are prepared. Contract/fixture validation, Python syntax and whitespace checks pass locally. CI execution and shared homelab deployment results are pending; foundation results above apply only to the original three RPCs. See the [task](tasks/private-trip-reads.md).
