# Review prompt

```text
Review <explicit commit, branch diff or working-tree scope> for task <task reference>.
This request is read-only; do not edit, commit or push changes.

Read the root and affected area AGENTS.md files, task acceptance criteria and
relevant architecture/contract sources. Inspect the actual diff and its callers.

Look for correctness/regression risks, boundary violations, account isolation,
snapshot/retry behavior, async state handling and contract/fixture drift where
relevant. Distinguish an observed defect from an untested concern. Verify any
claimed test evidence against available results and state its limits.

Lead with actionable findings, most significant first. For each finding include
the file/line, trigger, impact and smallest useful verification/fix. Avoid
speculative or style-only findings. If no actionable issue is found, say so and
name the remaining verification gaps. Do not claim the review proves safety or
product validation.
```
