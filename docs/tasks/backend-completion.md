# Task: Complete backend stages 3B–7 before opening a PR

Status: In progress
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
