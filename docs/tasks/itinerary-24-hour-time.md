# Itinerary time display

- Outcome: display itinerary departure, stop ranges, finish and active-trip planned times consistently as `HH:mm`, independently of the device's 12/24-hour preference. Dates continue to use the user's locale, and times use the trip's time zone.
- Verification: iPhone 18 Pro Max / iOS 27.2: 39 TripCreationTests passed, including Jakarta midnight, morning, noon and afternoon in US and Indonesian locales. The synthetic saved-trip preview displayed `08:00` and `08:00–08:30`. No live service was used.
