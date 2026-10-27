# Task: document the supplied UI design system

Status: Ready for review
Owner: Giovan
Reviewers: UI/design owner
Branch: `gi/design-system-guide`
Base: `origin/main` at `53732bc` on 27 October 2026

## Outcome

UI developers and coding agents can find the visual reference through the existing instructions, use its readable values consistently, and distinguish documentation from runtime implementation.

## Scope and dependencies

- Allowed areas: agent instructions, UI README, design-system reference and documentation evidence.
- Source: the user-supplied image identified in [the guide](../design-system.md).
- Deferred: Swift styling, fonts/dependencies, Xcode configuration, product/navigation decisions, backend changes and a formal HIG audit.
- External actions authorized for this task: commit and push `gi/design-system-guide`, then open a PR to `main`. Merge and deployment are outside this authorization.

## Acceptance criteria

- [x] Root and UI instructions lead to a single shared design reference.
- [x] Readable colors, type scale, spacing, component patterns and accessibility expectations are recorded in English.
- [x] Unreadable source values, flight-template examples and implementation gaps are explicit.
- [x] No runtime code or existing backend branch is changed.

## Verification plan

Check local Markdown links, source paths, fences, transcription consistency, whitespace and documentation-only scope. Verify the original checkout remains clean. Simulator/database tests are not needed for this documentation change.

## Result and handoff

- Implemented: [design-system guide](../design-system.md), linked agent/UI instructions and [implementation-folder README](../../ios-ui/Shared/DesignSystem/README.md).
- Verification: see the dated design-system documentation entry in [verification](../verification.md).
- Next owner: UI/design owner for a separately scoped font/token/component implementation task.
- Publication: authorized for commit, push and PR. Use the branch history and GitHub PR for the resulting revision and current review/check status.
