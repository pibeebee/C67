# iOS UI

Open `C67.xcodeproj`, select **C67**, and run an iPhone Simulator. Default mode is mock; no server or key is needed.

`Features/Discovery/` is the working VIPER example:

| Part | Responsibility |
|---|---|
| View | Render list/detail state and forward user actions |
| Presenter | Main-actor state, loading/saving/error handling, retry identity |
| Interactor | Execute repository operations without SwiftUI |
| Router | Typed navigation destination |
| Assembly | Construct the feature with injected dependencies |
| Entity | Imported from `C67Domain` in `../ios-backend` |

`App/CompositionRoot/` chooses the concrete repository. Views must not call Supabase or decode API payloads. The detail screen belongs to this small example module; other feature folders remain unimplemented placeholders.

`project.yml` is the XcodeGen source; regenerate and commit `C67.xcodeproj` after changing targets/source groups. Configuration defaults live in `Configuration/Base.xcconfig`; copy the example to the ignored local override file when needed. Client configuration is compiled into the app and must contain no server secrets.

## Design system

The [shared design-system guide](../docs/design-system.md) records the supplied visual reference: Gabarito text styles, Royal Blue/Mint/Navy brand colors, semantic Light/Dark roles, spacing, native components, feedback and accessibility. Read it together with [the UI agent instructions](AGENTS.md) before visual work.

[Shared/DesignSystem](Shared/DesignSystem/README.md) is the home for future reusable visual code. The guide is documented; font assets, theme tokens and shared components are not implemented yet. The existing Discovery screen still uses native SwiftUI styles. Flight-booking examples in the reference do not add product requirements.

The UI smoke test covers mock discovery → detail → save. Mock trips are not persisted. See [Getting started](../docs/getting-started.md).
