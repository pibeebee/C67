# Coding conventions

Use English for identifiers, comments, documentation, commit messages and PR titles. These conventions extend [the architecture](architecture.md); they do not introduce new product behavior or replace language idioms.

## Branches, commits and PRs

Start each task from current `dev` and name the branch `<initials>/<short-topic>` using lowercase letters, numbers and hyphens for the topic. Examples: `ab/discovery-search`, `cd/auth-session-refresh`, `ef/trip-copy-rpc`. Initials identify the contributor; a branch represents one task. Use additional short words when initials collide.

Use short-lived task branches. Run relevant local checks, attach the commit/toolchain/results to one focused PR to `dev`, resolve review comments and obtain one eligible teammate's approval. Squash feature PRs into `dev`. Feature PRs do not automatically run cloud CI. Pull the new `dev` before starting another task. Do not rewrite someone else's branch.

When a reviewed integration batch is ready, open a same-repository `dev` -> `main` PR. Required `integration` and `ios-smoke` checks run on its merge result. Keep this PR closed until the batch is ready; every subsequent update to an open promotion can trigger CI again. Promote with a merge commit to preserve the ancestry of the two long-lived branches, then synchronize `main` back into `dev` through a reviewed PR. Do not delete or force-reset `dev`. See [repository settings](repository-settings.md).

Use `bash scripts/verify_local.sh quick` for the local package/backend/contract/format checks, `ios-smoke` to include app unit tests and two critical mock UI flows, or `ios-full` for all mock app/UI tests. All modes record the commit, working-tree state, toolchain and log path. UI modes also produce a result bundle. Run tests specific to the changed behavior in addition to this baseline. Database migrations require isolated database checks; PoC/provider changes require their appropriate suites. The manual Full verification and PoC workflows retain those broader checks. TestFlight distribution remains a separate manual release action.

Commit messages and the final PR title use `<type>(<scope>): <description>`. Scope is optional; use `ios-ui`, `ios-backend`, `server`, `contracts`, `docs` or `ci` when useful.

```text
feat(ios-ui): add discovery search
fix(server): preserve trip retry identity
test(ios-backend): cover an expired session
docs: clarify local setup
chore(ci): add formatter checks
```

Supported types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`. Describe the actual behavior in the imperative. `refactor` preserves behavior. Avoid vague titles such as `update`, `final` or `fix stuff`. No release automation depends on these message types yet.

## Swift names

| Element | Convention | Example |
|---|---|---|
| Struct/class/enum/protocol | `UpperCamelCase` | `Trip`, `DiscoveryPresenter`, `RundownRepository` |
| Enum cases, functions, properties, locals | `lowerCamelCase` | `notFound`, `listRundowns()`, `selectedRundown` |
| Boolean | A readable condition/capability | `isLoading`, `hasLocationPermission`, `canSaveTrip` |
| An operation with side effects | Clear action and useful argument labels | `createTrip(from:startsAt:requestID:)` |
| Identifier property | `id` for Identifiable; descriptive `ID` suffix elsewhere | `id`, `sourceVersionID`, `requestID` |
| File | Name of its primary type | `DiscoveryPresenter.swift` |
| XCTest file/type | Feature or behavior + `Tests` | `StarterUITests.swift`, `StarterUITests` |
| Test function | State the behavior verified | `retryReturnsExistingTrip()` |

Choose names that read clearly at the call site. Use domain terms consistently. In current catalog-based payloads, a creator's published rundown version differs from a traveller's personal trip. New AI proposals have their own input/proposal identity as described in [ADR-0008](decisions/0008-ai-trip-planning-direction.md); do not invent creator IDs for them. A `Stop` is an occurrence in a sequence. Preserve current shared-contract meanings until a compatible implementation changes them. Document an approved terminology change before renaming it across layers.

Protocols describe a capability or role. Existing examples are `RundownRepository`; do not add `Protocol` mechanically. Implementations may express their source, such as `MockRundownRepository` and `SupabaseRundownRepository`.

Keep VIPER role suffixes: `DiscoveryView`, `DiscoveryPresenter`, `DiscoveryInteractor`, `DiscoveryRoute`/`DiscoveryRouter`, and `DiscoveryAssembly`. Prefer the existing typed route for simple navigation; introducing a router class is not mandatory. Import shared entities from Domain rather than copying them into each feature.

Name a file after its main type; small related supporting types can remain together. Split types when they need separate ownership or become difficult to navigate, not to satisfy a rigid one-type-per-file rule. Avoid ambiguous shared buckets such as `Helper`, `Manager` and `Utils`; name their actual capability.

## Folders, scripts and SQL

| Element | Convention | Example |
|---|---|---|
| Monorepo roots and Markdown documents | `kebab-case` | `ios-backend/`, `getting-started.md` |
| iOS features/layers/roles | `UpperCamelCase` | `Discovery/Presenter/`, `Domain/Entities/` |
| Server modules | Lowercase domain names | `accounts/`, `trips/`, `media/` |
| Python scripts | `snake_case.py` | `check_contracts.py`, `swift_format.py` |
| SQL tables/columns/functions | `snake_case` | `rundown_versions`, `source_version_id`, `create_trip` |
| SQL tables | Plural noun | `trips`, `rundown_versions` |
| SQL migrations | CLI-generated timestamp + `snake_case` description | `<timestamp>_add_trip_status.sql` |
| API JSON | Follow the published contract, not a universal case conversion | `source_version_id`, `p_version_id` |

Create migrations through the pinned CLI rather than typing timestamps. Keep existing paths when introducing conventions; do not run a broad rename without a scoped reason. Treat API name changes as compatibility changes. Map wire keys deliberately when Swift naming differs; do not silently rename payloads to match Swift.

## Formatting

Swift uses four-space indentation and LF endings. [`.swiftformat`](../.swiftformat) is the authoritative layout configuration; [the tool manifest](../tools/swiftformat.json) pins SwiftFormat and its official macOS archive checksum. The runner checks the downloaded archive and executable version and caches the binary in ignored `.tools/`. No global Homebrew formatter is required.

From the root, using Python 3.11+ on macOS:

```sh
python3 scripts/swift_format.py --write
python3 scripts/swift_format.py --check
```

The first run downloads the pinned binary from its official GitHub release; network access is required once per checkout/cache. The small explicit rule list handles layout only. It does not enforce semantic naming, reorder imports, rename declarations or replace code review. Run it after changing Swift code. CI runs `--check` and fails on drift; it does not rewrite a PR.

Other files follow [`.editorconfig`](../.editorconfig). Generated Xcode configuration still comes from `ios-ui/project.yml`. Keep dependencies and formatter version upgrades separate from unrelated feature changes.

Reference: [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/), [SwiftFormat](https://github.com/nicklockwood/SwiftFormat).

The two focused-English evaluator snapshots listed in
evaluations/foundation-models-2026-11-04/focused-english/freeze.sha256 are excluded from
automatic Swift layout changes so their recorded source hashes remain reproducible.
Maintained app/package sources, including the other evaluation harness copies, stay covered.
