# Implementation prompt

Replace the placeholders before sending this to your coding assistant:

```text
Implement the task described in <task file or full task brief> in the C67 repository.

Read the root AGENTS.md and every affected area's AGENTS.md, then inspect the
linked source documents and current code. Check git status and preserve unrelated
changes. Explain the intended outcome, affected boundaries and relevant checks
briefly, then complete the authorized implementation.

Use <agreed mock/live mode>. Follow the existing Discovery module, shared domain
and contract patterns as relevant. The task's acceptance criteria define done;
placeholder folders and old proposals are not new requirements.

If a material product decision is missing, ask a focused question and continue
independent work. Keep routine implementation choices within the approved scope.
Run relevant checks and report what actually passed, failed or could not run.

External actions authorized for this task: <none, or the exact commit/push/deploy
scope explicitly granted by the human>. Do not infer additional authorization.
```
