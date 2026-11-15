# UI audit follow-up — 15 November 2026

Status: Backlog. These are findings and proposed directions, not implemented requirements. The audit covered source and sampled iPhone 18 Pro Max / iOS 27.2 Simulator previews; it did not verify every screen, VoiceOver, physical devices or live providers. Confirm product decisions and reproduce runtime issues before implementation.

| Priority | Finding | Evidence and next step |
| --- | --- | --- |
| Now | Active-trip preview and real navigation differ | `TripProgressContent` shows sample turn instructions and Pause/End in design preview; the live path shows route steps and does not expose those controls. Define real supported behavior and Apple Maps handoff before presenting the preview as functional navigation. See `active-trip-glance-nav-masterplan.md`. |
| Now | Home location failure lacks visible recovery | `PlanningLocation` has errors and denied-permission state, but `TripHomeRootView` passes only locating state to its header. Test denied permission, no fix and manual origin; present appropriate recovery without treating a manual origin as GPS. |
| Now | Active-trip layout with large text | The panel has a bounded height and is scrollable. Check discoverability of instructions and actions with largest Dynamic Type, smaller iPhones, VoiceOver and landscape; no obstruction was established solely from code. |
| Next | Distance and address differ across place lists | Recommendations show device distance, while selected and searched place cards may show addresses. Define context-specific hierarchy while retaining branch identification. |
| Next | Departure weather does not match Hi-Fi | The ordering path currently uses Open-Meteo directly; WeatherKit-first with Open-Meteo fallback, attribution, supported temperature/condition data and refresh after date changes remain separate work. Never invent weather. |
| Next | “Behind the scenes” lacks clear user-facing hierarchy | Consider “Trip details” and group available route estimates, opening-hour status and weather sources; this remains a proposal pending product decision. |
| Next | Selected-place controls are inconsistent | Recommendation rows, search rows and My Places use different Added/remove interactions. Test whether users understand deselection; align actions and accessible labels without removing useful context. |
| Later | Trip-complete screen differs from Hi-Fi | Review hierarchy and imagery; actual visit timestamps must not be presented until the application records them. The displayed trip date is planned, not proof of actual visit. |

Also review processing-screen English copy, fixed 24-hour presentation as an explicit product choice, and Liquid Glass appearance with Reduce Transparency and on iOS 18–25. These are supplementary observations, not additional confirmed defects. Preserve the existing Reduce Motion and accessible selected-state behavior.

Sources checked 15 November 2026: [Apple iOS design](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy), and [Loading](https://developer.apple.com/design/human-interface-guidelines/loading).
