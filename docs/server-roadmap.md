# Server roadmap

This records the seven-step backend sequence agreed with Giovan. It is an implementation roadmap; the full technology proposal is reference context rather than permission to activate every product policy.

| Step | Outcome | State |
|---|---|---|
| 1 | Reproducible foundation, real-session API tests and privacy/retry evidence | Complete; local, CI and homelab evidence recorded |
| 2 | Persisted owner trip list and stored detail | Complete and deployed; PR #2 merged as b9c5e91 |
| 3A | Curated root/version identity, explicit destination time/date, revision and planned state | Complete and deployed: [trip model foundation](tasks/trip-model-foundation.md); PR #3 awaits review/merge |
| 3B | Normalized stop occurrences, days/sources and explicit origin → landing → first-stop → following-stop legs | Next model slice; no invented route geometry, duration or schedule |
| 4 | Discovery text/area search, pagination and multiple synthetic fixtures; geography when map queries require it | Later |
| 5 | One stop → private photo upload/validation → accepted journal → album | Later; presence/audience/worker policy must be resolved |
| 6 | Preview/apply edits and merge with explicit user choices, expected_revision, durable command receipts and atomic writes | Later; journaled visits must remain protected |
| 7 | Shared deployment/recovery, safe logs, capacity and monitoring | Minimum backup/restore/migration workflow already moved before step 2; ongoing operations remain |

The homelab is shared development. Mutating/reset SQL tests use an isolated clone; CI uses disposable Docker, with no Mac Docker prerequisite. Each new shared mutation follows its concrete approved operational plan. Scheduled/off-host backups and native iOS integration are separate outstanding work.
