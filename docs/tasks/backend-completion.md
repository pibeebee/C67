# Task: Backend stages 3B–7 complete before review PR

Status: Complete for the agreed server scope; review PR prepared after shared verification
Owner: Giovan
Branch: gi/trip-graph (main baseline 451b100)

## Outcome and human decisions

Giovan requested closing PR #4, preserving work and completing stages 3B–7 before opening one new PR. PR #4 remains closed. Source work, disposable CI, separately approved homelab application and cleanup are complete; no merge is authorized by deployment.

Agreed product scope: operator-curated catalog, private owner album, device-reported location at upload-session creation without a second presence gate after worker delay, planned-only editing/merge. Public creator authoring and completed/skip/ended_early remain inactive. Reported coordinates and byte validation do not certify presence or photo authenticity.

## Delivered

- Owner-scoped graph, explicit origin/landing/first-stop semantics and V1/V2 compatibility.
- Bounded published discovery with text/area filters and query-bound keyset pagination.
- Planned preview/apply title/time/zone changes, source append and explicit retained-occurrence overlap choices; revision locking, permanent receipts and protected pending/journaled plans.
- Private raw/ready buckets, location-bound sessions, create-only uploads, leased image validation, accepted journals and owner-only albums.
- Restricted healthy continuous worker, safe health/backup/recovery tooling, matching-image restore/backfill gates and exact cleanup.

## Verification

All four CI jobs passed at e32e283 ([run 40256508924](https://github.com/pibeebee/C67/actions/runs/40256508924)): 167 SQL assertions, clean lint, 66 retained HTTP checks, 16 complete-backend checks, two decoder tests, safe health and production Docker smoke. The binary test client subsequently gained the same truthful C67 User-Agent as its JSON client (548158b), following a diagnosed Cloudflare1010 edge denial; no gateway/policy/runtime-image change occurred.

Giovan separately approved the [consolidated exact plan](../homelab-backend-completion-plan.md). Both databases restored on the exact PostgreSQL17.6 image, persisted V1/V2 backfill/receipts passed, and all **167/167 isolated SQL assertions** passed. Four official migrations applied (seven total). Final real shared acceptance: **67 retained + 17 completion = 84 checks**, including actual Storage/image worker/journal/album, stale lease recovery and object privacy. Original account/catalog/root fingerprints and all 11 Supabase container IDs/start times are unchanged. Test rows/objects are zero, two buckets private/empty, and the isolated container/tunnel removed.

One c67-media worker is healthy under its reviewed filesystem/resource/security limits; env is private mode600. Recovery points/checksums remain private. See [full shared evidence](../homelab-backend-completion-verification.md).

## Handoff and boundaries

Open one review PR for the complete batch, then obtain normal human review before merge. The iOS data owner can adopt the [OpenAPI contract](../../contracts/README.md), source-route/graph/edit/upload/album fixtures and existing compatibility APIs. No native implementation is claimed.

[ADR-0005](../decisions/0005-backend-mvp.md) and [operations](../backend-operations.md) document maintenance and policy. Physical iPhone/HEIC conversion, field GPS/limits, queue/load/RPO/RTO, scheduled/off-host recovery and full object-service restore need separate evidence. These limits are not represented as completed product work.
