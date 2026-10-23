# Team onboarding checklist

Copy this checklist into your first task/PR and replace the placeholders. An unchecked item is not evidence that setup succeeded. Each member completes their own checks; access and owner assignments are intentionally outside this setup change.

Contributor: <name / GitHub username>
Workstream(s): <UI / on-device backend / server / shared>
Mac / Xcode / Simulator version: <actual versions>

## Shared setup

- [ ] I can clone the repo and open [Getting started](getting-started.md).
- [ ] I read the product context, architecture and coding conventions.
- [ ] My assistant read root `AGENTS.md` and every affected area's instructions.
- [ ] I understand mock, local Supabase and the shared homelab are different environments.
- [ ] I can create a branch such as `ab/onboarding-check` from current `main`.
- [ ] I have confirmed whether I can push a task branch or need the fork-based PR flow.

## iOS work

- [ ] I opened `ios-ui/C67.xcodeproj` and ran C67 on an iPhone Simulator in mock mode.
- [ ] I opened the synthetic rundown, selected a start time and saved a mock trip.
- [ ] `swift test --package-path ios-backend` passes.
- [ ] `python3 scripts/swift_format.py --check` passes.
- [ ] I recorded the actual Xcode/Simulator versions above; physical-device signing is a separate setup.

## Server/contract work (when relevant)

- [ ] I installed the pinned CLI using `npm ci` inside `server/`.
- [ ] My local Docker engine runs; I started my local Supabase stack.
- [ ] I understand that `npm run db:reset` rebuilds disposable local data and never targets the homelab.
- [ ] After the documented authorized local setup, `npm run db:test` passes.
- [ ] Contract validation passes using the environment from Getting started.
- [ ] I can explain that Studio developer access does not supply a traveller session to the app.

## First collaboration exercise

- [ ] I completed one small task using [TASK-TEMPLATE.md](tasks/TASK-TEMPLATE.md), with observable acceptance criteria.
- [ ] I opened a focused PR with an English title and actual verification evidence.
- [ ] The relevant CI jobs passed; an eligible teammate reviewed the change.
- [ ] I resolved feedback, confirmed the squash-merge result and deleted the completed task branch.

For protected `main`, an approving review must come from someone eligible under GitHub's review rules. Read-only reviews can provide useful feedback but do not satisfy the required write-access approval. Have a maintainer resolve access separately before relying on the merge exercise.
