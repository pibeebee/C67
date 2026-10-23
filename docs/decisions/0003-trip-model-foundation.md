# ADR-0003 — Additive trip model foundation

Status: Implemented and verified on the shared homelab for stage 3A. See [execution evidence](../homelab-trip-model-verification.md).
Date: 23 October 2026.

## Decision

Keep all five existing RPC wire shapes unchanged. Add create_trip_v2 and get_trip_snapshot_v2 with a distinct TripSnapshotV2 schema. A client opts in by choosing the new RPC; the schema_version field is 2. Existing list_my_trips remains a compact v1-shaped list; clients may fetch v2 detail for destination metadata.

A curated rundown identity has its own rundowns row; rundown_versions carries rundown_id/version_no. Existing versions receive separate newly generated roots and version number 1. This is a one-to-one legacy backfill, not guessed grouping of similar titles. Future privileged imports can explicitly add distinct numbered versions under the same root. Ordinary clients cannot write these tables. Root reads reveal only identities with an already-visible published version.

Each trip stores immutable source root/version/number attribution along with its existing copied title/stops. Identity metadata on a source version cannot be reassigned. Content immutability, creator identities and publishing/withdrawal policy are not added by this migration; the current curated development policy is preserved.

V2 creation requires an unambiguous timestamp instant and a PostgreSQL-recognized IANA zone (UTC or region/name). The server derives local_start_date in that zone, allowing destination/UTC calendar dates to differ. Offset-only values, unknown/internal zones, non-finite instants and destination dates outside years 1–9999 are rejected. The API accepts instants rather than interpreting ambiguous/nonexistent local clock times. Accepted IANA aliases are retained literally; a different zone string counts as changed retry input.

Legacy creation/backfill retains null time_zone/local_start_date: the destination cannot be inferred from an instant or an input offset that PostgreSQL has already normalized. No UTC zone, creator recommendation, ETA or actual visit time is fabricated.

A trigger derives attribution/date and owns revision: insert sets 1; each accepted privileged row update increments the previous revision regardless of a submitted revision. The current saved state is planned; no start/completion/early-ending transition is enabled. Client writes remain revoked. A v2 retry preserves identity/model/revision; API generation is part of command identity, so cross-generation reuse conflicts. The unique owner/request key resolves concurrent same-command retries.

## Consequences and following slices

This is a bounded stage 3 foundation. Ordered stop JSON is retained. Explicit origin → landing → first-stop → following-stop legs, normalized stop occurrence identity, scheduler data and unknown durations need their own subsequent contract/fixtures. No route geometry or timing can be inferred from the starter's two stop titles.

No client editing RPC is introduced. Before editing is enabled, implement expected_revision under the shared trip lock and durable immutable command receipts; current creation retry checks compare the stored creation fields. Do not advertise optimistic-concurrency or retry-after-edit guarantees from the revision column alone. Full source deletion/rights policy, creator publication, merge and visit/journal lifecycle remain deferred.

The Swift adapter/UI continues using the existing contract. The iOS data owner can opt into v2 with typed nullable zone/date/source/revision fields. No on-device v2 integration is claimed. Apply through one new migration after CI, private backup and isolated matching-image verification under a separately approved homelab plan.
