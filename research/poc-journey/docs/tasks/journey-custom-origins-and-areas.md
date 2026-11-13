# Custom origins, target areas and required spots

Status: Complete.
Owner: Hendra / Codex

## Outcome and scope

Expand the standalone C67 Journey POC beyond Bundaran HI–Blok M. Let users select an origin, one or more destination areas and sourced spots they explicitly want to visit. Preserve the existing one-day, return-to-origin, 1–6 destination and transport constraints.

## Implementation

- New trips start with the combined Jakarta catalog: 26 sourced candidate areas across Blok M, Cikini, Tebet, Senayan/SCBD, Kemang, Kebon Jeruk, Ragunan and Kuningan. Candidate records include distinct spaces at the same venue; they do not imply 26 independently schedulable venues. The historical default package catalog remains separate.
- Live origin search supports MapKit addresses and points of interest. Selecting a result locks its coordinate into the request. Editing the query clears the selection. Only results inside the existing Jakarta operational boundary can be selected. An unconfirmed freeform origin can still be resolved in the location review step.
- Demo offers seven explicitly synthetic origin fixtures. Unknown Demo searches return no result instead of an unrelated GBK coordinate. Authored venue locations and routing/weather remain labeled synthetic.
- Multiple target areas constrain recommendation eligibility. No selection means all catalog areas. Out-of-area required spots remain visible with a conflict and cannot be silently replaced or omitted.
- Users search the sourced catalog by name/address and mark up to six required spots before recommendation. Hard preference facts and opening hours still apply. Arbitrary MapKit venues are not assigned invented opening hours or preference attributes.
- Selected origins, areas and required spots are part of the revisioned request, draft, accepted plan and export. Planning and stored-plan audit check request consistency and target-area membership. Blok M branch boundaries remain enforced within the combined catalog.
- Each guided step resets its scroll position, and origin search supports keyboard submission/dismissal.
- Origin searches use cancellation and request identity checks to prevent old results after edits, navigation or mode changes.

## Verification plan

Run shared package checks and Showcase unit/UI checks. Cover a Tebet origin to Cikini by car, a Senayan origin to a chosen Blok M spot by TJ, multi-area filters, required-spot conflicts, missing facts, out-of-bound origins, freeform address confirmation, backward-compatible decoding and persisted drafts. Use fresh ignored evidence under `.verification/journey-custom-locations-20261106/`.

## Limits

Area coverage follows the finite sourced catalog, not all places in Jakarta. Some areas have candidates but no eligible sourced visiting hours; an empty result remains explicit. Existing TJ limits remain: at most one transfer, bounded walking and a dated GTFS snapshot. Live origin search does not establish live routing, WeatherKit success or field-route acceptance.

## Verified engine and provider evidence

All five package suites passed: TripIntelligence 57, PreferenceLearning 29, VisitTiming 59, PreferenceQuality 40 and TripIntegration 80 test functions (265 total). The integration suite includes eight new origin/area tests and existing parameterized TJ boundary/comparison inputs; parameter inputs are not counted as separate test functions.

The new deterministic scenarios produced an audited car itinerary from Tebet to the required Cikini library and an audited TJ itinerary from Senayan to the required Titik Temu M Bloc spot. Multi-area filters, out-of-area required conflicts, unavailable hours, invalid coordinates, explicit address confirmation and old JSON decoding passed.

A bounded live Mac MapKit probe returned one result each for Stasiun Cikini, Senayan and Jalan Wijaya II. These provider responses establish address/POI search on the Mac only. They do not establish iPhone routing or WeatherKit acceptance. Raw responses are retained in the ignored evidence directory.

## Final app verification

All 26 Showcase unit/UI tests passed on iPhone 17e Simulator, iOS 26.4.1, with zero failures and skips. This includes the complete custom Senayan origin → Cikini area → required Cikini spot → car itinerary → save flow, custom-origin TJ generation and draft restore, edit invalidation, and a provider response arriving after cancellation. Demo UI tests use explicit synthetic timing/weather/road geometry.

The first two bundles retain the initial keyboard/scrolling failures. The final correction gives each guided phase a fresh scroll position, dismisses the origin keyboard on submission, and makes test scrolling handle offscreen/lazily created elements. `ShowcaseAcceptance.xcresult` is the passing final bundle. Scoped SwiftFormat, portability/link scanning and whitespace checks passed.

The final signed build was installed on the connected iPhone. Automatic launch of that final build was blocked by the locked screen; an intermediate build had launched earlier. Final physical-device interaction and live itinerary/WeatherKit acceptance are not claimed. The application can be opened directly after unlocking the device.
