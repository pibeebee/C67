import Foundation

public enum PlanningDayWindow {
    public static func v41Inputs(_ original: PlanningInput, at anchor: Date) throws -> [PlanningInput] {
        guard let calendar = calendar(in: original.timeZone) else { throw PlanningError.invalidInput }
        let options = original.enginePreferences
        if options?.scheduleSource == .manual || options?.scheduleSource == .resolved || (options?.scheduleSource == nil && options?.usesAutomaticTripDate != true) {
            return [original]
        }
        let now = options?.timingAnchor ?? anchor
        let offsets: [Int]
        switch options?.tripTiming {
        case .now: offsets = [0]
        case .tomorrow: offsets = [1]
        case .inAFewDays: offsets = [2, 3]
        case .bestDay: offsets = [0, 1, 2]
        case nil:
            if original.places.contains(where: { $0.visitConfirmation != nil || $0.activitySession != nil || $0.preferredAfter != nil || $0.preferredBefore != nil }) {
                return [original]
            }
            offsets = [0]
        }
        return try offsets.map { offset in
            var input = original
            let window: DateInterval?
            if offset == 0 {
                // Keep the draft representable at midnight; the planner still sees zero usable minutes.
                window = remainingToday(at: now, timeZone: original.timeZone).map { today in
                    today.duration > 0 ? today : .init(start: today.end.addingTimeInterval(-1), end: today.end)
                }
            } else {
                let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
                let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
                window = calendar.dateInterval(of: .day, for: day).map { .init(start: start, end: $0.end.addingTimeInterval(-1)) }
            }
            guard let window else { throw PlanningError.invalidInput }
            input.startsAt = window.start
            input.finishBy = window.end
            input.enginePreferences?.timingAnchor = now
            return input
        }
    }

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
