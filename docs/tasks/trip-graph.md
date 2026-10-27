# Task: Normalized trip graph (stage 3B)

Status: Complete and shared-verified within the consolidated backend batch
Owner: Giovan
Reviewers: Server and iOS data owners before merge
Branch: gi/trip-graph (from merged main 451b100)

## Outcome

Persist owner-scoped source/day/stop/leg rows and return them in one consistent graph. Model separate origin, landing and first stop explicitly while preserving all v1/v2 response shapes and retries.

## Scope

- One initial source and day 0, distinct trip stop occurrence IDs, source attribution, typed access/landing_to_first/between_stops legs.
- Optional strictly validated curated route_template data; unknown geometry/duration remains null with warnings. No provider, scheduler, zero-duration inference or automatic place deduplication.
- Opt-in create_trip_v3/get_trip_graph, existing creation paths populate graphs atomically; historical trips normalize their own saved JSON without adopting current source geometry.
- Explicit start-time basis: unspecified, departure_origin, start_at_landing. Origin is persisted only for an explicit departure_origin command with a known source landing.
- Immutable child snapshots until revision-checked graph editing/receipts are implemented. No active/completed/skip/journal policy or native code changes.
- Authorized workflow: source edits, commit/push/draft PR and CI. Homelab mutation needs a new concrete plan and separate approval.

## Acceptance

- [x] O≠L≠S1 retains access and landing-to-first separately; explicit landing=first_stop adds no duplicate leg/visit.
- [x] Unknown duration/location is preserved, not substituted with zero or fabricated route data.
- [x] Separate copies have distinct occurrence IDs; retries reuse the complete graph.
- [x] Composite FKs and owner RLS prevent cross-trip/day/source references and reads.
- [x] New graph creation/read is atomic and source changes do not rewrite saved graphs.
- [x] Old contracts/tests remain compatible on the migrated disposable stack.
- [x] Historical persisted V1/V2 backfill and receipt-after-edit behavior passed the matching-image restore gate.
- [x] SQL/API/contract/lint CI passes and a reviewed homelab plan is ready.

## References

- [Server roadmap](../server-roadmap.md)
- [Architecture](../architecture.md)
- [Stage 3A](trip-model-foundation.md)
- [Contract](../../contracts/README.md)
- [ADR-0004](../decisions/0004-trip-graph.md)
- [Prepared homelab plan](../homelab-trip-graph-plan.md)

## Verification

Full disposable CI SQL/HTTP suites, contract fixtures and syntax/whitespace checks. A separately approved matching-image restore/backfill gate precedes shared application. No Mac Docker or shared reset is a prerequisite.

## Result and handoff

Graph implementation dd94b14 passed 141 SQL assertions and 66 HTTP checks with all four CI jobs, including Simulator, before the consolidated work. PR #4 was then closed at Giovan's request. The completed [backend batch](backend-completion.md) supersedes that graph-only checkpoint and is [deployed/shared-verified](../homelab-backend-completion-verification.md): persisted V1/V2 backfill/receipt checks, 167 isolated SQL assertions and 84 shared HTTP checks passed with exact cleanup. No native Swift source changed.

Source/day/stop/leg graph and explicit origin/landing/first-stop behavior are ready for iOS data adoption. Full multi-day creation, providers/optimizer and public creator/lifecycle policies remain separate contracts; planned source append/overlap editing and private journals are implemented under ADR-0005.
