# Dynamic context simulator protocol

Prepared on 7 November 2026 before running the new campaign. The user requested runtime place discovery in the active Simulator and broader weather/opening-hours experiments with benchmarks.

## Implementation scope

An isolated C67 Context Lab app uses a new bundle ID on the currently booted iPhone18ProMax/iOS27.2 simulator. A Mac-local authenticated service supplies dynamic Google search/details, independently searched Apple candidate pins, WeatherKit, and the corrected context planner. The user explicitly confirms Apple candidates and supplies dwell/exposure/preferences. Place IDs and aliases are input values rather than an application venue catalogue. Ambiguous search results remain selectable and cannot silently become a confirmed location.

Provider keys stay on the Mac. Prepared place contexts expire in memory. Exported benchmark records contain synthetic fixtures, technical measurements and sanitized plan summaries. Real Google review/details responses remain transient. Place context and provider attribution are shown in the app. The integrated product app has a separate bundle ID.

## Prospective test matrix

- Controlled paired experiments use the same corrected engine, client/server path, candidates, travel model and input bounds. Change only the declared variable. Compare dry weather, morning rain, afternoon rain, activity moved indoors, missing/stale weather, unknown exposure, early close, late open, split session, all-day closure, stale hours, required-time conflict, deadline pressure, ETA budget and five-stop15vs5minute grids.
- Each controlled scenario runs three times in Simulator. A separate Python reference independently enumerates admissible orders and slots using its own declared fixture rules and checks complete dwell, wait<=30min, return and penalties. Deliberately corrupted outputs must fail. Unknown and non-ready remain visible.
- Live runtime search includes GBK and venues outside the old catalogue. Search failures and duplicates are retained. A user-selected three-stop and five-stop set use fresh provider context. The benchmark supplies the place IDs/pins selected from actual search results, not a source-coded catalogue. Capture operator confirmation and distinguish it from actual user preference validation.
- Live planning repeats up to three times per case if budgets/freshness permit. It uses actual current forecast. A controlled rain forecast cannot be labeled live. Departure is tomorrow09WIB, return19WIB, full dwell, wait<=30min, automobile. Comparisons15vs5minute grids freeze all other inputs and use fresh exact-departure ETA per plan. Context acquisition timing and route timing are separate.
- Primary route policy is corrected firstFeasible. Controlled beam supplies a bounded context-quality comparator. Selective escalation remains experimental.

## Limits and evidence

Google campaign hard cap60calls, AppleHTTP900, ETAcells720, one active operation. Per-plan ETA cap64 for live, timeout180s client, fixed1.2sec lab start spacing. No automatic auth/quota retry. Controlled ETA calls are synthetic and counted separately. Stop live expansion if usage5Hremaining<=25percent, retain checkpoints and finish reporting. Start snapshot has95percent5Hremaining.

Use monotonic client timing from request submit to complete decode. End-to-end discovery timing includes search/resolve/enrichment when measured. Persist client benchmark summaries after each scenario. Capture UI search, selection and itinerary interactions through UI tests, screenshots and simulator exports. Passing package tests alone cannot establish UI behavior.

Existing benchmark artifacts and66original source/input hashes remain evidence. Retain a before-manifest for changed lab files. Preserve original15minute default for old request decoding. New dynamic planner offers5minute starts explicitly and labels the selected grid. Publication/deployment to shared infrastructure is outside this request.

## Amendment during pre-campaign regression testing

The first controlled weather test failed before simulator measurements. Partial beam ranking used only accumulated penalties, giving unvisited outdoor preferences a zero contribution. In a morning-dry/afternoon-rain fixture the park could remain last despite an available earlier dry visit. Preserve the original failure in `tests.log`. Rank partial states with an optimistic minimum remaining-goal penalty over still-reachable visit options, then the existing tie-breaks. Complete-candidate scoring and hard constraints retain their meaning. Re-run old regressions and compare against the independent reference. This is an implementation correction driven by development fixtures, not a claim from an untouched holdout. Early/late/split controls change museum hours, chosen so dry baseline does not already put the constrained venue first.

## Calendar and live-case amendment before live planning (8 November)

The campaign crossed midnight into Sunday8November. Controlled weekly hours are synthetic for9November. Live contexts are selected for **Tuesday10November2026**, avoiding an unintentional Monday-closure comparison. Three-stop departure is11WIB, matching the earlier accepted user brief; five-stop departure is09WIB. Both return by19WIB, wait<=30minutes; park start15–16 is a soft preference. These different-size cases are not direct algorithm scalability pairs. Within each size, compare15vs5minute grids with identical selections, date, dwell and priorities. Three live trials per grid are descriptive observations, not statistical significance. Runtime Google results included four same/related-name history-museum candidates; operator selected TamanFatahillahNo1, then explicitly reviewed independent Apple pins. No engine catalogue changes were used.
