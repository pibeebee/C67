# Itinerary weather and map adjustments

- Recommendation distance labels omit the straight-line wording; the value remains an approximate geodesic distance, not a road distance.
- The blue departure card displays the first stop's hourly rain chance at its estimated arrival, when a matching provider sample exists. It explicitly reports unavailable weather otherwise, including when changing dates moves outside existing forecast coverage. This does not add temperature or weather conditions to the server's current response.
- An expand control opens the same itinerary map and route geometry full screen and returns to the itinerary with Done. The existing sources disclosure remains unchanged pending product copy/content decisions.
- Source audit: the reasonable-order endpoint currently fetches Open-Meteo directly; the iOS WeatherKit implementation serves the older timed-planning path. WeatherKit-first ordering with Open-Meteo fallback and refresh for edited dates are not implemented or verified by this change.
- Verification: iPhone 18 Pro Max / iOS 27.2 synthetic tests passed for full-screen map open/close, recommendation distance, simulated Core Location, and a Pocket fixture itinerary including absent-weather messaging and save. No live WeatherKit, real weather or physical-device test ran.
