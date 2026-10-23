# Team starter and first assignments

## Shared milestone

Demonstrate catalog → detail → personal trip using one contract. Mock mode is ready for parallel UI work. Live creation remains gated on a real traveller session and a separately reviewed server deployment.

| Workstream | Starter available | Suggested first assignment | Acceptance evidence |
|---|---|---|---|
| iOS UI | Runnable VIPER list/detail, mock data, navigation | Refine discovery/detail against the agreed wireframe | Simulator walkthrough including loading/error/empty states |
| iOS Backend | Domain protocol, mock and RPC implementations | Add secure Auth session provider and session lifecycle tests | Expired/missing session handling; no server secrets in app |
| Server | Local config, migration, seed and pgTAP tests | Run database tests, review model against full specification, prepare deployment proposal | Two-account isolation and idempotent trip creation |
| Shared | OpenAPI and fixtures | Review version identity, timestamps, errors and fixture changes together | Contract checks and compatible adapters |

Assign real owners and reviewers before splitting tickets. One person may cover multiple workstreams; shared contracts belong to the whole team. App Auth work concerns traveller accounts, while Studio access concerns developers.

## Starter readiness check

- Every teammate can clone and run the mock app without a key.
- Every iOS developer can run the package tests.
- The server owner can run a fresh local stack, reset only its disposable database, and run pgTAP.
- Everyone understands which parts are mocked and which are remote.
- Repository access, reviewer names and the chosen Xcode version are agreed.

The repo contains the technical starter. Team access provisioning and real-person assignments are not configured by these files.

## Deferred slices

Trip editing, creator publishing, version lifecycle, geospatial search, journaling/media, presence policy, routing/weather, persistence/offline recovery, merge and albums need further contracts and acceptance criteria. Do not activate unresolved product policies from folder names alone.

## ACT evaluation

This starter checks whether the team can build one consistent flow across boundaries. It does not establish that travellers understand or want the product. Evaluate the next UI iteration with reachable travellers and record what they actually do, the task outcome and the decision to revise or continue.

## Shared AI setup

Before assigning implementation tickets, have every member read [the AI workflow](ai/workflow.md) and load the root plus affected area `AGENTS.md` files in their assistant. Use [the task template](tasks/TASK-TEMPLATE.md) for shared acceptance criteria. Try one small task with mock data and review its diff/evidence together before expanding work in parallel. No shared AI account is required.
