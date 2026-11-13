# Repository collaboration settings

Target: `pibeebee/C67`, branches `dev` and `main`. The authorized 12 November 2026 policy uses `dev` as the default working branch and `main` as the reviewed release integration branch. Markdown alone cannot enforce settings; verify the GitHub API values after changes. [The CI workflow](../../.github/workflows/ci.yml) defines the promotion checks.

## Main protection

- Require a pull request and one approving review.
- Dismiss stale approvals when new reviewable changes are pushed.
- Require resolution of review conversations.
- Require the `integration` and `ios-smoke` checks from GitHub Actions. The integration job fails unless the PR is from this repository's `dev` branch to `main`; disallowed sources are rejected rather than reported as skipped successes.
- Require the PR branch to be up to date with `main` before merging.
- Apply protection to administrators; disable force pushes and deletion of `main`.
- Keep required CODEOWNERS review disabled because area ownership was explicitly deferred.

## Dev protection and merge methods

- Default branch: `dev`; feature branches start there and open PRs back to it.
- Require a PR, one approving review, dismissal of stale approvals and resolved conversations.
- Do not require cloud status checks for feature PRs to `dev`. Review the local evidence for the actual commit instead.
- Apply protection to administrators; disable force pushes and deletion of both long-lived branches.
- Enable squash merges for feature PRs and merge commits for promotions/synchronization. Linear-history enforcement is disabled on `dev` and `main` because it would prevent ancestry-preserving promotion merges. Rebase merges remain disabled.
- Feature branches may be automatically deleted after merging; protected `dev` and `main` must be retained.

Only PRs targeting `main` trigger automatic CI. No automatic workflow runs on ordinary pushes, feature PRs to `dev` or merging a promotion to `main`. [Full verification](../../.github/workflows/full-verification.yml) and [PoC checks](../../.github/workflows/poc-journey.yml) are manual. Full verification retains the complete app/UI, package, contract, planning and disposable Supabase checks. The automatic smoke workflow runs app unit tests and two critical mock UI flows, not the full UI regression suite. Run broader checks before TestFlight and for relevant database/PoC changes; distribution itself remains manual.

## Permissions and first merge

Contributor permissions and CODEOWNERS were intentionally skipped at the user's direction. No collaborator role is changed by this setup. GitHub requires an eligible approving reviewer with write access, and the PR author cannot approve their own PR. The repository has an explicitly authorized PR-requirement exception for `MorpKnight` on `dev` and `main`, verified on 13 November 2026. This permits merging own PRs without an approving review and also permits bypassing the PR requirement. Required checks remain independent of that exception. Other users retain the approval requirement. Re-read live settings before relying on this account-specific exception.

Read-only contributors can work in a fork and open a PR; same-repository task branches require write access. Confirm each member's route during onboarding. Keep the technical setup separate from later access decisions.

## Changing repository settings

Treat review policy, required checks and merge settings as a reviewed maintenance change. Record the target and previous values, apply only the authorized settings, then read them back through GitHub to verify. CI contains no token or job that changes repository settings. During the initial transition, `dev` can contain the new workflow policy while stable `main` retains its earlier files until the first reviewed promotion; new branches must start from `dev` so they inherit the new trigger policy. Reconcile older PRs with `dev` and retarget them before pushing more changes.

References: [Protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches), [CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners).
