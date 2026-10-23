# Starter verification

**23 October 2026.** These checks concern the starter, not the deployed homelab or product validation.

| Check | Result / boundary |
|---|---|
| Swift package | 4 tests pass: snapshot/retry behavior, missing-session boundary, configuration validation, RPC headers/error/date decoding |
| iOS Simulator build | Pass with Xcode 27.1 / Swift 6.4; deployment target iOS 18 |
| Mock UI smoke test | 1 test passes on iPhone 18 Pro Simulator, iOS 27.0: discovery → detail → save |
| Configuration | Dummy live mode/client key and local URL confirmed in the built Info.plist; no live server request implied |
| API contract | OpenAPI 3.1 validates; both JSON fixtures validate; bundled catalog and SQL seed match the authoritative fixture |
| Configuration formats | XcodeGen/workflow YAML and local Supabase TOML parse |
| Project generator | XcodeGen 2.45.4 |
| Supabase CLI | 2.121.0 pinned with npm lockfile; config and migration name generated through CLI |
| Database runtime | Not run locally: Docker engine socket is unavailable; a 14-check pgTAP suite and CI job are provided |
| GitHub Actions | Baseline commit `640f035` passed `ios`, `contracts` and `database`; new conventions/formatter PR is checked separately |
| Homelab / real traveller Auth | Not modified or tested in this change |
| Physical device / offline / field use | Not tested; mock trips are memory-only |

Before shared backend deployment, run the local Supabase database suite with Docker, review the homelab database version and existing schema, implement/verify the traveller session path, and prepare a separate operational deployment plan. The local development stack is not an export of homelab credentials or data.

## Team-conventions setup

- The checksum-verified SwiftFormat 0.64.1 runner successfully downloaded its pinned macOS release, formatted two Swift files for layout only, and passed `--check` for all 15 Swift files.
- The shared package still passes all 4 tests after formatting. Contract/fixture checks, Markdown links/fences, Python syntax and workflow YAML checks pass.
- GitHub protection/merge settings are documented in [Repository settings](repository-settings.md) and verified by reading back the GitHub API.
- Main requires an eligible human approval. Ownership, CODEOWNERS and collaborator roles were explicitly skipped; the setup PR is not automatically merged.
