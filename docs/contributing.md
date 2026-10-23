# Contributing

1. Read [Product context](product-context.md), [Architecture](architecture.md), and [Team starter](team-starter.md).
2. Branch from current `main`; use `<initials>/<short-topic>` (for example `ab/discovery-empty-state`). See [Coding conventions](coding-conventions.md) for branch, commit, file and identifier names.
3. Keep a PR focused on one behavior. Include its purpose, affected areas, tests and remaining limitations.
4. Request review from the owner of every affected boundary. Changes to `contracts/` need client and server review; UI-visible behavior also needs UI review.
5. Merge only after the required CI checks pass, review conversations are resolved, and an eligible teammate approves the PR. Use squash merge; completed task branches are deleted automatically by GitHub.

## Shared conventions

Use English for code identifiers, documentation, comments and PR descriptions. Keep synthetic data clearly labelled. Keep secrets and generated build output out of Git. Commit dependency lockfiles and regenerate the Xcode project from `project.yml` when its configuration changes.

A folder's existence is not an assignment or a requirement to implement that feature. Add shared use cases only when more than one feature needs them. Do not duplicate entities inside VIPER modules or introduce a custom API server solely to fill a placeholder.

## Access and environments

Each teammate needs repository access. Simulator/mock work needs no Supabase access. Server developers use their own disposable local stack; shared Studio access is provided separately through a secure channel. Studio credentials must not be used as traveller authentication.

No CI workflow deploys or resets the homelab. A future deployment needs a reviewed migration plan, a backup/rollback approach and explicit operational authorization. Never commit the homelab `.env` or paste client sessions into issues.

## Definition of done

The assigned flow works in its stated mode, loading/error/empty states are handled, relevant tests pass, and setup/contract changes are documented. Clearly distinguish mock evidence, local database evidence, real-device evidence and deployed-system evidence. Attach UI screenshots when changing presentation.

Area-owner assignment, contributor role changes and CODEOWNERS were deferred by the user. Follow the current [repository settings](repository-settings.md); a required approving reviewer must have eligible write access. Check this separately before the first merge.

## AI-assisted work

Read [AGENTS.md](../AGENTS.md) and the instructions in each affected area. Use the [shared AI workflow](ai/workflow.md), [task template](tasks/TASK-TEMPLATE.md), and implementation/review/handoff prompts. Keep architecture and product decisions in their existing source documents rather than duplicating them in tool-specific rules. Report actual verification evidence, including missing prerequisites.

## First contribution

Complete the relevant items in [the onboarding checklist](onboarding-checklist.md). Read [Coding conventions](coding-conventions.md) and run `python3 scripts/swift_format.py --check` for Swift changes. `--write` applies the shared layout. Keep formatter upgrades separate from feature work.
