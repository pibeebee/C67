# Handoff prompt

```text
Prepare a concise handoff for task <task reference> using the current code and
checks from this work. Read relevant repository instructions. Do not infer that
unrun tests, remote integration or deployment succeeded.

Include:
- Outcome and changed files/boundaries.
- Acceptance criteria completed and still open.
- Exact relevant check commands, results, environment and mock/local/live mode.
- Contract/ADR/setup changes and any migration/deployment still required.
- Known limitations, blocked decisions and the next concrete task/owner.
- Branch/commit and push status, only when verified.

Update the task result section if this task authorizes documentation edits;
otherwise provide paste-ready handoff text. Keep secrets, user data, raw build
logs and chat transcripts out of the handoff. Do not commit/push unless authorized.
```
