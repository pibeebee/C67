# Recommendation briefs

- `discover-coffee-reading.json`: no chosen places; coffee/reading and relaxed pace. Preserves the 2026-11-04 Jakarta service date of the captured experiment.
- `known-synthetic-time-facts.json`: three explicitly selected fictional places, illustrative hours/reading seats/afternoon photography preference; fixed service date 2026-11-05. Venue names and facts are not observations of real venues.

These are `RecommendationBriefV1` inputs for `fm-trip-eval recommend --input <path>`. Dates are intentionally retained. Edit the date explicitly for a new trip. `--search-snapshot <recommendations.json>` can freeze discovery candidates for a replay; otherwise discovery uses live MapKit.
