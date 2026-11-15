# Physical iPhone — Foundation Lab build 4

Test date: **2026-11-05**, Jakarta/WIB. Completed run timestamp: **06:40:12 WIB**.

**Result: the new recommendation pipeline completed on the physical iPhone using the actual local Foundation Model and live MapKit.** It retrieved ten candidates, assessed six, and marked three as recommendations in **23.04 seconds**. Four of seven model stages passed native validation; three were rejected and replaced by explicitly labeled deterministic output. This is execution evidence with partial usable output, not an all-capabilities quality pass.

## Device and scenario

- Installed app: `giovanchristoffel.c67-foundation-lab`, version **0.2**, build **4**, verified through the device's installed-app inventory.
- Device: Giovan's paired physical iPhone 17. Recorded runtime: **iOS 27.0.1 (24A446)**.
- Model: `SystemLanguageModel.default (on-device)`, available, context **4,096 tokens**. English supported; Indonesian unsupported in the recorded runtime. Internal model version was not exposed by the observed API.
- Launch mode: `--recommendation-smoke`, isolated test storage. It executes a fixed brief through the iPhone app's shared pipeline and prints the saved run JSON. It uses neither the Simulator model nor the Mac executable.
- Brief: Jakarta, service date 2026-11-05, no chosen places, coffee and reading interests, relaxed pace, other preferences unspecified/flexible. English free text was empty, so the preference-extraction stage was deliberately skipped.
- Search: live `coffee shop, Jakarta` and `bookstore, Jakarta`, no search errors. All retrieved evidence was non-synthetic MapKit identity/category data. No route or weather calculation was requested.

Package/model source hashes matched the source frozen for the preceding Mac regression series. [The local source manifest](manifest.json) and [installed app metadata](installed-app.json) record the provenance available for this run; this does not claim a remote binary hash or a public model-weight identifier.

## Displayed recommendations

| Place | Retrieved coordinate | Displayed visit suggestion | Basis |
|---|---|---|---|
| Coffeeshop Jakarta International Expo | -6.1478725, 106.8459141 | Morning | General activity suggestion: tentative morning coffee break; opening hours need checking |
| Intermedia Bookstore | -6.245712, 106.934984 | No particular window (`any`) | General reading activity; opening hours need checking |
| Intermedia Book Store | -6.220414, 106.920858 | No particular window (`any`) | General reading activity; supplied venue time facts unavailable |

The two similarly named bookstore results have distinct MapKit identities and coordinates. The returned street-address fields were empty. Their category/name supports a broad bookstore match; it does not establish reading seats, quietness, price, opening hours or suitability of the whole outing.

The morning coffee suggestion is **not a verified best time**, opening-time claim or evidence about morning crowds. It is a tentative activity idea, labeled `generalActivitySuggestion`. The Mac regression series returned `any` for this venue, so its visit-window result is not consistent across the tested devices/runtimes. Those runs also had live-search ordering differences and were not an exact controlled cross-device replay.

## Stage outcomes

| Stage | Duration | Recorded input tokens | Result |
|---|---:|---:|---|
| Coffeeshop Jakarta International Expo | 3.13 s | 951 | Model output passed validation; selected |
| Intermedia Bookstore | 3.27 s | 946 | Model output passed validation; selected |
| Toko Buku Salsa | 3.00 s | 950 | Rejected: generated evidence ID was corrupted; template displayed |
| Intermedia Book Store | 3.00 s | 949 | Model output passed validation; selected |
| Toko Buku Al-Ikhlas | 2.92 s | 958 | Model output passed validation; not among the first three positive assessments |
| Pasar Pulo Jahe | 3.20 s | 953 | Rejected: positive `possible` fit without a supported coffee/reading match; template displayed |
| Explanation | 3.31 s | 763 | Rejected: generated evidence ID was corrupted; deterministic summary displayed |

There were **no recorded timeouts or context-length errors**. The stage durations sum to about 21.82 seconds; the 23.04-second total also includes search and native pipeline work. The maximum recorded stage input was 958 tokens. Each model task retained the existing 800-token output cap, fresh session, 20-second deadline and no automatic retry.

The Toko Buku Salsa output changed `mk-I6E1D6D1467D78A1` to `mk-I6E1D6D67D78A1`. The explanation changed the cafe evidence ID by adding a trailing `6`. Both failed reference validation. For Pasar Pulo Jahe, the model's own reason acknowledged the missing coffee/reading evidence but still returned `possible`; the native relevance gate rejected it. These are actual model failures, not repaired outputs counted as successful inference.

The run saved all seven raw responses separately from the displayed output. Native checks confirmed that selected IDs refer to supplied candidates with accepted model assessments, accepted advice references belong to those candidates, and `routingPerformed` is false.

## What this establishes

- **Established on physical iPhone:** actual local model inference, live Jakarta candidate retrieval, bounded place assessment, three recommendations, preservation of rejected raw output, source/reference checks and explicit fallback behavior.
- **Partially demonstrated:** a useful broad activity-time suggestion for coffee. Venue-specific best visiting times remain unproven because no venue time facts were supplied.
- **Failed in this run:** exact reference copying for one place and the explanation; relevance classification for one unrelated candidate. The explanation shown to the user came from a deterministic template.
- **Not tested here:** English free-text preference extraction, own-place/time-fact scenario, repeated-run reliability on iPhone, a full physical-device UI walkthrough, reduction of user input/corrections, accessibility, or a real journey. Mac and Simulator evidence remains separate.

The model is technically usable on this iPhone as an assistant behind native validation. This run does not support accepting every recommendation or explanation without user review. Valid references and category matches also do not prove every free-form sentence.

## Evidence and cleanup

- [Complete saved run](run.json): input, runtime, retrieved candidates, selected IDs, every raw/displayed output, errors and durations.
- [Raw device console](console.log).
- [Installed app metadata](installed-app.json).
- [Source and run hashes](manifest.json).
- [Post-test normal launch attempt](normal-launch.log): the phone had locked again by this point. This later lock did not interrupt or invalidate the completed smoke run.

The host console was closed after the complete JSON marker had been captured. No app source or routing source was changed during this continuation. No hosted AI endpoint was used by this run.
