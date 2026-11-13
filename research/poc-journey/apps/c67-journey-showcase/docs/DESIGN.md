# Journey Showcase visual and interaction rules

The primary task is to create and review a one-day Blok M itinerary. The app uses a guided stack with a persistent primary action and visible Demo/Live provenance. The [C67 design reference](../../../../../docs/product/design-system.md) supplies brand and native interaction guidance.

## Hierarchy and tokens

- Gabarito Regular with native Dynamic Type scaling for branded headings, buttons and place labels. Native controls retain system text styles. The bundled variable font provides weight variants.
- Royal Blue `#1A4EEA` marks actions and selected transport/interests. System semantic canvas, surfaces and labels adapt to Light/Dark.
- Spacing follows 4/8/12/16/20/24/32 pt. The 20 pt page/card inset is an intentional POC composition value. Cards use 16/20/24 pt radii according to their role.
- Cards group place decisions, itinerary summaries and visit details. Transport uses a lighter strip between visit blocks. Text wraps and content scrolls above the footer.
- The full visible button surface receives taps. Controls have at least 44 pt touch regions. Selection also has a checkmark or text indication.

## Maps and journey detail

The home map frames Blok M and Bundaran HI. Result maps fit selected destinations and published GTFS bus segments. A selected leg focuses the map, with an action to return to the whole journey. Detail sheets explain walking, headway buffer, boarding/alighting platforms and intermediate stops. Dashed walking connections are explicitly indicative. Geometry must match the routing ZIP hash and stop occurrence order.

## States and accessibility

Loading blocks conflicting actions and offers cancellation. Empty recommendations explain how to change criteria. Conflicts retain selected destinations and offer input correction. Saving requires a feasible, current proposal. Saved data stays visible through a rejected revision.

Dynamic Type, Light/Dark and VoiceOver labels are maintained. The map complements an accessible text timeline. Automated UI tests cover text enlargement and dark rendering. Manual VoiceOver observations are recorded separately from source inspection.
