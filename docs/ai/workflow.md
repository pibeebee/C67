# Working with AI as a team

Use this workflow for any coding assistant. Keep the task, context and acceptance evidence in the repository so another teammate can continue with a different tool.

## 1. Load the same context

Open the repository root. Ask the assistant to read `AGENTS.md`, the instructions for all affected areas, the task brief, and the linked product/architecture/contract documents. Confirm that it identifies the actual starter state before proposing changes.

Instruction discovery differs between tools. If your assistant does not automatically load `AGENTS.md`, attach or explicitly ask it to read the root and affected area files. When adding tool-specific configuration later, make it a small entry point referencing these sources instead of copying all the rules. See the [AGENTS.md format](https://agents.md/) and [Codex instruction documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

Personal/global instructions can differ between teammates. Confirm the active instruction sources when behavior is surprising. Repo instructions guide the assistant; they do not configure account permissions, enforce sandboxing, or replace review and CI.

## 2. Create a bounded task

Copy [TASK-TEMPLATE.md](../tasks/TASK-TEMPLATE.md) to a short task file under `docs/tasks/`, or use the same fields in the team's issue tracker. Choose a real owner and reviewers; include the intended outcome, allowed areas, dependencies, acceptance criteria and checks.

Reference existing decisions and code examples. Name unresolved product questions instead of letting the assistant invent rules. If a dependency is unfinished, state whether to use the agreed mock, prepare an interface, or wait for a required decision.

## 3. Implement and verify

Use [the implementation prompt](prompts/implement.md). Ask for a short scope/check plan, then proceed with the work already authorized. Routine edits do not need repeated approvals. A material scope/architecture change or an external action beyond the user's authorization needs a decision first.

Use a task branch under the team's naming convention. Keep each change focused; let mock data unblock UI while keeping the shared contract intact. Run the checks appropriate to the changed layer. Record exact commands, outcomes, mode and missing prerequisites. Never paste real sessions or shared credentials into a prompt or task file.

## 4. Review the diff

Use [the review prompt](prompts/review.md) against a named branch/commit/diff. A fresh session or another teammate's assistant can help, but a second model response is not proof of correctness. Review findings against the code and rerun a targeted check when a fix warrants it.

Human reviewers assess behavior, architecture and product intent. CI checks mechanical and executable properties. Neither guarantees that instructions were followed or that users want the feature.

## 5. Hand off the result

Use [the handoff prompt](prompts/handoff.md). Update the task's result/next steps and any changed source documentation. Report completed work, relevant evidence, limitations and the next owner. Keep mock, local database, real-device and deployed-system evidence separate.

Commit/push when authorized. Keep raw build output and credentials out of Git; summarize evidence and attach safe screenshots when useful. Do not append session transcripts to `AGENTS.md` or treat a prompt template as an architecture decision.

## Team setup

Each member needs repository access, a compatible Xcode version recorded in the onboarding checklist for iOS work and the relevant local tools. They may use different assistants. Shared source files, fixture checks, branch/PR practices and review provide consistency; no shared AI account or private skill installation is required by this repo.

Use [Coding conventions](../coding-conventions.md) for names and formatting. Link the completed [onboarding checklist](../onboarding-checklist.md) from the first task rather than assuming another teammate's successful setup applies to your machine.
