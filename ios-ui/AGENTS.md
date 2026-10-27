# iOS UI instructions

Apply the [root instructions](../AGENTS.md). Scope: `ios-ui/`.

- Follow the working `Features/Discovery/` VIPER example and [UI README](README.md).
- Read the [design-system guide](../docs/design-system.md) before visual work. Use its documented palette, typography, layout, state and accessibility rules; do not turn the flight examples into C67 features or treat the source's HIG label as verification.
- Put reusable visual tokens and components in [Shared/DesignSystem](Shared/DesignSystem/README.md) when an implementation task authorizes them. Inspect existing code first, reuse native controls and avoid repeating raw style values across features. The guide alone does not mean these components or the Gabarito font are installed.
- Views render state and forward actions. Presenters own main-actor presentation state. Interactors use domain/application protocols. Routers define navigation; Assembly and `App/CompositionRoot/` wire dependencies.
- Import shared entities from `C67Domain`; do not create a second Rundown/Trip model per screen. Presentation-specific view state is allowed.
- Keep network calls, DTO decoding and vendor SDKs out of Views/Presenters. Concrete Data implementations belong in the composition root.
- Cover loading, empty, failure, retry and duplicate-tap behavior when relevant. Keep navigation usable with larger text and accessible controls. Request device permissions only for a relevant user action.
- Default to mock for independent UI work; show its synthetic/memory-only limitations. A live URL is not evidence that RPCs are deployed.
- `project.yml` is the build-configuration source. After changing targets/source groups, run `xcodegen generate --spec ios-ui/project.yml` from the root and commit the generated project too. Do not modify generated project settings as a second source.
- Keep local overrides in ignored `Configuration/Development.local.xcconfig`. Never add server secrets to bundle settings.

## Verification

From the root, run the documented Simulator build for Swift/UI changes. For interaction changes, run the C67 scheme's relevant UI test in mock mode, using a destination from `scripts/simulator_destination.py`. Tests are under `Tests/UI/`. Report device/runtime and whether a manual walkthrough or automated test ran. Do not claim physical-device or iOS 18 runtime evidence from a newer Simulator.
