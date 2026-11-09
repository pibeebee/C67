import Foundation
import PlaceContextEngine
import PlannerEngine

enum SunsetOpportunityPolicy {
    static func moment(placeID: String, day: String, weather: WeatherEvidence, now: Date) -> VisitOpportunity? {
        guard placeID == SunsetVenueEvidence.placeID, weather.memberIDs.contains(placeID),
              weather.provider == "weatherkit", weather.complete, weather.expiresAt > now,
              weather.fetchedAt <= now.addingTimeInterval(300), weather.retrievedAt <= now.addingTimeInterval(300),
              let sunset = weather.sunset, ContextClock.label(sunset) == day else { return nil }
        return window(placeID: placeID, sunset: sunset, hours: weather.hours, checkedAt: weather.fetchedAt)
    }

    // The 45-minute interval and thresholds are a conservative pilot policy, not a measurement of light quality.
    static func window(placeID: String, sunset: Date, hours: [WeatherHour], checkedAt: Date) -> VisitOpportunity? {
        let start = sunset.addingTimeInterval(-45 * 60)
        var coveredUntil = start
        for hour in WeatherPolicy.sanitized(hours) {
            let nextHour = hour.start.addingTimeInterval(3600)
            guard hour.start <= coveredUntil, nextHour > coveredUntil else { continue }
            guard hour.rainChance <= 0.45, let clouds = hour.cloudCover, (0 ... 0.75).contains(clouds) else { return nil }
            coveredUntil = nextHour
            if coveredUntil >= sunset {
                return .init(id: "pre-sunset:" + placeID, placeID: placeID, start: start, end: sunset,
                             minimumMinutes: 20, sourceName: SunsetVenueEvidence.sourceName, sourceURL: SunsetVenueEvidence.sourceURL,
                             forecastCheckedAt: checkedAt)
            }
        }
        return nil
    }
}
