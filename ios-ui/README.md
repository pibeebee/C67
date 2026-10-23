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

The UI smoke test covers mock discovery → detail → save. Mock trips are not persisted. See [Getting started](../docs/getting-started.md).
