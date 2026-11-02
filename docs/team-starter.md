# Team handoff

Updated 30 October 2026. Start with [product context](product-context.md), [planning semantics](ai-trip-planning.md), [ADR-0009](decisions/0009-personal-planning-implementation.md), [architecture](architecture.md) and [implementation evidence](tasks/ai-trip-planning-implementation.md).

The default native experience now collects user places/preferences/time, presents optional suggestions and a plan proposal, saves a personal trip and supports manual start/arrival/extension/completion plus reviewed remaining-trip recalculation. Mock output is explicitly synthetic. The repository includes the live HTTP/provider adapters and additive SQL; neither the new service nor migration is shared-deployed by this work.

## Next bounded acceptance work

| Area | Next concrete outcome | Evidence needed |
|---|---|---|
| Native app | Exercise Plan/My Trips, account transitions, permission denial, interruptions and larger text | Authorized Simulator/device interaction checks; none run for this batch at the user's request |
| Backend operations | Review a matching-image migration/recovery and service/gateway plan | Fresh backup/restore/isolation checks and explicit deployment scope |
| Providers | Select a model and private Apple/model credentials; validate coverage and response assumptions | Approved bounded real-provider requests, attribution/data-policy review and observed errors |
| Planning quality | Evaluate D extension/C experience-window conflicts, grounded facts and alternatives | Measured factual support, feasibility, tool calls, latency/cost and traveller decisions |
| Product scope | Decide destination edits, skip/partial completion, undo, journal/album links and multi-day/transit | Explicit contracts and user evaluation before extending behavior |

The scheduler and synthetic checks establish software invariants, not travel correctness or product differentiation. Venue research is a bounded website text reader rather than a general web-search or JavaScript browser. Forecast gaps and unverifiable opening hours must remain visible.

Use [AGENTS.md](../AGENTS.md), [AI workflow](ai/workflow.md), [task template](tasks/TASK-TEMPLATE.md), [coding conventions](coding-conventions.md) and [onboarding](onboarding-checklist.md). Keep local implementation, tests, deployment and user evidence separate. Area owners/reviewers remain team decisions. Traveller app sign-in and developer Studio access remain different identities.

Earlier [documentation work](tasks/ai-planning-documentation.md), original manifests and deployed-server records are preserved as historical evidence. New implementation status is in the current task, not inferred from those records.
