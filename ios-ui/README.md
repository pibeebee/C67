# iOS UI

## Xcode Canvas previews

Open `Features/Home/View/TripHomeRootView.swift` for the full **HOME EMPTY** preview or `Features/Itinerary/View/ItineraryListView.swift` for **ITINERARY LIST**. Each file offers Light and Dark previews. In Xcode, choose **Editor → Canvas** and select **Resume** if prompted. These DEBUG previews use synthetic, in-memory or Sketch sample data; the itinerary map may need network access to load map tiles.

For the additional Sketch states, open `Features/Home/View/TripHomeRootView.swift` and select **HOME EMPTY ADD TRIP · Tap plus**, then tap the plus in the live Canvas to open the native menu. Open `Features/Recommendations/View/RecommendationsProcessingView.swift` for **PREFERENCES PROCESSING 1**, or `Features/Recommendations/View/PlacesRecommendationsView.swift` for **PLACES LISTS** and **PLACES LIST ADDED**. The list previews use Sketch sample content and photos; runtime recommendations use the planner's actual candidate data. See [implementation and checks](../docs/tasks/recommendations-swiftui.md).

## Connected Hi-Fi flow — 11 November 2026

Home now starts one of two draft flows. Get Recommendations opens Q1–Q7, then a confirmation form for an origin, at least one required place, exact times and walking/driving. Add Specific Place opens the compact searchable place list first. Both continue through main-spot/stay preferences, real request processing, itinerary review and a native save-name dialog. Renaming regenerates the proposal and requires another review before saving; it does not rename a saved record through an invented API.

Preferences such as public transport, motorcycle and automatic timing remain wishes in the request text. The confirmation form makes the supported routing mode and schedule explicit. Flexible stay retains the draft duration. A main spot does not become a forced first stop.

A saved trip opens a styled itinerary detail, then a map/status screen. Arrival is manually confirmed per stop. Finishing the last visit moves the trip into History. Live guidance opens Apple Maps; the in-app status UI does not claim turn-by-turn navigation. Existing extension and recalculation controls remain available under Trip options.

Additional Xcode Canvas files:

| Source | Named previews |
|---|---|
| `Features/TripCreation/Preview/AddPlacesDesignPreview.swift` | All six ADD PLACES states, including keyboard/search and the Places sheet |
| `Features/TripCreation/Preview/TripCreationDesignPreview.swift` | Both connected mock creation flows |
| `Features/Itinerary/Preview/ItinerarySaveDesignPreview.swift` | ITINERARY LIST SAVE native name alert |
| `Features/SavedTrip/Preview/SavedTripDesignPreview.swift` | ITINERARY LIST Copy / My Trip, Dark and completed states |
| `Features/Home/Preview/HomeAddedTripDesignPreview.swift` | HOME ADDED TRIP and the HOME Copy 3 variation |
| `Features/ActiveTrip/Preview/TripProgressDesignPreview.swift` | TRIP STARTED, TRIP DONE / per-stop arrival, Dark and large text |

Keyboard and native alerts may require Live Canvas. Preview photos, directions and estimates are sample content. Runtime live place search uses MapKit; mock search returns explicitly named synthetic places. Missing runtime photo/category data uses placeholders. See [implementation and verification](../docs/tasks/hi-fi-ui-completion.md).

## Itinerary review — 11 November 2026

The Home planning editor now opens `Features/Itinerary` after generating a proposal. The HI-FI ITINERARY LIST slice includes the departure summary, numbered stops, travel legs, native map, expandable weather/evidence context and Save Itinerary. Editing a visit or adding a place regenerates the proposal; saving opens the existing trip detail. Missing stop metadata stays explicit. The current planning contract still determines stop order.

For the supplied Sketch content, use the Xcode `ITINERARY LIST` preview or the DEBUG launch argument `--itinerary-preview`. Its photos were exported from the visible Sketch thumbnail layers. Preview actions show a sample-content notice and never save a trip. The normal app uses repository proposals and does not inject the reference's example weather, distances or venues. See [implementation and checks](../docs/tasks/itinerary-list-swiftui.md).

## Native trip home — 11 November 2026

The default entry is now `Features/Home`, sliced from Balaraja Sketch → HI-FI → HOME EMPTY. It uses system SF typography, adaptive canvas colors, native Trip/History tabs and native Liquid Glass buttons on iOS 26+, with material/bordered-button fallbacks on iOS 18. The plus button opens the recommendation/specific-place menu; the location pill opens starting-point search. Completed trips appear in History. Account is available from History or the editor.

The pill displays the actual draft origin label, including the explicit synthetic label in mock mode. It does not assert that the device is in the location illustrated by Sketch. The existing workspace remains accessible with `--planning-workspace`, and Discovery with `--legacy-catalog`. See [task and verification](../docs/tasks/home-empty-swiftui.md).

## Default planning flow — 30 October 2026

`Features/Planning` is now the default SwiftUI/VIPER feature: draft input → optional candidates → proposal/review → My Trips → manual start/arrival/extension/completion and recalculation. Platform helpers own MapKit place search/directions and user-requested Core Location. A marker map accompanies selected places. Native controls and source/uncertainty disclosure use the existing style; no new font/design-system dependency is introduced.

Mock is explicitly synthetic and memory-only. Live uses `PLANNING_SCHEME` / `PLANNING_HOST` plus existing Supabase traveller authentication; model/Apple/service credentials stay on the server. Missing planning configuration reports a visible error while Account stays usable. See [setup](../server/planning/README.md), [planning semantics](../docs/ai-trip-planning.md) and [task evidence](../docs/tasks/ai-trip-planning-implementation.md).

`Resources/PrivacyInfo.xcprivacy` declares app-only UserDefaults use (`CA92.1`) for pending-command recovery, following [Apple's required-reason documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons). It is a required-reason API entry, not a completed App Store data-collection disclosure.

Launch with `--legacy-catalog` to use the preserved Discovery example described below. The existing UI smoke test selects that argument. No iOS tests or Simulator interactions were run for this batch at the user's explicit request; only build/static evidence is recorded. Existing Auth/Apple evidence remains in its dated tasks; a real user Apple sign-in was previously observed, while full device lifecycle acceptance remains separate.

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
