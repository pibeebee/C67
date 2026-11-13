# Priority 3 handoff — 5 November 2026

**State: source implementation prepared; all build/runtime/test verification deferred by user instruction.** This is not a passing PoC result. The next execution gate is Giovan confirming WeatherKit activation for the new App ID.

## Prepared

- Separate SwiftUI application, XcodeGen configuration and WeatherKit entitlement: `C67TripIntegration`, v0.1 build1, iOS26+, team `DP5XP7C2AM`, Bundle ID **`giovanchristoffel.c67-trip-integration`**.
- Local Swift package linking the existing preference/embeddings and visiting-time packages. Ten isolated routing source copies with original hashes and documented adapter changes. Old routing and Foundation Lab sources/storage are preserved.
- Optional structured profile, required-place set, general cold start, source gates, unique-venue suggestions, MapKit branch review, WeatherKit-first hourly/solar/attribution, explicit Open-Meteo fallback, sourced visit-start adapter, actual departure-time hybrid route validation, final audit and deterministic explanation.
- Pre-trip +30-minute revision retaining all chosen places; proposal/accept/reject; atomic separate storage with backup/recovery; dated source evidence, compatible raw route report, provider log and exports.
- 33 package test functions, 2 UI test functions and10 live scenarios, written with expected results and separate real-versus-authored evidence labels. These counts describe source, not execution or passing cases.
- Official Baca Di Tebet and Erasmus Huis pages read to bridge published hours into the shared venue IDs. Imported P1/P2 source timestamps remain intact. These reads do not prove current admission, capacity, holiday exceptions or provider connectivity.

## Deliberately not executed

| Activity | State |
| --- | --- |
| Xcode/Swift compilation or dependency resolution | NOT RUN |
| Unit/integration tests, including offline replay | NOT RUN |
| Simulator build, launch or UI walkthrough | NOT RUN |
| Physical iPhone installation/launch | NOT RUN |
| Live MapKit search/ETA from this app | NOT RUN |
| WeatherKit diagnosis / Open-Meteo fallback request from this app | NOT RUN |
| E5 inference/performance in this app | NOT RUN |
| Real +30m comparison, restore/export exercise | NOT RUN |
| User observation / relevance or effort reduction | NOT RUN |

Project generation and reading source/configuration are preparation, not compilation or functional validation. Any compiler/API/concurrency issue found after the gate opens must be fixed and recorded; this handoff makes no claim that the new binary compiles or runs yet.

## Next action after Giovan confirms

1. Record confirmation and exact App ID/team. Resolve/build the new project; handle signing errors for this App ID without changing established app identities.
2. Run package tests and clearly labeled Simulator UI replay; fix failures and retain complete logs/xcresult. Follow the matrix, not merely the happy path.
3. Install the signed app on the physical iPhone. Run **WeatherKit diagnosis with fallback off** and preserve its real provider outcome/attribution. Ask to unlock only if the actual device is locked.
4. Execute the live preference → MapKit → time → routing → weather → explanation cases, including +30m, short deadline and cancellation. Compare E5 on/off and cold/warm requests. Recheck expired catalog facts as a new dated version.
5. Update this report and CBL with passed/failed/blocked/not-tested evidence. Technical integration acceptance and user-benefit conclusions are separate decisions.

## Material boundaries

The first integrated version uses a bounded sourced venue catalog; MapKit confirms locations rather than supplying missing hours or personal-fit facts. Preferred visit windows are advisory; adaptive routing retains its elapsed-time objective and bounded weather alternative. There is no global optimizer for every soft preference. This revision flow recomputes a pre-trip draft; active-trip state, actual delays and tracking remain a later PoC.

Weather cache freshness is retrieval age<15m plus provider expiration; the P1 advisory validator additionally rejects provider metadata older than15m. If that stricter gate removes advice, show context unavailable rather than relabeling metadata as new. Group weather is a representative within3km, not exact weather at each venue. WeatherKit denial remains visible even if explicit fallback succeeds. Provider cancellation/timeouts are cooperative.

The earlier recommendation-method research is preserved at `docs/research/low-compute-recommendation-approaches-2026-11-05.md` in the workspace. Its proposed model replacements have not been adopted or validated here.
