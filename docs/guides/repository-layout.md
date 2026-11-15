# Repository layout

Travelant groups executable applications, reusable packages, hosted services, experiments, and design material by their role. Module and product names remain C67, C67Domain, C67Data, and PocketEngine.

| Earlier path | Current path |
| --- | --- |
| `ios-ui/` | `apps/ios/` |
| `ios-backend/` | `packages/C67Backend/` |
| `poc-journey/` | `research/poc-journey/` |
| `tripsense-poc/` | `research/tripsense-poc/` |
| `evaluations/` | `research/evaluations/` |
| `Claude outputs/` | `design/branding/source/` and `design/branding/exports/` |
| `docs/decisions/` | `docs/architecture/decisions/` |
| Root product/design documents | `docs/product/` |
| Root setup/team documents | `docs/guides/` |
| Repository/backend operations | `docs/operations/` |
| Earlier homelab plans and results | `docs/history/` |
| `docs/verification.md` | `docs/testing/verification.md` |
| `server/deploy/media-worker.compose.yml` | `server/deploy/media/media-worker.compose.yml` |
| `server/deploy/planning-api.compose.yml` | `server/deploy/planning/planning-api.compose.yml` |

## Ownership

- `apps/ios/project.yml` owns app/project configuration. Regenerate with XcodeGen after changing it.
- `packages/C67Backend` owns the existing on-device Domain/Data Swift package.
- `packages/PocketEngine` owns the native engine and canonical catalog/taxonomy resources.
- `server/pocket/src` owns the maintained Python service. Its Docker build copies code from this directory and catalog resources from PocketEngine.
- `contracts` owns wire contracts and synthetic fixtures. Root sync/check scripts locate their package copies at the new path.
- `research` owns experiments and their evidence. Frozen reports and sources retain original hashes.
- `design` owns branding source/export archives. App resource catalogs own shipped assets.
- `scripts` owns executable repository checks. `tools` holds version/checksum manifests for external tools.

## Updating an existing checkout

Close the old Xcode project before updating, then reopen `apps/ios/C67.xcodeproj`. Local settings are intentionally ignored by Git. Move your own `Development.local.xcconfig` and `Production.local.xcconfig` from `ios-ui/Configuration/` to `apps/ios/Configuration/` when updating an existing checkout. Keep the original files recoverable until the new configuration has been checked. Do not commit their values.

App scheme and bundle identifier remain unchanged. A folder move does not change an already uploaded TestFlight build or the running homelab service. Deployment from a new revision is a separate operational action. Existing shared Supabase migration history remains in `server/supabase/migrations/`.

For older experiment commands beginning with `poc-journey/`, `tripsense-poc/`, or `evaluations/`, prepend `research/`. Paths inside frozen logs/manifests describe their original capture and are retained as provenance.
