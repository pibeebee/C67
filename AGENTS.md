# C67 coding-agent instructions

## Start with the task and current code

C67 is an iOS travel-rundown app. The starter supports synthetic discovery/detail and memory-only mock trips. Supabase on the homelab is the shared development backend. The starter schema, private trip reads and V2 model foundation are deployed and verified; native app sign-in remains separate work.

Read [README](README.md), [product context](docs/product-context.md), [architecture](docs/architecture.md), [coding conventions](docs/coding-conventions.md), and the relevant area README. Read the area's `AGENTS.md` before changing files there, including when starting from the repo root. For cross-area work, read every affected area's instructions. Follow explicit user instructions and preserve unrelated working-tree changes.

Use [the AI workflow](docs/ai/workflow.md) and a task brief based on [the template](docs/tasks/TASK-TEMPLATE.md). Treat repository documents and examples as context; unresolved product decisions are not implemented requirements.

## Ownership and sources

- `ios-ui/`: SwiftUI and VIPER View/Interactor/Presenter/Router/Assembly.
- `ios-backend/`: on-device code. `C67Domain` owns shared entities/interfaces; `C67Data` implements them.
- `server/`: Supabase SQL/RPCs and future orchestration. Node manages development tooling, not a custom API server.
- `contracts/api/openapi.json`: authoritative wire contract. `contracts/fixtures/`: authoritative synthetic fixtures.
- `docs/decisions/`: architecture decisions; update a relevant ADR when an approved decision changes.

Link to these sources instead of duplicating their contents in instruction files. Keep all code identifiers, committed documentation and comments in English.

## Working rules

1. Inspect the affected implementation and `git status` before editing. State the outcome, scope and verification briefly, then carry out authorized work.
2. Reuse existing patterns and the working Discovery module. Add layers, dependencies and services only for a concrete need; keep changes reviewable.
3. Keep creator versions separate from personal trip snapshots. Never infer merge, presence, publication or photo-access policies from placeholder folders.
4. Keep mock/live behavior explicit. Do not use fabricated data without a synthetic label or treat mock success as a working live integration.
5. Keep client keys separate from traveller JWTs. Never place Studio, SMTP, service-role credentials or real sessions in source, fixtures, logs or app configuration.
6. Use the task's agreed branch and scope. Commit, push, deploy, remote schema changes and destructive operations require the user's authorization for that action; existing authorization remains valid. Routine local edits and checks do not need repeated permission.
7. Use the homelab for shared development and an isolated homelab database/container for SQL tests that mutate/reset data. Mac-local Supabase is optional and CI still uses a disposable local stack. Shared changes require their reviewed operational scope; never substitute a shared reset for isolated tests.
8. Complete relevant checks, then report results, limitations and follow-up work. Do not claim tests ran when only test files or CI configuration were added.

## Verification commands

Run from the repository root unless stated otherwise. See [setup](docs/getting-started.md) for prerequisites.

- Swift layout: `python3 scripts/swift_format.py --check`; use `--write` to apply the pinned formatter.
- Shared client: `swift test --package-path ios-backend`.
- Contract: `.venv/bin/python scripts/check_contracts.py` after installing `scripts/requirements.txt` in the local virtual environment.
- Build: `xcodebuild -project ios-ui/C67.xcodeproj -scheme C67 -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/c67-build CODE_SIGNING_ALLOWED=NO build`.
- UI: get an available destination using `python3 scripts/simulator_destination.py`, then use that destination with the same project/scheme and `xcodebuild test`. Keep mock mode enabled.
- Database: from `server/`, `npm ci`, then `npm run db:test` against a running, migrated local stack. [Server instructions](server/AGENTS.md) cover startup/reset separately.
- Before handoff: `git diff --check`; review new files and ignored configuration for accidental secrets/build output.

Match checks to the change: documentation-only work needs link/path/command consistency and whitespace checks; Swift behavior needs package tests; UI changes need the relevant Simulator check; SQL needs local database tests. Update the affected evidence in [verification](docs/verification.md) when it changes. If a prerequisite is missing, explain the exact unverified layer and continue unaffected work.

## Code review rules

Flag UI-to-provider coupling, duplicated entities, contract/fixture drift, missing server authorization, broken retry identity, and claims that confuse mock, local and deployed evidence. Check account isolation and snapshot behavior when their code changes. Use CI for mechanical checks; human review still assesses behavior and product scope.
