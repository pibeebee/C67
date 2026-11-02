# Server roadmap

## Personal planning track — 30 October 2026

[ADR-0009](decisions/0009-personal-planning-implementation.md) and [task evidence](tasks/ai-trip-planning-implementation.md) record the repository implementation. [Planning semantics](ai-trip-planning.md) defines the chosen MVP bounds.

| Stage | Current outcome | State |
|---|---|---|
| A | Explicit input/duration/finish semantics, one day/1–6 stops, walking/driving | Implemented contract and UI |
| B | Hosted-model, Apple Maps/Weather and bounded website adapters | Implemented; real credentials/model/coverage/data-policy acceptance pending |
| C | User-place planning, optional suggestions and reviewed save | Implemented mock/live boundaries; synthetic backend checks and iOS builds only |
| D | Checked arithmetic, preserved destinations, visible conflicts and source context | Software invariants checked; real factual/quality evaluation pending |
| E | Manual arrival/extension/completion and revision-bound remaining-trip replanning | Implemented in independent aggregate; shared migration/service deployment pending |
| F | End-user evaluation, field/device behavior, real cost/latency and operations | Outstanding acceptance work |

Existing payloads and journal guards remain compatible. The new code does not authorize an incidental shared deployment, provider charge or database reset. Full-stack/matching-image and new iOS interaction acceptance remain separate from the synthetic checks recorded for this task.

## Previously implemented backend sequence

This records the seven-step backend sequence agreed with Giovan. It is an implementation roadmap; the full technology proposal is reference context rather than permission to activate every product policy.

| Step | Outcome | State |
|---|---|---|
| 1 | Reproducible foundation, real-session API tests and privacy/retry evidence | Complete; local, CI and homelab evidence recorded |
| 2 | Persisted owner trip list and stored detail | Complete and deployed; PR #2 merged as b9c5e91 |
| 3A | Curated root/version identity, explicit destination time/date, revision and planned state | Complete and deployed: [trip model foundation](tasks/trip-model-foundation.md); PR #3 merged as 451b100 |
| 3B | Normalized stop occurrences, days/sources and explicit origin → landing → first-stop → following-stop legs | [Complete and shared-verified](tasks/backend-completion.md); PR #4 remains closed |
| 4 | Discovery text/area search, pagination and multiple synthetic fixtures; geography when map queries require it | [Complete and shared-verified](tasks/backend-completion.md) |
| 5 | One stop → private photo upload/validation → accepted journal → album | Private/session-start location policy agreed; API/Storage/worker/album shared-verified |
| 6 | Preview/apply edits and merge with explicit user choices, expected_revision, durable command receipts and atomic writes | Preview/apply, overlap choices, receipts and journal protection shared-verified |
| 7 | Shared deployment/recovery, safe logs, capacity and monitoring | Backup/restore/backfill, safe health, restricted healthy worker and failure/recovery gates verified; off-host/scheduled recovery not claimed |

The homelab is shared development. Mutating/reset SQL tests use an isolated clone; CI uses disposable Docker, with no Mac Docker prerequisite. Each new shared mutation follows its concrete approved operational plan. Scheduled/off-host backups and native iOS integration are separate outstanding work.
