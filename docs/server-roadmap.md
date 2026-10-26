# Server roadmap

This records the seven-step backend sequence agreed with Giovan. It is an implementation roadmap; the full technology proposal is reference context rather than permission to activate every product policy.

| Step | Outcome | State |
|---|---|---|
| 1 | Reproducible foundation, real-session API tests and privacy/retry evidence | Complete; local, CI and homelab evidence recorded |
| 2 | Persisted owner trip list and stored detail | Complete and deployed; PR #2 merged as b9c5e91 |
| 3A | Curated root/version identity, explicit destination time/date, revision and planned state | Complete and deployed: [trip model foundation](tasks/trip-model-foundation.md); PR #3 merged as 451b100 |
| 3B | Normalized stop occurrences, days/sources and explicit origin → landing → first-stop → following-stop legs | [Source/CI complete](tasks/backend-completion.md); shared gate pending; PR #4 closed |
| 4 | Discovery text/area search, pagination and multiple synthetic fixtures; geography when map queries require it | [Source/CI complete](tasks/backend-completion.md); shared verification pending |
| 5 | One stop → private photo upload/validation → accepted journal → album | Private/session-start location policy agreed; API/Storage/worker/album CI passed, shared verification pending |
| 6 | Preview/apply edits and merge with explicit user choices, expected_revision, durable command receipts and atomic writes | Preview/apply, explicit overlap choices and journal protection passed CI; shared verification pending |
| 7 | Shared deployment/recovery, safe logs, capacity and monitoring | Backup/health/recovery tooling and restricted worker image tested; consolidated shared restore/deploy gate pending, off-host/scheduled recovery not claimed |

The homelab is shared development. Mutating/reset SQL tests use an isolated clone; CI uses disposable Docker, with no Mac Docker prerequisite. Each new shared mutation follows its concrete approved operational plan. Scheduled/off-host backups and native iOS integration are separate outstanding work.
