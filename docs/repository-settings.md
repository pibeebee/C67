# Repository collaboration settings

Target: `pibeebee/C67`, branch `main`. These are the settings applied through GitHub as part of this setup; Markdown alone cannot enforce them. [The CI workflow](../.github/workflows/ci.yml) defines the corresponding checks.

## Main protection

- Require a pull request and one approving review.
- Dismiss stale approvals when new reviewable changes are pushed.
- Require resolution of review conversations.
- Require the `ios`, `contracts`, `database` and `style` checks from GitHub Actions.
- Require the PR branch to be up to date with `main` before merging.
- Apply protection to administrators; disable force pushes and deletion of `main`.
- Keep required CODEOWNERS review disabled because area ownership was explicitly deferred.

Only squash merging is enabled. GitHub deletes a completed PR's head branch after merge when it can. This does not delete `main` or local branches. Linear history is required on `main`.

## Permissions and first merge

Contributor permissions and CODEOWNERS were intentionally skipped at the user's direction. No collaborator role is changed by this setup. GitHub requires an eligible approving reviewer with write access, and the PR author cannot approve their own PR. If only the PR author has write access, a maintainer must arrange another eligible reviewer before merging. Do not bypass or weaken protection to make an automated self-review count.

Read-only contributors can work in a fork and open a PR; same-repository task branches require write access. Confirm each member's route during onboarding. Keep the technical setup separate from later access decisions.

## Changing repository settings

Treat review policy, required checks and merge settings as a reviewed maintenance change. Record the target and previous values, apply only the authorized settings, then read them back through GitHub to verify. CI contains no token or job that changes repository settings.

References: [Protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches), [CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners).
