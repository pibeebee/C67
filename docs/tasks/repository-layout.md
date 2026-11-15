# Task — Organize Travelant and rewrite the README

Status — Ready for review
Owner — Giovan, with implementation by Codex
Branch — gi/repository-layout

## Outcome

Developers can find the app, packages, services, experiments, design assets and current documentation from the repository root. The default product builds independently of experimental server source.

## Scope and authorization

The user approved the layout draft and requested README creation using the create-readme skill, followed by commit, push and a PR to dev. This task reorganizes tracked content, fixes path references and adds regression coverage for the relocated Pocket service. Existing iPad orientation changes and private configuration remain in the original checkout. Shared services and already uploaded binaries retain their existing release paths.

## References

- [Layout decision](../architecture/decisions/0011-repository-layout.md)
- [Path mapping and checkout migration](../guides/repository-layout.md)
- [Research inventory](../../research/README.md)
- [Pocket service](../../server/pocket/README.md)

## Acceptance

- App, package and service entry points resolve from their new locations.
- Pocket image uses server/pocket/src and canonical package resources.
- Imported publication hashes and frozen evaluator sources remain verifiable.
- Root README includes the existing app icon, current architecture, setup, directory map, verification and evidence boundaries.
- Maintained documentation links and deployment build contexts resolve.

## Verification

Executed locally on macOS with Xcode 27.2.

| Check | Result |
| --- | --- |
| PocketEngine Swift package | 12 XCTest tests passed |
| C67Backend Swift package | 47 Swift Testing tests passed |
| Pocket Python HTTP/CLI regression | 4 tests passed from an unrelated working directory |
| Integration-promotion policy | 4 tests passed |
| PoC Python scripts | 66 tests passed |
| Planning API | Type and format checks passed, 22 tests passed |
| Contract/schema/fixture copies | Passed |
| Swift format | 0 of 660 files require formatting |
| iOS smoke | iPhone 18 Pro Max Simulator, iOS 27.0; 76 Swift Testing app tests passed, 15 XCTest app cases executed with 2 live cases intentionally skipped, and both selected UI flows passed |
| Pocket Docker | Image built; health/auth/catalog/body limit/private-route/method checks passed, 8 HTTP cases; nginx configuration valid; no host ports |
| Compose recipes | Pocket local/homelab, media and planning configurations parsed |
| Research evidence | 3,415 imported copies and 32 previously reviewed source evolutions verified against existing manifests |
| Publication portability | Passed; 61 previously missing historical attachments recorded exactly in unavailable-local-links.json |
| Maintained Markdown links | All relative targets resolved |

Docker smoke testing first exposed container directory permissions and a path default that assumed a deeper filesystem root. The image now sets directory/file permissions explicitly, and resource lookup handles both checkout and container roots. Final server/native/Docker checks passed after correction.

The 61 missing attachments were reproduced in the original checkout before relocation. Their reports were preserved and an exact source/target ledger was added; no substitute evidence was generated. Product runtime behavior, API/schema meanings, and the CI trigger policy retain their existing scope. Build/fixture success does not establish physical-device operation or real recommendation quality.

## Handoff

Open apps/ios/C67.xcodeproj after updating. Follow the layout guide when relocating ignored client configuration. See [TestFlight operations](../operations/testflight.md) for releases and [Pocket homelab deployment](../../server/deploy/pocket/README.md) before any shared server update.
