import Foundation

/// Provider hours are session-only. Regular hours do not establish special-date access.
public struct PlanningRegularHours: Decodable, Sendable {
    public struct Interval: Decodable, Sendable {
        public let startSeconds: Int
        public let endSeconds: Int
    }
    public struct Day: Decodable, Sendable {
        public let weekday: Int
        public let intervals: [Interval]
    }
    public let placeId: String
    public let timezone: String
    public let weekly: [Day]

    public enum Match: String, Sendable { case within, partial, outside, unknown }

    /// Match the complete estimated visit in the venue's local calendar. No waiting is implied.
    public func match(start: Date, end: Date) -> Match {
        guard start < end, end.timeIntervalSince(start) <= 86_400,
              let zone = TimeZone(identifier: timezone), weekly.count == 7,
              Set(weekly.map(\.weekday)) == Set(1 ... 7) else { return .unknown }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        guard let first = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: start)),
              let last = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)) else { return .unknown }
        var day = first
        var windows: [(Date, Date)] = []
        while day <= last {
            guard let record = weekly.first(where: { $0.weekday == cal.component(.weekday, from: day) }) else { return .unknown }
            for interval in record.intervals {
                let a = interval.startSeconds, b = interval.endSeconds
                guard (0 ..< 86_400).contains(a), (0 ... 86_400).contains(b), a != b else { return .unknown }
                // Refuse DST-transition days: seconds-from-midnight cannot be assumed to be wall-clock time.
                guard let tomorrow = cal.date(byAdding: .day, value: 1, to: day), tomorrow.timeIntervalSince(day) == 86_400 else { return .unknown }
                let finishDay = b <= a ? tomorrow : day
                if b <= a, let following = cal.date(byAdding: .day, value: 1, to: finishDay), following.timeIntervalSince(finishDay) != 86_400 { return .unknown }
                windows.append((day.addingTimeInterval(Double(a)), finishDay.addingTimeInterval(Double(b))))
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day), next > day else { return .unknown }
            day = next
        }
        windows.sort { $0.0 < $1.0 }
        var cursor = start
        var overlap = false
        for (a, b) in windows {
            if a < end, b > start { overlap = true }
            if a <= cursor, b > cursor { cursor = b }
            if cursor >= end { return .within }
        }
        return overlap ? .partial : .outside
    }
}

public struct PlanningHoursLookup: Decodable, Sendable {
    public let status: String
    public let hours: PlanningRegularHours?
    public init(status: String, hours: PlanningRegularHours? = nil) { self.status = status; self.hours = hours }
}
