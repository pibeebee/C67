# C67 coding-agent instructions

## Start with the task and current code

C67 targets AI-generated personal trip recommendations from user-selected places, preferences, weather and time; see [product context](docs/product-context.md) and [ADR-0008](docs/decisions/0008-ai-trip-planning-direction.md). Personal planning UI, a Node/TypeScript API/worker, provider adapters and an additive SQL aggregate are implemented locally; see [ADR-0009](docs/decisions/0009-personal-planning-implementation.md) and [task evidence](docs/tasks/ai-trip-planning-implementation.md). The new service/migration are not shared-deployed. The default mock flow is synthetic personal planning; the legacy Discovery example remains accessible. Supabase on the homelab is the shared development backend. The graph/discovery/planned-edit/private-journal server slice and image worker are deployed and verified; native email/password sessions and discovery/trip query adapters are implemented with their verification tracked separately.

Read [README](README.md), [product context](docs/product-context.md), [architecture](docs/architecture.md), [coding conventions](docs/coding-conventions.md), and the relevant area README. Read the area's `AGENTS.md` before changing files there, including when starting from the repo root. For cross-area work, read every affected area's instructions. Follow explicit user instructions and preserve unrelated working-tree changes.

Use [the AI workflow](docs/ai/workflow.md) and a task brief based on [the template](docs/tasks/TASK-TEMPLATE.md). Treat repository documents and examples as context; unresolved product decisions are not implemented requirements.

## Ownership and sources

- `ios-ui/`: SwiftUI and VIPER View/Interactor/Presenter/Router/Assembly.
- `ios-backend/`: on-device code. `C67Domain` owns shared entities/interfaces; `C67Data` implements them.
- `server/`: Supabase SQL/RPCs and the separate `planning/` Node API/worker. The root server package pins Supabase tooling; planning has its own locked development dependencies.
- `contracts/api/openapi.json`: authoritative wire contract. `contracts/fixtures/`: authoritative synthetic fixtures.
- `docs/decisions/`: architecture decisions; update a relevant ADR when an approved decision changes.
- [Design system](docs/design-system.md): the shared visual reference for UI work; the guide distinguishes documented specifications from implemented components.

Link to these sources instead of duplicating their contents in instruction files. Keep all code identifiers, committed documentation and comments in English.

## Working rules

1. Inspect the affected implementation and `git status` before editing. State the outcome, scope and verification briefly, then carry out authorized work.
2. Reuse existing patterns and the working Discovery module. Add layers, dependencies and services only for a concrete need; keep changes reviewable.
3. Preserve creator-version and personal-snapshot meanings in existing code/contracts. New AI plans must not be forced through invented creator identities. Never infer merge, presence, publication, photo-access or active-trip mutation policies from placeholder folders or target documentation.
4. Keep mock/live behavior explicit. Do not use fabricated data without a synthetic label or treat mock success as a working live integration.
5. Keep client keys separate from traveller JWTs. Never place Studio, SMTP, service-role credentials or real sessions in source, fixtures, logs or app configuration.
6. Use the task's agreed branch and scope. Commit, push, deploy, remote schema changes and destructive operations require the user's authorization for that action; existing authorization remains valid. Routine local edits and checks do not need repeated permission.
7. Use the homelab for shared development and an isolated homelab database/container for SQL tests that mutate/reset data. A disposable embedded PostgreSQL check of the new personal-planning migration is also available without Docker; it does not replace matching-image/full-stack acceptance. Mac-local Supabase is optional and CI still uses a disposable local stack. Shared changes require their reviewed operational scope; never substitute a shared reset for isolated tests.
8. Complete relevant checks, then report results, limitations and follow-up work. Do not claim tests ran when only test files or CI configuration were added.

## Swift platform and concurrency

- Swift language mode is 6.0; the app and package require iOS 18.0 or later (`ios-ui/project.yml`, `ios-backend/Package.swift`). Distinguish deployment minimums from compiler/SDK and test-runtime versions; recorded iOS 27 evidence does not raise that minimum. Check availability and guard newer APIs when needed. See [setup](docs/getting-started.md) and [verification](docs/verification.md) for toolchain evidence.
- Follow existing `@MainActor @Observable` presenters for UI state, `Sendable` domain values/protocols and actor-isolated mutable Data state. Keep these responsibilities within the existing VIPER and Domain/Data boundaries.
- Prefer structured concurrency. For unstructured tasks, define ownership and cancellation; check cancellation and session/request identity before applying asynchronous results. Revalidate state assumptions across `await`, including after logout or account changes.
- Resolve Swift 6 concurrency diagnostics through correct isolation, safe value transfer or justified synchronization. Do not add `@unchecked Sendable`, `nonisolated(unsafe)` or detached tasks merely to suppress diagnostics. Necessary unsafe annotations must be narrowly scoped and document their safety invariant.

## Verification commands

Run from the repository root unless stated otherwise. Use the documented command-line tools for agent verification. See [setup](docs/getting-started.md) for prerequisites.

- Swift layout: `python3 scripts/swift_format.py --check`; use `--write` to apply the pinned formatter.
- Shared client: `swift test --package-path ios-backend`.
- Planning backend: `npm ci --prefix server/planning --ignore-scripts`, `npm run check --prefix server/planning`, `npm test --prefix server/planning` (synthetic + disposable embedded PostgreSQL, no real providers).
- Contract: `.venv/bin/python scripts/check_contracts.py` after installing `scripts/requirements.txt` in the local virtual environment.
- Build: `xcodebuild -project ios-ui/C67.xcodeproj -scheme C67 -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/c67-build CODE_SIGNING_ALLOWED=NO build`.
- UI: get an available destination using `python3 scripts/simulator_destination.py`, then use that destination with the same project/scheme and `xcodebuild test`. Keep mock mode enabled and use `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- C67_DATA_MODE=mock` for Simulator tests so the test host can access Keychain.
- Database: from `server/`, `npm ci`, then `npm run db:test` against a running, migrated local stack. [Server instructions](server/AGENTS.md) cover startup/reset separately.
- Before handoff: `git diff --check`; review new files and ignored configuration for accidental secrets/build output.

Match checks to the change: documentation-only work needs link/path/command consistency and whitespace checks; Swift behavior needs package tests; UI changes need the relevant Simulator check; SQL needs local database tests. Update the affected evidence in [verification](docs/verification.md) when it changes. If a prerequisite is missing, explain the exact unverified layer and continue unaffected work.

Follow the existing Swift Testing patterns for package unit tests; preserve XCTest for app tests and XCUITest. Use behavior-focused names and checks. Reuse or extend the target's existing test helpers before adding new doubles; keep necessary reusable doubles in shared test-support files.

## Code review rules

Flag UI-to-provider coupling, duplicated entities, contract/fixture drift, missing server authorization, broken retry identity, and claims that confuse mock, local and deployed evidence. Check account isolation and snapshot behavior when their code changes. Use CI for mechanical checks; human review still assesses behavior and product scope.


<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
