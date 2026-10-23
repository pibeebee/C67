# Task: Trip model foundation (stage 3A)

Status: In progress
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

## Acceptance criteria

- [ ] Existing APIs/tests and iOS caller shapes remain compatible.
- [ ] One rundown can have distinct numbered versions; trip source identity remains fixed.
- [ ] Destination dates derive from explicit valid time zones across UTC/day/DST boundaries.
- [ ] Legacy zone/date remain null; server owns revision and derived fields.
- [ ] Both new RPCs enforce real traveller sessions, owner isolation, retry identity and changed-input conflicts.
- [ ] Contract, SQL lint, full pgTAP/HTTP suites and CI pass.
- [ ] A concrete homelab preflight/plan is ready for separate approval.

## Verification plan

Run contracts/Python/whitespace checks locally and the complete database/API suites in disposable CI. Reuse the approved-backup/isolated-restore approach only after presenting the exact new remote scope. Never start Mac Docker or reset shared data as a prerequisite.

## Handoff boundaries

Revision starts at 1 and privileged database updates increment it; no client edit RPC or optimistic-concurrency behavior is activated. Future edits must add expected_revision and immutable command receipts before changing current retry assumptions. Only planned is currently accepted. Curated root identity does not implement creator profiles, publication/withdrawal, rights or source deletion policy.
