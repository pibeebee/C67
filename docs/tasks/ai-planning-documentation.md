# Task: Align documentation with AI trip planning direction

Status: Done — historical documentation pass. Superseded implementation status: [personal planning task](ai-trip-planning-implementation.md).
Owner: Giovan (requesting owner); Codex (document edits)
Reviewers: Not assigned; product and affected implementation owners can review the local documents
Branch: gi/ai-planning-docs
Updated: 29 October 2026

## Outcome

The team can read one consistent product direction: AI-generated recommendations from user-selected places/preferences/time, context from routes/weather/place sources, and recalculation during a trip. The documents clearly distinguish this target from the catalog-based code and existing deployed contracts.

## Scope and dependencies

- Allowed: Markdown context, architecture, roadmap, handoff, ADR and contract documentation, plus dated source snapshots in the research workspace.
- Deferred: Swift/HTML/JS/CSS, model/browser setup, OpenAPI/schema/fixtures, migrations, live services and deployment.
- Decisions: the user's 29 October clarification, recorded in [product context](../product/product-context.md) and [ADR-0008](../architecture/decisions/0008-ai-trip-planning-direction.md).
- Environment: local documentation only. No provider or shared backend requests.
- External actions authorized: none. No commit, push, PR or deployment requested.

## References

[AI target](../architecture/ai-trip-planning.md), [architecture](../architecture/architecture.md), [roadmap](../architecture/server-roadmap.md), [current contract](../../contracts/README.md), and [existing backend decision](../architecture/decisions/0005-backend-mvp.md).

## Acceptance criteria

- [x] Current context documents describe confirmed user control, inputs, AI/API/browser direction and active recalculation.
- [x] Provider, runtime, ranking, durations and application policy remain explicitly open.
- [x] Existing source/version semantics, planned-only guards and verification evidence are not rewritten as new runtime behavior.
- [x] Existing research context and technology sources are preserved with checksums in the source workspace.
- [x] Local links, Markdown fences/tables, snapshot integrity and whitespace checked.
- [x] Protected application/schema/fixture/generated files confirmed unchanged.

## Verification plan

Check modified documentation paths and local links (including the source workspace), balanced fenced blocks, table structure, snapshot SHA-256 entries and `git diff --check`. Compare protected non-Markdown file hashes and API/fixture paths with the pre-edit state. Do not run app/database/provider tests for a documentation-only change.

## Result and handoff

- Written: current product/target/ADR and synchronized entry points, handoff, roadmap and contract context. The research workspace also contains the current CBL, flow, engine and validation plan.
- Checks: `python3 /tmp/check_c6_docs_20261029.py` checked 57 active/annotated Markdown documents for local paths/anchors, fences and table structure; no issues. All 15 pre-update source snapshot hashes matched. All 244 protected non-Markdown file hashes matched, including code, existing contracts/fixtures and wireframe assets. `git diff --check` passed in both repositories. The checker and reports are temporary local tooling, not application changes or committed test infrastructure.
- Unverified: AI/provider/browser capability, route/weather coverage, runtime behavior, field usefulness, costs and latency.
- Next task: select a bounded contract/capability spike after resolving the relevant open decisions; owner not assigned.
- Commit/push: not performed. C67 documentation is on local branch `gi/ai-planning-docs`; the research workspace retained its existing branch and unrelated changes.
