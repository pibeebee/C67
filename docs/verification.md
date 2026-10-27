# Starter verification

**23 October 2026.** Evidence below distinguishes starter/mock, disposable CI and shared homelab checks; it does not establish product validation.

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

Before future shared backend changes, rerun database/API checks for the proposed revision, review the homelab database version and existing schema, and prepare a separate operational deployment plan. Verify the native traveller session path before connecting the app to shared data. The local development stack is not an export of homelab credentials or data.

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

## Private trip reads — CI and shared homelab verified

Implementation commit `fa274b1` passed the database and contract jobs in [CI run 39937332257](https://github.com/pibeebee/C67/actions/runs/39937332257). The disposable GitHub Linux stack applied both migrations and the synthetic seed after a clean rebuild. Both pgTAP files passed: 40/40 assertions (14 foundation plus 26 private-read assertions). Public-schema lint reported no errors. The HTTP suite passed 39/39 checks through real local Auth sessions, then removed its temporary data and stopped the stack.

New evidence covers empty/default owner lists, start-time/UUID ordering across page boundaries, account-bound/invalid cursors, persisted detail, uniform missing/foreign 404s and non-finite-date rejection. Existing copy/retry/isolation checks also pass. OpenAPI 0.2 and all three fixtures validate, generated catalog copies remain consistent, and local Python syntax/whitespace checks pass.

This CI stack uses PostgreSQL 17.11; shared homelab remains PostgreSQL 17.6. All four CI jobs passed at documentation checkpoint `4a425bb`. The [approved homelab plan](homelab-trip-reads-plan.md) has also been executed: both databases restored on the exact shared image, 40/40 isolated pgTAP assertions and 40/40 shared HTTP checks passed, the new migration is recorded by the official runner, all 11 services are healthy and the original account/catalog remain with zero trips. Temporary users/data/container were removed. See [actual shared results](homelab-trip-reads-verification.md). Both private RPCs are deployed; native Swift repository/UI integration is separate work. See the [task](tasks/private-trip-reads.md).

## Trip model foundation (stage 3A) — CI and shared homelab verified

Implementation `d9d90f3`, [CI run 39988491177](https://github.com/pibeebee/C67/actions/runs/39988491177): three SQL test files pass 79/79 pgTAP assertions, public-schema lint reports no errors, and real-session HTTP acceptance passes 54/54 checks on the disposable CI stack. OpenAPI 0.3 and five fixture files validate; original catalog copies/seed remain consistent. Existing API tests are retained and pass alongside new identity, destination-time and revision checks. No Swift source changed; all four CI jobs passed at c9164b4, including the Simulator check.

This verifies a clean migrated stack, V1/V2 compatibility, two-account privacy, source version attribution, legacy null-zone behavior, changed-zone/API-generation conflicts, concurrent retries and UTC/date/DST boundaries. The [approved homelab execution](homelab-trip-model-verification.md) additionally restored both databases on PostgreSQL 17.6, proved an upgrade over a persisted synthetic legacy trip without changing its snapshot/owner/request/retry behavior, and passed 79/79 isolated pgTAP assertions before shared application.

Stage 3A is deployed: official history has all three migrations, and 55/55 shared HTTP checks passed. Final state: 11 healthy unchanged containers, one original Auth account, one catalog version/root and zero trips; temporary accounts/trips/draft/root/container were removed. Private backups and exact source hashes are recorded in the [plan](homelab-trip-model-plan.md) and results. Revision alone does not demonstrate optimistic concurrency or retry-after-edit support; see [ADR-0003](decisions/0003-trip-model-foundation.md).

## Normalized trip graph (stage 3B) — backend CI verified

Implementation dd94b14, [CI run 40046041636](https://github.com/pibeebee/C67/actions/runs/40046041636): four SQL files pass **141/141** assertions (79 existing + 62 new), public-schema lint reports no errors, and the expanded real-session HTTP suite passes **66/66** checks. OpenAPI 0.4 and nine fixtures validate, including known/unknown graph and both landing templates; generated catalog/seed copies are unchanged. Python syntax, documentation links and whitespace checks pass. All four implementation CI jobs passed, including Simulator; no native source changed.

Evidence includes distinct origin/landing/first-stop segments, first-stop landing with/without an origin, null unknowns, integral/fractional JSON duration boundaries, stable whole-graph retries, four concurrent retries, separate occurrence identities, source-change independence, owner RLS on every child table, composite cross-trip/day/source rejection and guarded parent cleanup. The seven earlier API payloads remain compatible through the retained suite.

This CI verifies clean migration and all creation paths. Existing persisted V1/V2 backfill still requires the [prepared homelab procedure](homelab-trip-graph-plan.md) in a restored isolated clone before shared deployment. Read-only preflight found 11 healthy services, one user/catalog/root, zero trips and exactly three prior migrations; existing stop arrays satisfy the normalization contract. No stage 3B shared mutation is claimed. The graph is one initial source/day 0, with no scheduler/provider, public edits, lifecycle transition or native integration.

## Consolidated backend stages 3B–7 — source/CI complete, shared gate pending

Giovan closed PR #4 and requested one PR after the complete backend batch. PR #4 is closed and no replacement is open. Source checkpoint c55aef6 passed all four [CI jobs](https://github.com/pibeebee/C67/actions/runs/40255936842) on 26 October: **167/167 SQL assertions**, clean SQL lint, **66 retained HTTP checks**, **16 complete-backend acceptance checks**, **2 image-decoder tests**, read-only API health and the restricted production Docker image smoke. OpenAPI 0.5/10 fixtures validate. The worker's pinned npm runtime dependencies report zero known vulnerabilities. No Mac Docker was started.

Acceptance actually exercised real password/refresh sessions, query-bound discovery pagination, CAS edit races, permanent creation/apply receipts, root/day/date reschedule, explicit source append and retained-occurrence overlap choices, private Storage byte upload/download denial, reported-location session checks, delayed lease recovery/stale finalization, decoded JPEG publication without input EXIF, accepted journal/album, invalid bytes rejection, protected documented topology and exact synthetic account/row/object cleanup. Service-role credentials were confined to setup/worker/cleanup; traveller JWTs established privacy. No real person's media/location was used.

Read-only shared preflight still found 11 healthy services, one original account/catalog/root, no trips/buckets/objects, three migrations and no media worker. The four pending migrations and one new worker are **not deployed**. The [consolidated plan](homelab-backend-completion-plan.md) supersedes the earlier graph-only plan and pins input hashes and exact backup/restore/backfill/Storage/runtime writes. Existing postgres is not the storage.objects owner/member; the existing supabase_admin migration login was verified read-only and will be used only within the approved plan, without granting new rights.

The agreed scope is curated catalog, private albums, session-start reported-location policy, planned-only edits/merge, no completed/skip/ended_early or public authoring. See [ADR-0005](decisions/0005-backend-mvp.md), [completion task](tasks/backend-completion.md) and [operations](backend-operations.md). Source/CI completion is not shared runtime, physical-device, field GPS, media authenticity, off-host recovery or load certification. The review PR remains deferred until operational verification is complete.

## Consolidated backend stages 3B–7 — shared execution complete

The separately approved [combined plan](homelab-backend-completion-plan.md) is executed. [Full shared evidence](homelab-backend-completion-verification.md): two-database restore on exact PostgreSQL17.6, V1/V2 persisted backfill/receipts after edits, **167/167 isolated SQL assertions**, four official migrations (seven total), **67 retained + 17 completion = 84 shared HTTP checks**, private Storage/actual image validation/journal/album and exact cleanup. A diagnosed Cloudflare1010 denial affected Python-urllib; the binary suite now uses its existing C67 client identity. No gateway/Cloudflare policy changed.

Original Auth account/catalog/root fingerprints remain; final test rows and Storage objects are zero, two buckets are private/empty. The new restricted image worker is healthy; all 11 existing Supabase containers are unchanged/healthy, database ports stay unpublished, and the isolated test container/tunnel were removed. Private backup checksums/permissions pass. Physical-device, field-GPS, production capacity and off-host/scheduled/full-object-service disaster recovery remain unverified as documented; native integration is a handoff, not claimed by server acceptance.
