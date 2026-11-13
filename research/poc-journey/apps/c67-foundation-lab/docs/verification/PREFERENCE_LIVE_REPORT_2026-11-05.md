# Preference Lab — live MapKit integration

Date: **5 November 2026**, Asia/Jakarta. App **v0.4, build 6**.

**Delivered:** tab **02 · Preferensi** now runs the requested workflow from a local preference profile through **fresh MapKit search**, native validation/filtering and **E5 embedding ranking**, then accepts feedback for a new search. It no longer depends on a fixed catalog for live recommendations. The original Foundation experiment and the v0.3 synthetic/snapshot modes remain available.

The integration completed on Mac, Simulator and a physical iPhone. This demonstrates execution of the workflow, not reliable fulfillment of every combined preference or reduced user effort.

## Workflow and boundaries

1. The default mode is **MapKit langsung · Jakarta**. Explicit interests, an optional short direction or previously liked places provide signals. The live profile is stored separately from the synthetic/snapshot profiles and experiment 01.
2. A bounded query planner chooses up to three activity searches. Explicit interests have priority; known tags of liked places and recognized Indonesian/English activity words can add activities. If the text supplies no recognized activity, E5 matches it to activity prototypes. Each query's basis and any semantic score are retained. General discovery is labeled when no activity signal is available.
3. `MKLocalSearch` retrieves point-of-interest results with a Jakarta region hint. Only bounded activity queries are sent; the complete user profile and raw free text are not sent to a hosted AI API. The app does not request the user's physical location.
4. Responses are interleaved by query, checked against the existing frozen Jakarta operational mask, deduplicated by identity and near-identical name/location, and required to have a broad known category/name match to a searched activity. At most twenty candidates reach ranking. This coarse relevance gate does not prove venue amenities.
5. The category baseline and E5 rank the same eligible set. Native code excludes liked/disliked identities and known avoided tags. E5 supplies numerical similarity, not venue IDs, facts, explanations, visit times or routes. The existing 384-dimensional int8 model and runtime are unchanged.
6. Up to three semantic suggestions are shown with a category comparison, source timestamp, coordinates/address when supplied, and unknown attributes. Likes/dislikes can be submitted from the results. A new action searches MapKit again; it is not just a re-sort of the previous snapshot.
7. Source-bearing feedback places remain in the profile even when absent from later provider results. Repeated likes do not inflate weight. Removing feedback removes its remembered place. There are at most six likes and one hundred feedback identities in this PoC. Reset affects the selected profile; history remains available.
8. Each query has a twenty-second deadline and no automatic retry. Cancellation propagates to MapKit; input revisions prevent stale output from replacing current results. Partial errors are visible. Total failure and a successful-but-empty search have separate statuses. Neither silently uses the bundled snapshot as fresh data. E5 unavailability leaves an explicit category fallback over the retrieved candidates.

The live path uses shared boundary/deadline utilities from the existing `TripIntelligence` package through a local package dependency. Its source and resources were not changed. There is no routing execution, itinerary mutation, weather integration or change to the previously agreed routing method.

## Verification results

| Check | Observed result |
|---|---|
| Preference package tests | **29/29 passed**: previous fifteen tests plus fourteen live-query, feedback, compatibility, filtering, partial failure, empty response, timeout and cancellation tests. [Log](preference-live-2026-11-05/preference-tests.log) |
| Existing Foundation package tests | **57/57 passed**. [Log](preference-live-2026-11-05/legacy-tests.log) |
| Simulator UI tests | **2/2 passed** on iPhone 18 Pro, iOS 27.2. They cover search → like → new search with exclusion → relaunch/history → export, plus cancellation and the old Foundation tab. The provider is an explicitly labeled snapshot replay with real E5 inference. [Summary](preference-live-2026-11-05/ui-summary.json), [log](preference-live-2026-11-05/ui-tests.log), [screenshots](preference-live-2026-11-05/ui-attachments/manifest.json) |
| Actual live MapKit on Mac | Six integration scenarios completed with no query errors in this series. Four semantic cases, one general discovery case, one category-only baseline. [All runs and manifest](preference-live-2026-11-05/live-series/summary.json) |
| Actual live app on Simulator | Fresh MapKit + E5 completed in **2.00 s**, received 26 provider rows and retained 14 matched Jakarta candidates. [Saved app run](preference-live-2026-11-05/simulator/live-run.json). Its console marker was not captured by this simctl console session; the completed result was retrieved from the app's saved run instead. |
| Signed iOS build/install | **Passed**, version 0.4 / build 6. [Build log](preference-live-2026-11-05/device-build.log), [install log](preference-live-2026-11-05/install.log), [installed version](preference-live-2026-11-05/iphone/installed-app.json) |
| Actual physical iPhone | One scripted live profile → MapKit → E5 run completed in **2.06 s** on iPhone 17, iOS 27.0.1 (24A446), after the user unlocked the phone. Received 26 rows, retained 14 candidates, no query errors, status `semantic_completed`. [Run](preference-live-2026-11-05/iphone/run.json), [console](preference-live-2026-11-05/iphone/console.log) |
| Source preservation | The old Foundation views/models, app entry and `TripIntelligence` source/resources remained byte-for-byte unchanged. Only the preference feature, its package dependency/wiring and version/test configuration changed. [Hash audit](preference-live-2026-11-05/preservation.json) |
| Formatting | `swift-format lint --strict` passed on app, package sources/tests and UI tests |

The initial locked-phone launch is retained separately from the completed unlocked run. A later normal launch attempt was again denied by the lock screen; it does not invalidate the completed run. The iPhone evidence is a pipeline smoke, not a full physical-device interaction walkthrough or a real trip. The full like/refresh/restore/export UI sequence was observed on Simulator, and actual provider feedback-driven searching was exercised in the Mac series.

## Live integration series

Source and binary hashes were frozen before the [series](preference-live-2026-11-05/live-series/manifest.json). Each case ran once with changing live provider results. These are integration scenarios, not independent quality samples or a controlled latency comparison.

| Scenario | Result | Received → retained | Total time |
|---|---|---:|---:|
| Indonesian coffee/reading/quiet direction | Recognized coffee/bookstore searches, semantic ranking | 26 → 14 | 1.63 s |
| One liked place; clear text and explicit interests; search again | New bookstore/shopping queries from remembered tags; liked identity excluded from both rankings | 27 → 20 | 1.83 s |
| Empty profile | General coffee/museum/park discovery, no claimed personalized semantic result | 51 → 19 | 2.20 s |
| Free text without recognized activity words | E5 chose culture/entertainment/art search intents, followed by live retrieval and ranking | 28 → 19 | 2.48 s |
| Explicit reading, avoid coffee | Bookstore search and native avoidance over known tags | 25 → 13 | 1.68 s |
| Category-only coffee/reading baseline | Fresh MapKit, no embedding generation in the bounded query planner/ranking for this input | 26 → 14 | 0.96 s |

Received counts are provider rows across queries, including duplicates/outside-boundary or unrelated categories. Retained counts are fresh unique Jakarta candidates after the coarse activity gate and cap, before excluding previously liked/disliked/avoided candidates from ranking. Search timing includes query planning. Performance figures depend on network/provider/cache/device conditions and are not service guarantees.

The physical-iPhone profile explicitly requested coffee and reading. Its first three semantic suggestions were **Toko Buku Ojan**, **Toko Buku Bintang Cipinang** and **Toko Buku**, with supplied addresses and coordinates. The result demonstrates ranking of actual provider identities; it does not establish that these bookstores serve coffee or provide seating to read.

## Important limits retained

- **Combined preferences are soft.** Coffee and reading may retrieve cafes and bookstores, while the first three semantic results can all be bookstores. A broad category match does not guarantee every requested activity at one venue. No stronger fulfillment claim is made.
- **The available real data remains thin.** Identity, category, address and coordinate are useful retrieval inputs. They do not establish quietness, reading seats, opening hours, crowds, pricing, accessibility or best visiting times. The model does not add those facts.
- **Text negation remains unreliable.** Potentially negated text is not used for query generation, and the UI requests explicit avoids. E5 ranking still does not logically enforce arbitrary negation. Unknown avoided attributes remain unverified rather than assumed absent.
- **Likes provide provisional evidence.** A bookstore like may also add its broad shopping tag, causing shopping searches. A like does not prove the user endorses every attribute, and users can correct the profile or apply avoids.
- **Query intent is bounded, not exhaustive.** The native vocabulary covers nine broad activity types and caps searches at three. Semantic prototype matching does not prove correct intent for every phrase, nor retrieval of the best places in Jakarta. There is no learned city-wide ranking or collaborative filtering.
- **The category gate trades recall for simpler relevance.** Places with unknown or unrecognized categories/names can be removed even when they might suit the user. The count of unmatched activities is recorded. Similarity is not calibrated personal-fit probability.
- **No measured user benefit.** Six live Mac cases, two replay-provider UI tests and one actual iPhone run do not show fewer corrections, lower decision burden, battery/RAM suitability or reliability across devices and network conditions. The earlier v0.3 and Foundation tests remain separate evidence.

An early development query combined `bookstore library` and retrieved too few useful results. The final query uses `bookstore`. This change and all failed/replayed output must not be counted as a blind benchmark improvement; the final live series is a development integration check.

## How to try

Open **02 · Preferensi → MapKit langsung · Jakarta**. Pick interests or provide a short direction, then press **Cari dan rekomendasikan tempat** or the comparison icon. Like or dismiss a result, then **Cari ulang dengan preferensi terbaru**. The result discloses the actual query/provider/date. Inspect sources and export through the history/experiment screen. The synthetic and dated snapshot modes remain selectable.

```sh
bash scripts/run-preference.sh --live --out /tmp/c67-live
bash scripts/run-preference.sh --live --profile /absolute/path/to/profile.json --out /tmp/c67-live-profile
python3 scripts/evaluate-live-preferences.py /absolute/path/to/preference-eval /tmp/c67-live-series
```

`--preference-live-smoke` uses the actual provider/model and isolated test storage in the app. `--preference-live-fixture` injects an explicitly labeled replay for UI checks, without a live request. `--preference-reset` resets the selected test profile only when explicitly passed. Dependencies and model artifacts remain pinned as in v0.3; the existing [model report](PREFERENCE_LAB_REPORT_2026-11-05.md) records their numerical/reference limits. No commit, push or publication was performed for this handoff.
