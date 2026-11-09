# C67 Context Lab in Simulator

This isolated SwiftUI lab adds runtime Google place discovery, opening-session context, explicit independent Apple-place confirmation, user-declared dwell/exposure/time preferences, WeatherKit, and ETA-validated context planning. It uses bundle `giovanchristoffel.c67-context-lab`; the previous integrated app is separate.

Provider credentials stay in the Mac's ignored `.env.local`. `RunConfig.json` contains only the authenticated local-service connection and is ignored; the generated app bundle is a private debug artifact. Do not distribute this build or copy credentials into sources.

## Start and build

From the parent lab directory:

```bash
swift build -j 4 --product planner-server
python3 scripts/dynamic-context-server.py start
xcodegen generate --spec ContextHarness/project.yml
```

Open `ContextHarness/C67ContextLab.xcodeproj`, choose scheme `C67ContextLab`, and run on the active iOS Simulator. The local service listens only on `127.0.0.1:8778`. It is for the Simulator on this Mac, not an iPhone over Wi-Fi. Rebuilding the connection resource is required after restarting the service because its local bearer token rotates. Never start a second copy over an existing recorded process.

To stop the local service:

```bash
python3 scripts/dynamic-context-server.py stop
```

## Personal recommendations (default screen, v0.5)

Choose structured interests and pace once; edit them via the profile icon in **Jelajah**. On-device E5 uses English query/passage inputs (`en-v1`); venue searches and UI labels are unchanged. The zero-price OpenRouter LLM still must succeed before a recommendation page is shown.

1. In **Jelajah**, review the area, date and hours, and tap **Temukan tempat**. **Cari lainnya** appends a page without repeating previously displayed IDs or clearing your chosen destinations. Up to six places appear per round; you can choose up to six total destinations for one route. **Mulai pencarian baru** is an explicit reset in the trip settings.
2. Open a place and select **Wajib dikunjungi** or **Jika sempat**. Confirm the matching Apple venue before the place is saved for routing. Matching remains conservative, so some legitimate aliases may need a different Apple query.
3. Tap **Tinjau pilihan** or open **Rencana**. Search and confirm your starting location. Rain-aware scheduling is on by default for activities identified as outdoor, such as visiting a park or garden. Unclear exposure and unavailable forecasts remain unknown. Use **Sesuaikan durasi dan batas** only when the defaults are unsuitable.
4. Tap **Susun rencana**. Review the numbered visits, the Apple Maps road geometry, and the reasons or omitted stops. Tap **Jelajahi peta rute** for the in-app map. Choose a numbered badge or a row in **Urutan ruas** to highlight that leg. **Seluruh rute** returns to the overview. The drawing loads separately after the schedule. If Apple can't return a leg's geometry, the map reports it and keeps the available pins and lines.

The plan can also highlight a visit that overlaps a sourced pre-sunset window at Pantai Indah Ancol. Select **Ancol Jakarta** and the outdoor interest to try the pilot. When the forecast and schedule support it, **Momen perjalanan** appears automatically. See the [moment pilot verification](../docs/PERSONAL_SUNSET_MOMENT_2026-11-09.md) and [v0.3 flow verification](../docs/PERSONAL_SIMPLIFIED_RESULTS_2026-11-09.md). The previous personal screen, including synthetic controls, remains available via `--personal-full-layout`.

Provider key/model settings belong in the Mac's `.env.local`: `OPENROUTER_API_KEY`, `OPENROUTER_MODEL` (Crouton Alpha by default), and `OPENROUTER_FALLBACK_MODEL` (Nemotron by default). The fallback shares the recommendation time limit. The service enforces zero price; current operational and quality limits are documented in the [protocol](../docs/PERSONAL_RECOMMENDATION_PROTOCOL_2026-11-08.md) and [results](../docs/PERSONAL_RECOMMENDATION_RESULTS_2026-11-08.md). The original CLI key file is preserved. Do not distribute the debug app or local bearer resource.

## Legacy manual context flow

Open **Preferensi → Buka lab pengujian**, or launch with `--context-legacy` to open the manual lab directly.


1. In **Cari & Rencana**, set the travel date first. Enable **Pilih sebagai lokasi awal**, enter a place, search, choose a Google result, then explicitly confirm its independently searched Apple candidate. Review name/address and pin separation; the nearest pin is not silently confirmed.
2. Disable the origin toggle. Search and confirm each destination. No venue needs to be added to Swift source. Jakarta bounds and a maximum of six destinations remain explicit pilot limits. GBK returns potentially different areas; choose the intended activity/location.
3. Set full visit duration, indoor/outdoor/unknown exposure, rain avoidance and the optional 15–16WIB start preference. Read displayed opening sessions and their source. A provider's 24-hour schedule is retained as evidence, not a field-verified access guarantee.
4. Select departure/deadline, total waiting cap, grid and method, then **Buat itinerary**. Time preferences are soft; the app displays unmet time preference and bounded-search warnings. Missing weather/exposure is retained as unknown. Waiting/transfer weather exposure is not fully modeled.
5. **Eksperimen** runs 18 controlled cases three times each. They use synthetic inputs with the production lab planner and actual Simulator HTTP path. **Benchmark live** alternates grids15/5, up to three repetitions each, using the current selections and real providers. Outputs are checkpointed in the app's `Documents/ContextBenchmark` after each result, including across relaunches.

Prepared identities and place context expire after15minutes. Search/prepare again after expiry. The client exports sanitized summaries, not a review corpus. Google details are requested without reviews in this dynamic path; public sentiment remains incomplete. The legacy manual planner has no LLM judge; the default personal recommendation stage uses the mandatory LLM described above.

## Evidence and reproduction

The dated results document describes measured inputs, date amendments, UI checks, independent oracle, live diagnostic controls, and limits. `scripts/dynamic-context-selection.py` supports an operator-reviewed runtime benchmark setup: it calls the same search/prepare routes and writes expiring selections privately. It does not provide an engine catalogue or automatic identity matching. Operator choices and their provenance are recorded separately from human preference validation.

Run controlled tests through Xcode's Test action, then export `controlled-observations.json` from the app container. Audit with:

```bash
python3 scripts/audit-dynamic-context.py artifacts/dynamic-context-simulator-2026-11-07
python3 scripts/report-dynamic-context.py artifacts/dynamic-context-simulator-2026-11-07
```

Live UI tests consume `selection-three.json`/`selection-five.json` from the app's Documents directory and delete those transient files after loading. They must be prepared fresh, reviewed and copied before the relevant tests; ordinary interactive use needs no selection file. Live tests incur provider calls; do not run them repeatedly without checking the service counters and freshness.
