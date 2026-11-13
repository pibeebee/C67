# ADR 0011 — Organize the repository by runtime and purpose

Status — Accepted on 13 November 2026 following the user's review of the proposed layout.

## Context

The repository grew from separate native/server roots into a maintained Pocket product with extensive experimental source and evidence. The on-device package was named ios-backend, experiments occupied several root directories, and the deployed Pocket image copied runtime code from the PoC tree. Documentation mixed current setup with dated plans.

## Decision

Group the iOS app in `apps/ios`, the Domain/Data package in `packages/C67Backend`, and retain `packages/PocketEngine`. Keep runtime module/product names and public contracts stable. The maintained Pocket server owns its Python source under `server/pocket/src`; its resource source remains the canonical PocketEngine catalog and taxonomy.

Group whole experiment trees under `research` and branding material under `design/branding`. Preserve imported and frozen source/evidence hashes. Organize documentation into product, architecture, guides, operations, testing, tasks, AI workflow, and history. Record the earlier-to-current path mapping in the [layout guide](../../guides/repository-layout.md).

## Consequences

XcodeGen, local package references, fixtures, Compose build roots, scripts and workflows must use the new locations. Existing ignored client settings need deliberate relocation by each developer. Previously uploaded binaries and running homelab releases are independent artifacts. Deployment of a new revision requires its own operational verification.

Earlier experimental scripts/logs can contain historical root-relative paths. Preserve their evidence and use the mapping when reproducing them. Exactly identified unavailable historical attachments are recorded separately, and new broken links still fail portability checks.
