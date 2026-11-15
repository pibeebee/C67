# Task: Build the first Pocket itinerary with fewer inputs

> Superseded on 14 November 2026: the user removed geographic restrictions and catalog dependence, and required request-time web research plus Luna on the native first-itinerary path. See [the runtime implementation](pocket-runtime-visit-resolution.md). Earlier behavior and checks below are historical.

Status: Implemented locally. Fixture scenarios pass. The five-place live scenario failed to produce a multi-stop itinerary.
Owner: Giovan and Codex
Branch: `gi/pocket-ui`

## Outcome

Generate an initial car itinerary directly after selection and the optional main-spot choice. Use catalog evidence, automatic visit timing, an editable starting point and an endpoint that defaults to the origin.

## Scope and dependencies

- Use the existing Swift Pocket planner, native trip creation and itinerary review.
- Evaluate recurring weekday and weekend options. Use date-specific evidence and reject required reservations without a personal confirmation.
- Keep excluded destinations in the creation selection and explain why they are absent from the review. Expose a focused confirmation route when evidence blocks every proposed visit.
- Use the existing catalog and consented provider configuration. Crawler deployment, new Luna capabilities and geographic expansion are separate.

## Acceptance criteria

- [x] A selected main spot reaches review without a duration or availability form when evidence suffices.
- [x] An unsupported place stays selected and appears with its reason in review. An entirely unverified selection cannot produce a plan.
- [x] A saved itinerary contains only the scheduled subset, with valid ETA through the return leg.

## Implemented defaults

- Use the current origin when available. The first proposal uses a car and returns to the origin unless an endpoint is selected.
- Try two upcoming weekdays and both weekend days. A personal confirmation can add its specific date. Search within 09.00–20.00 WIB, with a latest departure of 17.00 and up to 45 minutes of waiting per stop.
- Suggest 75 minutes for the optional main spot and 45 minutes elsewhere, capped by evidenced maximum duration. Prioritize retaining the main spot, then visit count. Compare equally complete daily proposals by elapsed trip time. These defaults are product assumptions to evaluate.
- There is no selection cap. The bounded search considers up to 12 eligible candidates a day, plans up to six stops, and permits up to 20 ETA requests per date. An explicit provider throttle stops the request across all dates.
- The checked bundled catalog preserves the [Tebet Eco Park hours reported by the operator](https://tebetecopark.jakarta.go.id/v144/t101/informasi) and the [directory's conflicting closing time](https://pertamananpemakaman.jakarta.go.id/taman-24jam) as a conflict. The bundled evidence cannot schedule this venue automatically. The deployed catalog is outside this update.

## Verification

- Pocket Engine, 14 passing tests. New checks cover a necessary 15-minute visit delay before the next stop and finding a valid departure near Friday's second session.
- C67Backend, 51 passing tests. New checks cover seven selections, saving six verified stops, evidence-backed visit cap and last entry, a date-specific closure, missing reservation, separate endpoint ETA, provider throttle and the catalog conflict.
- iPhone 18 Pro Max Simulator, iOS 27.2 (24B8117), Xcode 27.2. The targeted final run passed 33 trip-creation presenter tests and 3 Pocket UI tests. UI checks cover a user-picked main spot followed by direct review, an omission reason, time and endpoint editors opening, saving the scheduled subset, and a separate itinerary created after personal confirmation. Venue evidence, recommendations, ETA, weather and starting location in those UI tests are synthetic. The broader preceding run passed 12 additional recommendation and trip-creation UI checks, including accessibility text size.
- Repository-pinned formatting passes for 659 Swift files. Contract, fixture schema and whitespace checks pass.

Fixture commands from the repo root:

```sh
swift test --package-path packages/PocketEngine
swift test --package-path ios-backend
xcodebuild -project ios-ui/C67.xcodeproj -scheme C67 \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max,OS=27.2' \
  -parallel-testing-enabled NO \
  -only-testing:C67AppTests/TripCreationTests \
  -only-testing:C67UITests/PocketEngineUITests \
  -only-testing:C67UITests/RecommendationsUITests \
  -only-testing:C67UITests/TripCreationUITests \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- C67_DATA_MODE=mock test
```

## Live Simulator observation

The opt-in `PocketEngineUITests/testLivePocketPlansFromRealJakartaDiscovery` passed. Automatic position did not resolve on this Simulator. The starting-point picker selected Stasiun MRT Blok M BCA through live MapKit search. Nature discovery returned Jakarta places, and an exact search by name was needed to add Taman Bendera Pusaka. The Simulator already held Kota Tua in the creation selection. The review placed Taman Bendera Pusaka at 09.02–09.47 WIB on Monday, 16 November 2026, with departure at 09.00 and estimated finish at 09.49. The review retained Kota Tua as an exclusion outside supported planning areas. The route used live Apple ETA and existing bundled venue evidence. Repository processing took 4.48 seconds for this request. Full XCTest duration was 46.44 seconds including launching, searching, selecting and rendering. This was one run. The saved-trip interaction was tested with fixtures.

The prior run that expected the park directly in Nature failed because the park was absent from the observed recommendation list. The final opt-in test permits exact search through the app.

## Five-place live validation

Giovan's screenshot on 14 November matches the persisted Simulator proposal for 21 November 2026. The real request completed in 4.51 seconds and scheduled Taman Bendera Pusaka only, from 09.16.55 to 10.01.55 WIB, with a 10.20.28 return estimate. Four of five selected places were omitted. The earlier successful single-stop smoke test still covers producing a route with live ETA. The five-place run exposes the gap in obtaining a usable multi-stop plan from the user's discovery selection.

| Selection | Distance from the discovery center | Why the current code accepted or omitted it |
| --- | ---: | --- |
| Taman Bendera Pusaka | 7.20 km | In Jakarta Selatan and matched to sourced catalog evidence. |
| Tatemukai Signature Omakase Sushi | 5.43 km | In Jakarta Selatan. No catalog identity or alias matched this branch. |
| National Library of Indonesia | 2.52 km | Outside the Jakarta Selatan and Kemayoran routing polygons. The [Perpusnas services page](https://perpusnas.go.id/layanan) lists service hours. |
| Night market | 2.23 km | The selected pin is outside both routing polygons. The generic label leaves the market's operating schedule unverified. |
| Memorial Coffee Cipondoh | 18.19 km | The selected pin is outside both routing polygons. |

A replay of the five public venue pins from the original request used the current Swift repository, bundled catalog and a constant synthetic ETA. It reproduced the four reasons and requested routes only between the replay origin and Taman Bendera Pusaka. This isolates geography and branch evidence checks from ETA and the order search. The review headline reads “All set!” because it checks route feasibility even when the proposal omits most of the selection. Treat this scenario as failed coverage in acceptance reporting.

## Remaining verification

Measure evidence coverage and time to a usable proposal across real Jakarta selections. The first plan uses published catalog evidence, with the bundled catalog available locally. Runtime scraping, Luna extraction or reranking, device acceptance and TestFlight were outside this implementation.
