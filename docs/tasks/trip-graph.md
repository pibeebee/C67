# Task: Normalized trip graph (stage 3B)

Status: Implementation/backend CI verified; homelab approval/deployment pending
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
- [ ] Historical persisted V1/V2 backfill preserves saved values and unknowns in the matching-image restore gate.
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

Implementation dd94b14 passes backend checks in [CI run 40046041636](https://github.com/pibeebee/C67/actions/runs/40046041636): 141/141 pgTAP assertions (79 retained + 62 graph), clean public-schema lint and 66/66 real-session HTTP checks with fixture/account cleanup. OpenAPI 0.4 and nine fixtures validate. Python syntax, documentation links, approved-input hashes and whitespace checks pass locally. All four implementation CI jobs passed, including the Simulator check; no Swift source changed.

PR #4 was closed at Giovan's request. Continue stages 3B–7 on this branch and open one new PR only after the complete agreed backend scope is verified. Shared homelab remains at the three previous migrations; the graph is not deployed there. The prepared plan separately gates restore/backfill of persisted V1/V2 records, 141 matching-image SQL checks, official migration and 67 shared HTTP checks. No shared mutation has been run in this stage.

The iOS data owner can adopt the new published source-route and authenticated graph endpoints without changing existing consumers. Full multi-day/multi-source creation, scheduler/provider work, edits/concurrency receipts and lifecycle/journaling remain later contracts. Stage 3B supplies the initial one-day normalized model and explicit landing semantics.
