# Shared design system

Read the [design-system guide](../../../../docs/product/design-system.md) and [UI agent instructions](../../AGENTS.md) before adding visual code here. The guide is the single reference for the supplied palette, Gabarito type scale, layout, native component patterns and accessibility expectations; do not duplicate those tables in instruction files.

`TripGlassCapsule` supplies the Home location pill's native interactive glass treatment on iOS 26+ and regular material fallback on iOS 18. `Resources/Colors.xcassets/TripCanvas` records the HOME EMPTY Light canvas (#F2F2F7) and an adaptive black Dark variant. System primary/secondary text and blue action tint provide the remaining Home roles. The source frame uses SF Pro, so Home uses native Dynamic Type text styles. Gabarito is not installed; existing feature screens retain their current native styles.

When an implementation task authorizes visual work, place reusable tokens, text-style helpers and components here as needed. Preserve Dynamic Type, semantic Light/Dark appearance and native control semantics. Keep networking, provider SDKs and business logic outside the design system.

Update [project.yml](../../project.yml) only if the implementation requires a build/resource configuration change, then follow the documented project-generation workflow. Adding this Markdown reference alone does not require regeneration.

`AppColor` names the semantic color roles backed by `Resources/Colors.xcassets` (canvas, surface, brand fill, accent text, on-brand, primary/secondary text). `AppFont` maps the Balaraja Sketch SF Pro type scale to Dynamic Type text styles. New feature code should use these roles instead of `Color("…")` strings or fixed font sizes; existing screens have not been migrated.

Reusable single-choice question pieces live in `Shared/Components`: `QuestionTitle` (bold title with accent-highlighted words), `ChoiceOptionButtonStyle`, `ChoiceOptionList` and the `SingleChoiceQuestionView` layout used by the HI-FI `PREFERENCES` question frames (first adopted by `Features/Preferences` for Q2).

Question components added for Q1–Q7: `QuestionScaffold` (title, content, optional bottom action, native Skip toolbar), `QuestionPrimaryButton` (native prominent capsule Next), `ChoiceChip` (native bordered/bordered-prominent capsule toggle with an SF Symbol) and `FlowLayout` (wrapping `Layout` for chips). The flow lives in `Features/Preferences`; every question file has `#Preview`s for unselected, selected, and Dark at an accessibility text size.

Sketch (Balaraja Sketch, HI-FI) is the visual source of truth: take colors, opacity, spacing, radii and copy from it. When a Sketch detail conflicts with a native Apple component's behavior or appearance, keep the native component (for example the system back button, toolbar buttons, the disabled state of prominent buttons and the native `Slider`) and match Sketch only where the native component allows, preferably through system semantic colors such as `tertiarySystemFill`.

The native launch screen uses the adaptive `TripCanvas` color. The sign-in screen uses `TravelantsMark` with the standard Apple sign-in control. The historical logo animation is available to previews and rendering tests through `SplashFrameView` and `SplashTimeline`.

Place and wait-state components: `PlaceThumbnail` (rounded place photo with a map-pin fallback), `CheckmarkRow` (native-style selectable row with trailing checkmark, used by `Features/MainSpot`) and `ProcessingStatusView` (headline, highlighted message and native large spinner, used by PROCESSING 1 in `Features/Recommendations` and PROCESSING 2–4 in `Features/TripProcessing`). `AppColor.secondaryBackground` is the system secondary background used for cards on white sheets (Sketch `Backgrounds/Light/Secondary`).
