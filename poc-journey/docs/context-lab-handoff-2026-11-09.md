# Context Lab handoff — 9 November 2026

The active experiment is **C67 Context Lab v0.5 (5)** with a local Mac Swift/Vapor service and an iOS Simulator app. Giovan asked to document the discussion, current implementation, gaps and next steps, and publish them within the existing PoC journey.

The current [CBL source record](source-records/CBL.md) contains the full Indonesian synthesis in section 0I. The [5 November record](source-records/CBL-2026-11-05.md) remains a dated source. [BLINDSPOT](source-records/BLINDSPOT.md) retains the original system/test analysis. Source records keep their language and historical claims.

## Current flow and responsibilities

1. The traveller selects structured interests and pace once, then area, day, departure and return deadline.
2. Google Places discovers candidates and supplies opening sessions. On-device E5 uses English category/activity inputs, revision `en-v1`. OpenRouter ranks supplied candidates and cites constrained evidence IDs.
3. **Cari lainnya** continues discovery without repeating IDs or clearing chosen destinations. There are at most six cards per round and six selected destinations per trip.
4. The traveller chooses required/optional visits and confirms each independent Apple identity, including the origin.
5. The server checks opening hours, full dwell, waiting, return deadline and exact-departure Apple ETAs. Outdoor activities use weather automatically where exposure is supported.
6. A sourced pre-sunset opportunity is available for Pantai Indah Ancol. A valid ordinary plan can already contain it. Otherwise, an alternative uses the remaining shared ETA budget and retains the same visits.
7. A plan-level LLM call occurs only when a valid alternative adds travel or waiting. It chooses an offered plan ID and a matching evidence/reason code. An unavailable judge leaves the ordinary plan usable.
8. The app displays visits and a sourced moment card when applicable. The in-app map has coloured numbered legs, selection from badges/list, camera framing and an overview action.

The configured primary model is `stealth/crouton-alpha`, with `nvidia/nemotron-3.5-super-vl:free` as fallback within the same time budget. Provider responses and constraints are validated locally. E5, hosted candidate ranking and verified schedule selection have separate roles.

## Evidence and limits

| Checkpoint | Observed result | Scope |
| --- | --- | --- |
| Personal discovery, 8 November | Three live lists, median 8.523 s to first selectable card | Older personal flow, three explicit interests |
| Personal itinerary, 8 November | One three-visit plan, 41.347 s, 35 ETA calls | Separate route computation timer |
| More candidates, v0.3 | 12 distinct cards across two pages; the first selected venue remained usable | One live Simulator journey |
| Sunset, v0.4 Simulator | 17.00–18.00 WIB, 45 minutes overlapping the opportunity, plan 3.058 s | One actual venue, E5 and live providers; plan judge skipped |
| Sunset, v0.4 backend CLI | 22.12 minutes overlapping the window; +10 minutes waiting and +1 second driving; endpoint 15.45 s | Nemotron fallback selected the alternative; CLI did not run device E5 |
| Interactive map, v0.5 | One live UI test passed selection from the list and map badge, overview, close and foreground checks | One venue, outward and return legs |

These are dated development observations. They use different inputs and timers. Read [the current app guide](../apps/c67-local-server-lab/ContextHarness/README.md), [sunset report](../apps/c67-local-server-lab/docs/PERSONAL_SUNSET_MOMENT_2026-11-09.md), [map report](../apps/c67-local-server-lab/docs/INTERACTIVE_ROUTE_MAP_2026-11-09.md) and the [published evidence inventory](../evidence/context-lab-publication.json).

## What still needs work

- Express activity-level needs with low input effort, including reading in place, quietness, dietary needs, budget and access.
- Improve complex/tenant identity, sourced aliases, entrances and activity scope. The strict beach guard covers two known cases.
- Supply current last-entry, ticket, queue, holiday and venue-specific evidence before making claims about these conditions.
- Broaden the opportunity policy beyond one place and test its thresholds with people. The 45-minute pre-sunset interval, minimum 20-minute overlap, rain/cloud thresholds and 15-minute extra-effort cap are pilot choices.
- Compare grid15, grid5 and arrival/opening/event-derived starts with the same brief, data and ETA allowance.
- Preserve drafts and plans through relaunch/expiry/server restart. Test background/network failure, partial map geometry and larger trips.
- Compare E5, learned facets, moment suggestions and plan judging against controlled baselines on new holdouts, then obtain human and field evaluation.

The native active-trip lifecycle and independent offline-from-team-backend experiments remain in their original apps. Extending this Context Lab into active-trip state or production requires a scoped implementation task.

## Reproduce this source export

From the repository root, restore and verify the pinned model assets, then run the Context Lab package tests.

```sh
python3 poc-journey/scripts/bootstrap.py
python3 poc-journey/scripts/verify_portability.py
bash poc-journey/scripts/verify.sh context
```

For the normal app, follow the [ContextHarness setup](../apps/c67-local-server-lab/ContextHarness/README.md). Create private `.env.local` values from the supplied example using your own Google, OpenRouter and Apple Maps/WeatherKit REST credentials. Starting the local service creates the ignored connection resource required before XcodeGen/build. Native WeatherKit entitlement setup from the historical app does not provision these REST credentials.

Source export verification is recorded separately from original live evidence. Historical raw logs, provider payloads and opaque result bundles are retained at the original location. The public inventory records links that could not be included. Model assets are restored by immutable URLs and checksums.
