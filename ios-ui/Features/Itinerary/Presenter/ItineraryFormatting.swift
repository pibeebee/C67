import Foundation

enum ItineraryFormatting {
    static func date(_ date: Date, zone: String, locale: Locale) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()
        style.timeZone = TimeZone(identifier: zone) ?? .current
        style.locale = locale
        return date.formatted(style)
    }

    static func time(_ date: Date, zone: String, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: zone) ?? .current
        style.locale = locale
        return date.formatted(style)
    }
}
