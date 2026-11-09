# Google Places context engine — verification

Date: 7 November 2026, WIB. Isolated lab implementation; no production app integration.

This document records the initial no-key verification. Subsequent [single-place live verification](GOOGLE_PLACES_CONTEXT_LIVE_2026-11-07.md) succeeded after the user configured the key; its evidence and limits are reported separately.

## Implemented

- Foundation-only `PlaceContextEngine` library and `places-context` CLI; no model downloads or new package dependencies.
- Places API (New) Text Search and Place Details adapter: explicit bounded field masks, optional reviews, authenticated headers, private key configuration, ephemeral/no-cache transport, redirect rejection, single-provider concurrency and bounded request counts.
- Google-shaped schemas preserve place/review IDs, authors, attribution, URLs, current/regular hours and nullable fields. No place identity automatically chosen from ambiguous search results.
- Full-stay time windows, current dated exceptions, closed status, timezone, split sessions, overnight and 24/7 handling. Missing closing time, missing schedule, stale data and unknown exposure are not invented.
- Rule-based temporal review indications with language/negation/conflict/staleness checks. These are weak hypotheses from at most five returned reviews, not public consensus or measured hourly crowd levels.
- Explicit user time wishes and goal priorities; caller-supplied full-visit weather; activity-specific exposure with a required evidence label. No API-only inference that outdoor seating means an outdoor activity.
- Bounded order-and-slot beam planner with exact-departure travel-provider interface, full stop/dwell/return/deadline preservation, missing-data and budget outcomes.
- Authenticated local capability/search/evaluation HTTP endpoints. Live Google calls require REST mode. Original D/E and app code paths are preserved.

## Observed validation

- **25 new tests passed**, plus **69 existing regular tests**. One fixture experiment test is intentionally skipped in the generic suite because it requires explicit input/output paths. Full test log (original local evidence, omitted from this publication).
- CLI synthetic end-to-end demo: three simulated Google-shaped HTTP calls. Quiet-reading preference chooses park before museum; afternoon-photo and rain-avoidance preferences choose museum before park. Every result retains both visits, full dwell and return; travel is explicitly synthetic 15 minutes. Demo JSON (original local evidence, omitted from this publication).
- Travel, waiting, dwell and elapsed are accounted separately. The rain-avoidance demo is explicitly a candidate with unknown waiting exposure, not a promise of a rain-free trip.
- Tests cover current closure versus regular hours, dated exceptions, overnight periods, 24/7 and malformed schedules, full stay/session boundaries, required time, stale/unknown data, negated/conflicting review evidence, partial/overlapping forecast coverage, attribution-carrying schemas, exact travel departure, missing ETA, bounded search, optional billing profiles, invalid IDs, provider/auth/quota errors, cancellation and credential redaction.
- Local HTTP smoke checks run with no key and with an intentionally invalid synthetic key, in replay mode only. Authentication, no-store, malformed requests, missing-key/replay guards and zero Google request counters are checked. HTTP evidence (original local evidence, omitted from this publication).
- Initial compile failed on a pure ID validator inherited from an actor-isolated client; corrected with a nonisolated pure validator. Initial failure log retained. Final build and tests passed.

## Limits

No real Google key was configured at verification time; **zero live Google calls** were made. Live credentials, field availability and data quality remain unverified. Synthetic preference-dependent output is a functional test, not demonstrated human relevance or public sentiment accuracy. No UI, iPhone runtime, field trip or production SLA was tested. The travel adapter in the demo is synthetic; a real provider adapter and explicit identity mapping are still needed to use the new order planner with live road ETAs.

Public API and product references checked on implementation date: [Places schema](https://developers.google.com/maps/documentation/places/web-service/reference/rest/v1/places), [Text Search](https://developers.google.com/maps/documentation/places/web-service/text-search), [Place Details and field tiers](https://developers.google.com/maps/documentation/places/web-service/place-details), [key setup](https://developers.google.com/maps/documentation/places/web-service/get-api-key).

Private `.env.local` was extended only with missing Google variable names; existing values were preserved, mode 600 retained. Live content is not persisted to the lab SQLite/catalogue or used for training. Source hashes and smoke-server cleanup are recorded in final verification. See [setup](GOOGLE_PLACES_CONTEXT_SETUP.md) for obtaining a key and making the first explicit live call.
