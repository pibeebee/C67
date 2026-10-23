# Task: Read private persisted trips

Status: In progress
Owner: Giovan
Reviewers: Server and iOS data owners before merge
Branch: gi/server-local-foundation (foundation checkpoint followed by an additive read commit in the same draft PR)

## Outcome

An authenticated traveller can list their persisted trips using bounded keyset pagination and reload one complete saved snapshot. Foreign and missing details return the same 404.

## Scope

SQL RPCs, additive OpenAPI 0.2/fixtures, database and HTTP acceptance checks, server documentation and iOS data handoff. Native login/UI/repository methods, trip editing, full timezone/revision models and other roadmap steps remain separate work. Existing RPC payloads are preserved.

## Acceptance

- [ ] Default/empty lists, deterministic tied-time ordering, pagination boundaries and account-bound cursors work.
- [ ] Detail returns persisted data without rebuilding it from the source.
- [ ] Anon/missing subjects and cross-account reads are rejected.
- [ ] Invalid limits/cursors/IDs and non-finite starts fail without writes.
- [ ] Contract/fixtures and full database/HTTP suites pass on a disposable environment.
- [ ] Shared homelab application and temporary account tests have a concrete approved preflight before execution.

## References

- [Contract](../../contracts/README.md)
- [Migration](../../server/supabase/migrations/20261023100158_add_private_trip_reads.sql)
- [Deployed foundation](../homelab-verification.md)

## Handoff

The server adds list_my_trips and get_trip_snapshot without changing Trip JSON. The iOS data owner should add typed page/cursor models and repository/mock methods against this contract; no UI or Swift implementation is claimed in this server task.
