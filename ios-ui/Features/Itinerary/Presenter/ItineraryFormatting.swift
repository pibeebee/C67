import Foundation
import C67Domain

enum ItineraryFormatting {
    static func drivingEstimate(_ stop: ScheduledPlanningStop) -> String {
        let seconds = stop.experienceTravelSeconds
        let minutes = (seconds + 59) / 60
        if stop.roadDistanceMeters == nil { return String(localized: "≈ \(minutes) min · default") }
        return String(localized: "≈ \(minutes) min")
    }

    static func date(_ date: Date, zone: String, locale: Locale) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()
        style.timeZone = TimeZone(identifier: zone) ?? .current
        style.locale = locale
        return date.formatted(style)
    }

    static func time(_ date: Date?, zone: String, locale: Locale) -> String {
        guard let date else { return String(localized: "Not scheduled") }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: zone) ?? .current
        style.locale = locale
        return date.formatted(style)
    }
}
