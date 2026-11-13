# Hi-Fi preference bridge, area selection, and Luna advice

12 November 2026. Implemented in the isolated Pocket Engine PoC. No Google APIs or the old 982-place dataset were used. The old 62-label vocabulary is retained; source records remain independent. This is implementation and bounded verification, not production approval.

## Behavior

The entry flow now offers Foodie, Nature, Photo Spot, Culture, Lifestyle, Art, and Entertainment. Themes are UI groups over the existing type/subtype/feature vocabulary, not seven new labels stamped onto venues. Multiple themes can be selected; Next is disabled without selection and opens detailed preferences. Skip preserves existing saved preferences and mandatory conditions. Selecting a new theme set clears incompatible old category refinements; the next screen allows explicit detailed choices. This is a functional PoC flow, not a complete pixel-level rendering of the unfinished Hi-Fi.

| Theme | Initial mapping |
| --- | --- |
| Foodie | Seven food/drink types and their cafe/cuisine subtypes |
| Nature | Parks, botanical gardens, urban forests, public squares, waterfront walks; supported nature feature |
| Photo Spot | Supported architecture, city_view, or public_art feature |
| Culture | Museums, cultural centers, heritage sites, history/science museums; supported heritage feature |
| Lifestyle | Books, reading/working spaces, shopping and collection types |
| Art | Galleries, art museums, creative/workshop spaces, performance venues; supported public_art feature |
| Entertainment | Cinema, music, karaoke, sports and recreation types |

These are explicit initial product mappings, not a recovered historical seven-theme specification. Photo Spot especially requires evidence; a generic park or an Apple search query does not establish photography suitability. Other existing feature labels remain available as detailed conditions.

Selecting Foodie + Japanese cuisine narrows Foodie to Japanese cuisine. A generic restaurant does not pass that refinement. Each representable theme gets a different representative where possible; fewer than three eligible recommendations still produces no recommendation list. Existing saved profiles decode without a themes field.

The region selector supports Jakarta Selatan and Kemayoran. Both the Apple search region and independent-catalog filter use the selected polygon. Selection persists; expansion by 5 km requires confirmation. Kemayoran is an OSM boundary snapshot, not a legal boundary certification; Nominatim classifies the relation as village despite admin_level 6, so fine administrative and border accuracy remain unvalidated. Raw provenance is retained in the research artifacts.

## Planning and Luna

1. Swift searches under one shared ETA budget and retains up to six feasible schedules with the highest visit count found. Its deterministic ordering still prioritizes user visit-time preferences and finish time. Search remains bounded, not a proof of global optimality.
2. The app sends date, interests/refinements/conditions, preferred visit minutes, and candidate visit summaries to the authenticated server. The summaries include names, public venue IDs, times, supported attributes and weather descriptions; the origin coordinate and provider key are not sent.
3. The server calls only luna-provider.example, requesting cx/gpt-6-luna(max), with one call and 500 output tokens. There is no model fallback, redirect or automatic retry.
4. Luna must return exactly one offered slotID. The app maps this ID back to its own immutable schedule. The model cannot author replacement times, coordinates, venues, routes or facts.
5. Swift rechecks mandatory visits, exact/not-before timing, full opening interval, evidence expiry, access, chronology, wait limits, return and deadline. A changed trip configuration cancels stale work. Failures publish no schedule and can be retried by the user. Reduced-count and waiting proposals still require the existing user acceptance.

Luna is enabled by default. The server is therefore required for this path. The user can explicitly switch it off in Settings to use the deterministic Swift planner. Foundation Models remains optional for selecting venue explanation IDs; it is not the schedule adviser. Logs retain stage durations and requested/reported model names without secrets or raw prompts/responses. There is no automatic provider billing reconciliation.

## Independent catalog

The prepared local server seed contains **14,835 source identities**, prior independent OSM/Overture records plus the small previously reviewed pilot. Ten existing pilot facts were imported through Store. Identity count is not a count of unique venues, eligible matches, verified hours, or ready-to-visit places. The 30-day fact policy remains in force. Retaining the 62-label contract does not mean every source identity has all of those labels or that missing attributes have been filled automatically.

Four TUKU branch identities were found and operator aliases/provenance were retained. Proposed coffee facts were not promoted: brand-level products plus a named branch do not verify that branch's current menu. New historical reading/public-access statements were also held from the active catalog. This prevents the enrichment work from claiming a coverage gain unsupported by current branch evidence. Reading, coffee and children coverage remain incomplete. No new held-out 10/12 acceptance pass has been established.

The local private Server/.env now references the existing provider credential file and the prepared independent seed. No new provider key is embedded in Swift. Server/.env.example documents the optional configuration. The prepared seed is a local artifact; it is not silently bundled as verified production data. Start the normal local server from the lab directory with `python3 Server/server.py` when using the app.

## Verification

- Simulator build passed before runtime checks; final build recorded below after all source changes.
- Existing core tests: 12/12. Deterministic replay: 18/18 cases, five repetitions each. Replay is synthetic, not 18 successful real trips. The release replay build emitted a runnable executable but exited nonzero because sandbox rejected dsymutil; this is not a passing release build.
- Independent Swift regressions: 5/5 test methods cover legacy decoding, themes/refinements, unknown/stale/conflicting feature evidence, different theme representatives, area points, an independent ETA-call counter and shared budget, mandatory destinations, tampered pins/names, deadlines, expired facts/hours, date exceptions, and overnight intervals.
- Proxy tests with injected transport: 4/4; wrong model, invalid IDs/JSON, timeout and failure do not trigger fallback.
- HTTP: unauthenticated catalog/advice 401; authenticated catalog returned 14,835 identities; invalid slot request 422. One live synthetic advisory call returned HTTP 200, S1, requested cx/gpt-6-luna(max), reported gpt-6-luna(max), 3,810.5 ms. The reported alias does not establish upstream internals or general recommendation accuracy.
- Simulator UI: 1/1 isolated XCUITest passed after targeting the switch control correctly. Foodie+Culture multi-selection, disabled/enabled Next, Japanese refinement, Skip preservation, relaunch persistence and Kemayoran display/persistence were observed. This is not physical-device validation.

Runtime flow integration and final build are recorded in the continuation below.

## Evidence paths

All artifacts are under `.local/implementation-20261112/`: `testing-agent/REPORT.md` and logs; `ui-agent/REPORT.md`, screenshots and xcresults; `evidence-agent/SOURCES.md` with raw OSM metadata and held proposals; `catalog.json` and independent identity inputs. First runtime attempts failed before planning because the fixture assumed source IDs survived the normal cross-source deduplication pool. The harness was corrected to resolve a unique name/coordinate match, record original and canonical IDs, and require three distinct resulting places. That exposed a production bug: PocketModel.match read raw catalog records even after CandidatePool had merged them. It now reads the independent canonical pool, and merging now retains absorbed names and aliases. The independent regression verifies alias retention, distinct branches beyond 125 m, and refusal of genuinely ambiguous matches. Taman Literasi had two same-name OSM records 35.79 m apart; both resolve to one pool candidate after the fix. The three failed integration runs remain in the report; none reached ETA or Luna. Failed outputs are preserved. This also illustrates why source identity count must not be presented as distinct venue coverage.

## Final runtime outcome

The fourth isolated Simulator launch passed after the production matching fix. Total elapsed time was **35.22 seconds**, including catalog sync, canonicalization, configuration and planning/advice. Luna's reported upstream portion was **5,235 ms**; this is a single measurement, not a latency distribution.

- Loaded 14,835 source identities. Nature filtering produced 417 eligible pool entries in Jakarta Selatan and 0 in Kemayoran from this source extract. This verifies filtering on the same extract, not absence of parks in Kemayoran or complete coverage of either region.
- Three distinct canonical park IDs were used. Taman Literasi's way ID resolved to the existing OSM node representative, 35.79 m apart. No new venue was invented.
- Planner made 16 live Apple ETA requests and returned a bounded result with searchTruncated=true. Luna selected S1; the app revalidated and published that existing schedule. This is not proof of the best possible order.
- Example date: 13 November 2026, departure 09:00 WIB. Taman Literasi 09:27:51–09:57:51; Taman Bendera Pusaka 10:03:17–10:33:17; Tebet Eco Park 10:57:33–11:27:33. The origin was Tebet, also the final stop, so the extra return leg was zero. A distinct home destination was not tested in this live scenario; existing synthetic tests cover nonzero return travel.
- Hours 09:00–17:00 and public access were hypothetical user confirmations for this test, not sourced operational facts. No live WeatherKit quality/coverage claim is established by this run.

Final normal PoC Simulator build passed, no reported warnings/errors, log `build_sim_2026-11-12T03-21-49-597Z_pid86846_02604160.log` under XcodeBuildMCP workspace logs. The isolated integration app was stopped after testing. No physical iPhone, Google API, or old 982-place dataset was used. The server used a separate database and test port; cleanup is recorded in the agent report.

## Remaining release questions

The functional preference/area/Luna bridge is implemented and tested within this scope. Production approval still requires current branch-level evidence sufficient for the held-out recommendation gate, real operational-hours/access checks, broader independent visiting-time quality evaluation, route/traffic and weather validation, source-ID continuity across catalog refreshes, real-device privacy/permissions, server deployment and resource/billing controls. The 62-label UI contract alone does not resolve these data and operational gaps.
