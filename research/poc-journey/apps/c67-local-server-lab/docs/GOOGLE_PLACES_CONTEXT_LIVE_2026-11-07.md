# Google Places live verification — 7 November 2026

Place ID was supplied and verified by the user: `ChIJi_JxtdT1aS4R7Vhgb1ZBFaQ` (Museum Nasional). One actual Place Details (New) request with the explicit experience field mask succeeded at **09:13:22 WIB**, after the user's successful Text Search. No extra Text Search or automatic retry was used in this run.

## Observations

Current opening hours, regular opening hours, timezone and five reviews were returned. Author attribution was present for all returned reviews. No temporal quiet/busy hint passed the existing conservative extractor. Zero accepted hints means **insufficient accepted evidence**, not that the place is always busy, that the reviews contain no useful information, or that a stronger extractor would necessarily fail.

The engine evaluated 16 local scenarios against this single in-memory snapshot: two future dates (8/9 November), each with hours only, morning preference, afternoon preference, quietness, rain without exposure/forecast, required visit time outside availability, unconfirmed identity and stale snapshot. All initial local checks passed: full dwell within a returned operating session and requested bounds, future start, no options for invalid/stale/unconfirmed scenarios, and no invented rain score. The same engine supplies hours and options, so this is a functional consistency check rather than independent validation of the provider's schedule.

For 8 November, the 60-minute visit had 37 possible starts in the requested 09–19 interval, according to that response. Morning preference ranked 09:00 first; afternoon preference ranked 15:00 first. Quietness and rain/exposure remained unknown. A required 23:00 start gave no feasible window. The 9 November response resolved to closed; user preference did not override it. These observations describe the retrieved schedule and are not a promise about real conditions or admission.

One provider invocation took **0.294 seconds**. Local scenario evaluation took **3.45–16.20 milliseconds** each, including first-call setup. These are single-place measurements; they do not measure multi-place order computation or constitute a performance distribution/SLA.

## Evidence and changes

- Aggregate technical record (original local evidence, omitted from this publication). No raw response/review text/author corpus or credentials were persisted.
- New `places-context verify-live CONFIRMED_PLACE_ID` command fetches details once, holds content in memory, and runs the local matrix. It prints a bounded summary without review text or authors.
- After the first live run, the verifier was strengthened to explicitly assert status names and top-ranked preferred-time penalties. The updated source compiles/tests locally; those extra assertions were not rerun live to avoid an unnecessary second billed request. This distinction is retained in the aggregate record.

## Reproduction

From the lab directory, with key already in private `.env.local`:

```sh
python3 scripts/places-context.py verify-live ChIJi_JxtdT1aS4R7Vhgb1ZBFaQ
```

This performs **one real Place Details request including reviews** (experience field tier) and picks tomorrow/the following day relative to the actual invocation. Do not compare later outputs as the same provider snapshot or date. The command reports content in the terminal but does not write a provider archive.

## Remaining boundary

Google credentials, Place Details schema and single-place window evaluation are now live-verified. A real travel adapter and explicit cross-provider identity mapping for the new planner remain unimplemented; no real-road multi-stop route was generated here. WeatherKit was not called in this run. Human preference relevance, public sentiment quality, current admission and field experience remain unverified. The production application, D/E paths and Apple key configuration were not changed.
