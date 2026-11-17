import Foundation

public enum PlanningDayWindow {
    public static func remainingToday(at now: Date, timeZone: String) -> DateInterval? {
        guard let calendar = calendar(in: timeZone),
              let day = calendar.dateInterval(of: .day, for: now) else { return nil }
        let finish = day.end.addingTimeInterval(-1)
        return DateInterval(start: min(now.addingTimeInterval(600), finish), end: finish)
    }

    public static func tomorrow(after date: Date, timeZone: String) -> DateInterval? {
        guard let calendar = calendar(in: timeZone),
              let currentDay = calendar.dateInterval(of: .day, for: date),
              let nextDay = calendar.dateInterval(of: .day, for: currentDay.end),
              let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay.start) else { return nil }
        return DateInterval(start: morning, end: nextDay.end.addingTimeInterval(-1))
    }

    public static func isSameDay(_ lhs: Date, _ rhs: Date, timeZone: String) -> Bool {
        calendar(in: timeZone)?.isDate(lhs, inSameDayAs: rhs) == true
    }

    private static func calendar(in timeZone: String) -> Calendar? {
        guard let zone = TimeZone(identifier: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
