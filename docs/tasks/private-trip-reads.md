# Task: Read private persisted trips

Status: Implementation and CI verification complete; shared homelab approval/deployment pending
Owner: Giovan
Reviewers: Server and iOS data owners before merge
Branch: gi/server-local-foundation (foundation checkpoint followed by an additive read commit in the same draft PR)

## Outcome

An authenticated traveller can list their persisted trips using bounded keyset pagination and reload one complete saved snapshot. Foreign and missing details return the same 404.

## Scope

SQL RPCs, additive OpenAPI 0.2/fixtures, database and HTTP acceptance checks, server documentation and iOS data handoff. Native login/UI/repository methods, trip editing, full timezone/revision models and other roadmap steps remain separate work. Existing RPC payloads are preserved.

## Acceptance

- [x] Default/empty lists, deterministic tied-time ordering, pagination boundaries and account-bound cursors work.
- [x] Detail returns persisted data without rebuilding it from the source.
- [x] Anon/missing subjects and cross-account reads are rejected.
- [x] Invalid limits/cursors/IDs and non-finite starts fail without writes.
- [x] Contract/fixtures and full database/HTTP suites pass on a disposable environment.
- [ ] Shared homelab application and temporary account tests have a concrete approved preflight before execution.

## References

- [Contract](../../contracts/README.md)
- [Migration](../../server/supabase/migrations/20261023100158_add_private_trip_reads.sql)
- [Deployed foundation](../homelab-verification.md)
- [Prepared homelab plan](../homelab-trip-reads-plan.md)

## Handoff

The server adds list_my_trips and get_trip_snapshot without changing Trip JSON. The iOS data owner should add typed page/cursor models and repository/mock methods against this contract; no UI or Swift implementation is claimed in this server task.

## Verification

Implementation `fa274b1`: [CI run 39937332257](https://github.com/pibeebee/C67/actions/runs/39937332257), 40/40 pgTAP assertions, clean SQL lint and 39/39 HTTP checks on disposable PostgreSQL 17.11. Contract/fixture, Python syntax and whitespace checks pass. Shared deployment requires the prepared plan and an isolated PostgreSQL 17.6 restore gate. No new RPC has been deployed to the shared backend.
