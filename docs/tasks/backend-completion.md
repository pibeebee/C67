# Task: Complete backend stages 3B–7 before opening a PR

Status: Source/CI complete; consolidated homelab approval/deployment/verification pending
Owner: Giovan
Branch: gi/trip-graph

## Human decisions — 26 October 2026

Close PR #4, preserve branch/commits, finish all backend roadmap stages 3B–7 and only then open one reviewable PR. Branch CI runs independently of a PR. Teammate inactivity is context, not permission to bypass protected main or merge without review.

Approved product scope: curated operator catalog; private owner album; reported-device location evaluated when requesting an upload session, with no second location requirement after worker delay; edit/merge limited to planned trips. Do not enable completed/skip/ended_early or public creator authoring. Sensor reports do not prove physical presence or photo authenticity.

## Deliverables

- Normalized graph (3B), bounded discovery/search/cursors (4).
- Private upload session, server validation worker, accepted journal/album (5), cleanup/recovery and secure object access.
- Revision-checked preview/apply edits and explicit keep-both source append, immutable receipts and protected journaled visits (6).
- Reviewable operations, restore/backfill, diagnostics/health and recovery evidence (7).
- Shared homelab deployment remains governed by a refreshed concrete plan and explicit approval. Previous approval covered stage 3A only. Do all authorized local work first; do not reopen a PR just to trigger CI.

## Verification

Retain v1/v2/v3 suites. Test complete Auth/API/Storage/worker path, cross-account and direct-access denial, malformed media/limits, duplicate receipts/concurrency, worker crash/retry, source-independent copies and safe cleanup. Disposable CI is permitted; no Mac Docker or shared reset prerequisite. Record remaining on-device, field, production capacity and off-host disaster-recovery boundaries honestly.

## Implementation checkpoints

PR #4 is verified closed; no replacement PR has been opened. The main baseline remains 451b100 and the branch retains the graph commits. CI now triggers for branch pushes.

Database/API/Storage/worker integration has passed at intermediate commits. Final revision additionally covers explicit overlap retention/removal, reschedule with destination-date projection, lease recovery/stale finalization, protected pending/accepted plans, processed-byte privacy and production container smoke checks. Final counts/results are recorded only after those jobs complete.

The shared preflight on 26 October found 11 healthy services, PostgreSQL 17.6, Storage v1.81.0, one user/catalog/root, zero trips/buckets/objects and exactly three applied migrations. Four reviewed migrations are pending. The c67-media directory/project, isolated test name and new backup destination are unused. No shared mutation in this completion batch has run.

## Operational approval gate

The original graph-only deployment plan is superseded by [the consolidated plan](../homelab-backend-completion-plan.md). It now includes four migrations, two private buckets, a new ongoing media worker and broader synthetic acceptance fixtures. This new exact scope has not been approved. Keep main unchanged, retain all commits and do not open a new PR until shared deployment/verification is complete or Giovan explicitly changes the completion boundary.

## Final disposable verification — 26 October 2026

Source checkpoint c55aef6 passed all four [CI jobs in run 40255936842](https://github.com/pibeebee/C67/actions/runs/40255936842): database, contracts, style and iOS. Actual database job evidence:

- Five SQL files: **167/167 pgTAP assertions**.
- Public-schema lint: no schema errors.
- Retained Auth/API/graph suite: **66/66 checks** and exact synthetic cleanup.
- Complete discovery/edit/merge/private-photo/Storage/worker/album suite: **16 checks**, including lease recovery, stale finalization, journal protection, exact-ID cleanup and receipt stability after rescheduling/edits/journals.
- Image decoder: **2 tests** pass; npm runtime audit reports zero known vulnerabilities.
- Production Docker image smoke: passes with read-only root/tmpfs, dropped capabilities, bounded memory/CPU/PIDs against the disposable stack.
- Read-only backend health: passes. Contract/10 fixture validation, Python syntax, Markdown links, secret-pattern and whitespace checks pass locally.

The four migrations and runtime/test inputs are pinned in the consolidated plan. New operational preflight additionally proved that existing supabase_admin is required/available for Storage policy ownership, without changing any role/grant/password. No homelab changes occurred in this batch and no new PR is open.

Remaining acceptance is explicitly operational: private backup/restore/backfill on PostgreSQL 17.6, four official migrations/two private buckets, real shared API/Storage verification and the single restricted continuous worker. Open one PR only after those gates complete. Native login/photo conversion, physical location/field validation, off-host/scheduled recovery and production load/RPO/RTO remain outside this agreed server slice.
