# Task: Trip model foundation (stage 3A)

Status: Implementation and backend CI verified; shared approval/deployment pending
Owner: Giovan
Reviewers: Server and iOS data owners before merge
Branch: gi/trip-model-foundation (from merged main b9c5e91)

## Outcome

Separate curated rundown identity from version identity and persist an explicit destination time zone/date with a server revision on personal snapshots. Keep existing API payloads compatible.

## Scope and dependencies

- Additive schema, create_trip_v2/get_trip_snapshot_v2, OpenAPI/fixtures, SQL/HTTP acceptance checks and handoff documentation.
- Legacy APIs retain their exact shapes. Legacy trips have unknown (null) time zone/date; an instant does not reveal a destination IANA zone.
- Stage 3A keeps ordered stop JSON, planned status and initial revision. Stop/leg normalization (including origin/landing/first-stop distinction), editing with expected_revision/receipts, merge and lifecycle transitions are subsequent slices.
- No native Swift/UI/Auth edits, publishing policy or external provider is introduced.
- Local source edits, commit/push/draft PR and CI continue the authorized backend workflow. A new concrete approval is required before homelab writes; previous approval covered only the preceding migration.

## References

- [Architecture](../architecture.md)
- [Contract](../../contracts/README.md)
- [Previous slice](private-trip-reads.md)
- [Server roadmap](../server-roadmap.md)
- [Prepared homelab plan](../homelab-trip-model-plan.md)

## Acceptance criteria

- [x] Existing APIs/tests and iOS caller shapes remain compatible.
- [x] One rundown can have distinct numbered versions; trip source identity remains fixed.
- [x] Destination dates derive from explicit valid time zones across UTC/day/DST boundaries.
- [x] Legacy zone/date remain null; server owns revision and derived fields.
- [x] Both new RPCs enforce real traveller sessions, owner isolation, retry identity and changed-input conflicts.
- [x] Contract, SQL lint and full pgTAP/HTTP suites pass in CI (Simulator job remains separate).
- [x] A concrete homelab preflight/plan is ready for separate approval.

## Verification plan

Run contracts/Python/whitespace checks locally and the complete database/API suites in disposable CI. Reuse the approved-backup/isolated-restore approach only after presenting the exact new remote scope. Never start Mac Docker or reset shared data as a prerequisite.

## Handoff boundaries

Revision starts at 1 and privileged database updates increment it; no client edit RPC or optimistic-concurrency behavior is activated. Future edits must add expected_revision and immutable command receipts before changing current retry assumptions. Only planned is currently accepted. Curated root identity does not implement creator profiles, publication/withdrawal, rights or source deletion policy.

## Result and handoff

Implementation `d9d90f3` passed the database/contracts/style jobs in [CI run 39988491177](https://github.com/pibeebee/C67/actions/runs/39988491177). Actual backend output: 79/79 pgTAP assertions, no schema lint errors, 54/54 HTTP checks and successful temporary-data cleanup. Contract/fixture validation, Python syntax and documentation/whitespace checks pass locally. The iOS Simulator job is still running; no native source changed.

[Draft PR #3](https://github.com/pibeebee/C67/pull/3) contains the additive model and handoff. Shared homelab remains at the two previously verified migrations; no new root table or V2 RPC is deployed. The proposed matching-image restore gate will additionally exercise backfill of an existing legacy trip. Next server model work is stage 3B: normalized stop/day/source and explicit route-leg data, under a separate contract. Native V2 adoption belongs to the iOS data owner.
