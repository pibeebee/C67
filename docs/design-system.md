# C67 design system

**Documented reference — 27 October 2026.** Audience: UI developers, designers and coding agents. Use this guide to keep future C67 visual work consistent with the user-supplied reference. This documentation change does not install fonts, implement a theme, restyle screens or change product/API behavior.

## Source and interpretation

The source is the user-supplied composite image `codex-clipboard-4675d83d-c93a-47de-95c1-328e3524b68e.png` (4480 × 5120). SHA-256: `71c84c2e86cc0d2cdf3e7645b672d5f8c96372e3a3a43dc276826d8b85f825d7`. It includes Foundations, Components, Screen templates, Semantic tokens, Buttons & actions, Forms & selection, Navigation, Feedback, Content & media, Accessibility & states, Typography, Color & Icons, and Gabarito Style Library boards. This portable transcription is the repository reference; the original attachment is not bundled here.

The source labels itself “iOS 27 · HIG-aligned template.” This is a source label, not an Apple endorsement or a completed HIG audit. The app's deployment target remains iOS 18 in [project.yml](../ios-ui/project.yml). Respect that target and check availability before adopting newer platform APIs or materials.

Flight search, booking, fares and the example Explore/Trips/Offers/Saved/Profile tabs illustrate component use. They do not define C67 features, navigation destinations, copy or backend operations. Use the [product context](product-context.md) and the relevant feature task for those decisions. In particular, a delete confirmation example does not authorize implementing trip deletion.

Only clearly readable numeric values are recorded below. Small palette labels and the partially covered board are not fully transcribed. Do not estimate additional HEX colors, intermediate shades or missing dimensions from screenshot pixels. Record a missing source value as unresolved before making it a shared token.

## Color reference

| Brand color | Source HEX | Intended role |
| --- | --- | --- |
| Royal Blue | `#1A4EEA` | Branded actions and emphasis in the Light examples |
| Mint | `#19EBA0` | Brand accent and emphasis in the Dark examples |
| Navy | `#041859` | Deep brand background in the Dark examples |

These are palette values, not universally approved foreground/background pairs. Define semantic roles with Light/Dark variants instead of placing raw HEX values in individual feature views. Check text and control contrast before using a brand color in a particular pairing; never infer sufficient contrast from a swatch.

| Semantic role | Guidance |
| --- | --- |
| Canvas | Adapt the screen background to appearance; the reference contrasts a pale Light canvas with a deep Navy Dark canvas |
| Surface | Separate grouped cards and lists from the canvas using adaptive surfaces |
| Primary label | Keep primary content legible in both appearances |
| Secondary label | Express hierarchy without making supporting text unreadable |
| Tint / action | Apply the appropriate appearance-specific action color consistently |
| Success, warning, danger, information | Keep status meaning consistent and pair color with labels, symbols or state text |

The boards also show neutral/grey, aqua/supporting and stone/surface palettes. Their complete HEX scales remain unresolved. Use appropriate system semantic roles where exact custom values are absent; document any proposed custom mapping rather than silently inventing a palette.

## Typography

Use **Gabarito** for branded content and UI labels, with text styles that respond to Dynamic Type. Use the system font where native iOS chrome expects it, and **SF Symbols** for icons. Do not replace symbol glyphs with Gabarito characters or emoji.

The following sizes and line heights are reference values at the standard content setting. They are not fixed text frames or maximum accessibility sizes. Allow wrapping and scale text with the user's preferred content size.

| Text role | Weight | Size (pt) | Reference line height (pt) |
| --- | --- | --- | --- |
| Large Title | Regular | 34 | 41 |
| Title 1 | Regular | 28 | 34 |
| Title 2 | Regular | 22 | 28 |
| Title 3 | Regular | 20 | 25 |
| Headline | Semibold | 17 | 22 |
| Body | Regular | 17 | 22 |
| Callout | Regular | 16 | 21 |
| Subheadline | Regular | 15 | 20 |
| Footnote | Regular | 13 | 18 |
| Caption 1 | Regular | 12 | 16 |
| Caption 2 | Regular | 11 | 13 |

Tracking is automatic in the source table. Do not impose global custom tracking or force every label onto one line.

| Action role | Weight | Size (pt) | Reference line height (pt) |
| --- | --- | --- | --- |
| Prominent action | Semibold | 17 | 22 |
| Standard action | Regular | 17 | 22 |
| Compact action | Semibold | 15 | 20 |

Gabarito files and font registration are not present in the starter. Before implementation, obtain the font from an approved source, retain its license, verify its registered name and required weights, and verify Dynamic Type behavior. Do not claim that selecting a font name in documentation installs or renders that font.

## Layout and materials

| Token family | Reference values |
| --- | --- |
| Spacing | 4, 8, 12, 16, 24, 32 pt |
| Corner radius | 8, 16, 24 pt |
| Touch region | At least 44 × 44 pt in the supplied reference |

Use the spacing scale as a shared rhythm, not a fixed screen geometry. Adapt to safe areas, device size, text size and content. A touch region can exceed its visible icon or label; keep adjacent targets usable. Avoid fixed-height text containers that truncate accessibility text.

Prefer native bars, controls and system materials. The source asks materials to adapt to content behind them; do not simulate them with one hardcoded blur or glass color. Keep branded content surfaces distinct from platform chrome, and preserve usable fallbacks on supported OS versions.

## Components and interaction states

| Area | Rules from the reference |
| --- | --- |
| Buttons | Distinguish primary, secondary, disabled and destructive actions; choose one prominent action per context; show pressed and loading states without relying on color alone |
| Menus and confirmations | Keep actions near their content; identify destructive actions clearly; explain irreversible consequences before confirmation |
| Text fields | Use persistent labels, visible focus, suitable keyboard/content behavior, clear controls and understandable validation |
| Selection | Use toggles for immediate settings and segmented controls for short, mutually exclusive choices or peer views |
| Value adjustment | Show the current slider value and provide precise adjustment where needed; prefer native steppers and pickers |
| Date and time | Use locale-aware controls; do not introduce a display convention that changes the server's date/time meaning |
| Lists | Use scannable rows and grouped surfaces; disclosure indicators communicate navigation |
| Cards | Pair meaningful imagery and context with a clear action; keep the action reachable as text grows |
| Contextual controls | Anchor menus and popovers to relevant content and adapt presentation to device and task |

Prefer native SwiftUI controls and their accessibility behavior before building custom equivalents. Add shared wrappers only for a concrete repeated need. Keep business rules and networking in the existing VIPER/domain/data boundaries; a visual component does not own those concerns.

## Navigation and feedback

- Keep tab destinations stable and top-level; use short labels. The screenshot's five tab names are examples, not the approved C67 tab structure.
- Preserve navigation hierarchy and put frequent actions in the appropriate toolbar.
- Search should expose query, focus, results, empty and failure states with familiar native behavior.
- Reserve page dots for a short sequence with a clear swipe affordance.
- Use alerts for consequential interruptions, inline status for routine updates, and sheets for contextual tasks or choices.
- Use determinate progress only when progress can be measured; otherwise communicate activity without invented percentages.
- Explain empty and error states in plain language and offer the next useful action, such as retry where appropriate.
- Prevent duplicate submission when an action is in progress while keeping the current state understandable.

## Accessibility, localization and media

- Check Light and Dark appearances, larger accessibility text and increased contrast. Preserve meaning beyond hue.
- Give interactive controls appropriate accessible names, values and actions. Support VoiceOver and alternate input; pair meaningful icons with clear labels.
- Scale SF Symbols with the surrounding text weight and size. Do not turn the example travel symbols into a required icon set for every feature.
- Support Reduce Motion with a calmer transition or immediate state change as appropriate.
- Allow longer translations to wrap and review right-to-left layout, including directional navigation.
- Use meaningful images, appropriate cropping, text alternatives and an identity fallback such as initials. Decorative imagery should not create redundant accessibility announcements.
- Preserve native control semantics rather than recreating buttons or toggles from gestures alone.

## Implementation boundary and agent workflow

The implementation home is [ios-ui/Shared/DesignSystem](../ios-ui/Shared/DesignSystem/README.md). It currently contains documentation and a placeholder, not Swift tokens, font assets or shared controls. Existing Discovery code uses native SwiftUI text styles and colors; it has not been restyled by this guide.

For an authorized UI implementation task:

1. Read [UI agent instructions](../ios-ui/AGENTS.md), this guide, the feature task and the existing implementation.
2. Identify the required visual roles and any missing source decisions. Reuse native controls and existing shared components before adding abstractions.
3. Introduce reusable visual code in `Shared/DesignSystem` as needed. Keep style definitions centralized; do not copy raw values into every feature.
4. Keep the feature's domain/API meaning and mock/live boundary intact. Use C67 product copy, not the flight-template copy.
5. Verify the affected screen at standard and larger text sizes, Light/Dark appearance, and relevant loading/empty/failure/disabled states. Check contrast, accessible controls, Reduce Motion or RTL when affected.
6. Run the relevant Simulator/build checks from [root instructions](../AGENTS.md) and report exactly what was tested. A screenshot, documented token or passing build alone does not establish accessibility or HIG compliance.

Font files/licensing, exact remaining palette values, final C67 tab structure, reusable component implementations and visual/accessibility verification remain implementation work. Do not silently treat unresolved reference details as implemented requirements.
