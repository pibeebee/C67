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

`App/CompositionRoot/` chooses the concrete repository. Views must not call Supabase or decode API payloads. The detail screen belongs to this small example module; Account provides email/password sign-in, registration, confirmation/resend, recovery/reset and session state using the same roles. Open it from
the Discover toolbar in live mode; mock mode explains its synthetic boundary without signing in.
Other feature folders remain unimplemented placeholders.

`project.yml` is the XcodeGen source; regenerate and commit `C67.xcodeproj` after changing targets/source groups. Base defaults are shared; Debug includes the ignored Development.local.xcconfig and Release includes a separate Production.local.xcconfig. See [native Auth setup](../docs/native-auth.md). Client configuration is compiled into the app and must contain no server secrets.

## Design system

The [shared design-system guide](../docs/design-system.md) records the supplied visual reference: Gabarito text styles, Royal Blue/Mint/Navy brand colors, semantic Light/Dark roles, spacing, native components, feedback and accessibility. Read it together with [the UI agent instructions](AGENTS.md) before visual work.

[Shared/DesignSystem](Shared/DesignSystem/README.md) is the home for future reusable visual code. The guide is documented; font assets, theme tokens and shared components are not implemented yet. The existing Discovery screen still uses native SwiftUI styles. Flight-booking examples in the reference do not add product requirements.

Registration input, accessibility-size scrolling and system callback rejection passed on Simulator; see the Auth task for evidence and device/delivery limits. The C67 scheme includes native Account/Keychain/form tests and UI smoke tests for mock discovery →
detail → save and the mock Account boundary. Simulator tests require ad hoc signing:
`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- C67_DATA_MODE=mock`.
The Keychain test uses unique synthetic items and removes them afterward. Mock trips are not persisted. See [Getting started](../docs/getting-started.md).

Native Sign in with Apple uses the official AuthenticationServices button, the domain authentication
protocol and the existing session actor. The capability/entitlement is declared in project.yml.
The homelab provider is active. Developer Program provisioning and a real authorization remain pending;
see [Apple setup](../docs/apple-auth.md).
