import Foundation
import C67Domain

enum ItineraryFormatting {
    static func drivingEstimate(_ stop: ScheduledPlanningStop, showsApproximation: Bool = true) -> String {
        let seconds = stop.experienceTravelSeconds
        let minutes = (seconds + 59) / 60
        let duration = String(localized: "\(minutes) min")
        let estimate = showsApproximation ? "≈ \(duration)" : duration
        if stop.roadDistanceMeters == nil { return String(localized: "\(estimate) · default") }
        return estimate
    }

    static func date(_ date: Date, zone: String, locale: Locale) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()
        style.timeZone = TimeZone(identifier: zone) ?? .current
        style.locale = locale
        return date.formatted(style)
    }

    static func time(_ date: Date?, zone: String, locale _: Locale) -> String {
        guard let date else { return String(localized: "Not scheduled") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone) ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
