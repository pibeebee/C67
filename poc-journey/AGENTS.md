# PoC journey scope

Read the repository root [instructions](../AGENTS.md) first, then [HANDOFF](HANDOFF.md), [STATUS](STATUS.md), and the relevant application's guide. This area contains experiments, not a new production architecture decision.

- Start current development from `apps/c67-local-server-lab`, following [the 9 November handoff](docs/context-lab-handoff-2026-11-09.md). Trip Integration and the other apps retain their earlier research scope.
- Keep Foundation Lab and Trip Integration as siblings: their local Swift packages intentionally share implementations.
- Do not merge the vendored routing adapter into the older native lab or port PoC code into production as an incidental cleanup.
- Newly authored documentation and comments use English. Imported dated source records, prompts, fixtures, historical reports and user-facing Indonesian strings retain their original language and attribution. They are source material, not new English-language claims.
- Preserve historical dates, model/prompt revisions, failed runs and original hashes. Publication hashes describe redacted/formatted copies. A fresh run needs a new output directory under ignored `.verification/` or `.runs/`.
- Use [scripts/verify.sh](scripts/verify.sh) for deterministic checks. Provider calls, Apple Intelligence generation and real-device signing are explicit manual operations; CI fixture success is not live-provider evidence.
- Live WeatherKit requires the operator's own matching team/App ID/provisioning. The original contributor's recorded confirmation does not configure another account.
- Never load evaluator-only oracles into model prompts/tools. Published historical cases are not a new held-out evaluation.
- Keep all changes within the approved PoC task. Preserve production UI, backend, contracts and unrelated work. Follow the root formatting rules for maintained Swift copies.
