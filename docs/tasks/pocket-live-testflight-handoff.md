# Pocket Engine live acceptance and TestFlight handoff

Status: **Internal beta candidate; App Store Connect upload is blocked by signing. Public HTTPS is unverified.**

The test target was **iPhone 18 Pro Max Simulator, iOS 27.2, Xcode 27.2**. No other Simulator or physical device was used for this acceptance. The native app branch starts from `origin/dev` at `26cf144`. No Google API, 982-place dataset, simulated ETA, guessed hours or synthetic Luna response was used for the live run. Local server catalogs were isolated from shared deployments.

## What the live runs showed

The tests sent no initial destination. Discovery used real MapKit search where available plus a local Pocket catalog containing independent OSM/Overture records. The first catalog had 34 identities. We removed obvious Apple-only false park candidates, prioritized opening/access evidence among equally relevant candidates, and added three branch-checked Japanese dining identities and evidence for three public parks. The final bundled catalog contains 36 identities. The corrected runs are diagnostic replays after seeing the failures, not a new held-out benchmark.

| Brief | First → corrected candidates | Examples / limit |
| --- | ---: | --- |
| N01 · Jakarta Selatan · Nature + Park | 12 → 12 | Taman Bendera Pusaka, Tebet Eco Park, and Taman Literasi Martha Tiahahu were the first three with published park hours/access. |
| F01 · Jakarta Selatan · Foodie + Japanese cuisine | 0 → 3 | Sushi Hiro Senopati; Sushiro Gandaria City and Pondok Indah Mall 1. Venue branches verified, hours/access still unconfirmed. |
| C01 · Jakarta Selatan · Culture + Art | 5 → 5 | Ciputra Artpreneur Museum, BAIK ART Jakarta, Museum Betawi. Apple search unavailable for this brief; output came from the independent catalog. Opening/access not established. |
| K01 · Kemayoran · Nature + Park | 11 → 7 | RPTRA Harapan Mulia, RPTRA Krida and RPTRA Serdang Baru. Removed evident false positives such as a parking result and a named home. Remaining Apple-only candidates still need independent review. |

The first itinerary attempt correctly failed because the top three places lacked availability evidence. The corrected run for **13 November 2026, 09:00–18:00 WIB**, driving from Blok M with flexible departure and return to origin, used three recommended parks with 45 minutes at each. It called live Apple ETA, fetched the catalog over authenticated HTTP loopback, asked model `cx/gpt-6-luna(max)` to select from two locally validated options, accepted reported model `gpt-6-luna(max)` and slot S1, revalidated the option, then saved the trip in the isolated repository. Model identification is the provider's reported label.

| Place | Visit in WIB | Leg ETA |
| --- | --- | ---: |
| Taman Bendera Pusaka | 09:02:59–09:47:59 | 179 s |
| Tebet Eco Park | 10:12:25–10:57:25 | 1,466 s |
| Taman Literasi Martha Tiahahu | 11:28:09–12:13:09 | 1,844 s |
| Return to origin | Arrives about 12:13:30 | 21 s |

Run 3 required **125.85 s** end to end, including repeated WeatherKit authentication failures and 5.24 s at the Luna proxy. Run 4 after the WeatherKit cooldown used the same schedule, made **15 successful Apple ETA calls**, and took **6.82 s** for planning, including **3.83 s** at the Luna proxy. Two measured runs do not establish a latency distribution. Weather remained unknown; rain avoidance was not required. No observed drive times or guarantee of hours, special closures or parking access is implied. WeatherKit's HTTP 401 must be corrected for rain-aware beta testing.

Source references: [Tebet Eco Park operator hours](https://tebetecopark.id/informasi), [Jakarta Tourism: Bendera Pusaka](https://enjoy.jakarta.go.id/article/berwisata-ke-taman-bendera-pusaka-ruang-hijau-baru-di-jakarta-selatan), [Jakarta Parks: 24-hour parks](https://flona.jakarta.go.id/taman-24jam), [Sushiro branches](https://sushiro.co.id/en/location/) and [Sushi Hiro branches](https://linktr.ee/sushihiroid). The park checks expire after 14 days; do not extend evidence by merely restarting the catalog. The 10/12 held-out recommendation gate is still open.

## Verification and evidence

- Normal app UI: selected Nature and no required place, then observed the three real parks in Recommendations. Final opt-in UI test passed in **32.69 s**; its timing includes UI interaction. An earlier UI attempt stopped at missing starting location; a subsequent manual search interaction did not reach a result. The passing run uses the Simulator's Blok M starting location and normal app discovery. The screenshot and XCTest result are held locally.
- Live adapter: the initial discovery/itinerary failure is kept above. Corrected XCTest passed; the publication-server replay passed the live adapter case and recorded Luna HTTP 200. A separate final UI run then passed.
- Maintained Swift core **12/12**, adapter **47/47**. Imported standalone Pocket and Preference packages **12/12** and **13/13**, Python pilot **6/6**; Venue Context manifest parsed. Historical UI, provider and performance experiments were not rerun.
- The Pocket Docker image built, then started in a disposable read-only container; health 200, no-token catalog 401 and authorized catalog 200 with 36 identities. The first runtime attempt exposed a missing taxonomy resource; this was fixed before the successful smoke check. Trusted external HTTPS and release-network acceptance are still open.
- Generic iOS Release archive compiled unsigned with app icon. Signed archive remained blocked, including the automatic provisioning attempt.

## Reproduce the live test

Run the [Pocket server](../../server/pocket/README.md) in isolation, set a small Luna request cap, and provide the test runner with `TEST_RUNNER_C67_LIVE_ACCEPTANCE=1`, `TEST_RUNNER_C67_LIVE_URL` and `TEST_RUNNER_C67_LIVE_READ_TOKEN` through the environment. Do not put the token on the command line or in an artifact. From Xcode or `xcodebuild test`, select C67 / iPhone 18 Pro Max and the `C67AppTests/PocketLiveAcceptanceTests` test. Run the opt-in real-recommendations UI test separately; on the test Simulator set the location near Blok M and allow location for this app. It uses bundled real identities and normal MapKit search. Neither live test runs in ordinary CI.

## Before upload

1. Sign in to the appropriate team in Xcode → Settings → Accounts. The local archive attempt with automatic provisioning reported **No Accounts**. Verify the App Store Connect record uses the same bundle ID as the target: `io.pibeebee.c67.starter`.
2. A team Account Holder or Admin must enable WeatherKit in both **App Capabilities** and **App Services** for that App ID and regenerate its profiles. The cached profile did not contain the entitlement. See [Apple's WeatherKit capability steps](https://developer.apple.com/help/account/identifiers/enable-app-capabilities#enable-weatherkit).
3. Deploy the [Pocket server](../../server/pocket/README.md) behind a trusted HTTPS host. Verify reachability and Luna from a different network. Put only the HTTPS host in the ignored `Production.local.xcconfig`; configure the invited beta token in Account → Pocket settings. The default shipped archive does not include an HTTPS endpoint or tester token.
4. Confirm version `0.1.0` and choose a fresh build number in App Store Connect (local default `1`). With the signed Release device archive, run Organizer → Validate App and then distribute with [TestFlight Internal Only or TestFlight & App Store](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/). No upload was performed. Complete the beta notes and privacy disclosures for the configured providers; do not infer upstream retention or public-distribution readiness from this pilot.

The existing Travelant 1024px icon is wired to the target. An unsigned generic iOS Release archive verifies device compilation and asset generation only; it cannot be uploaded. Continue to treat physical-device operation and Apple Weather behavior as separate checks.
