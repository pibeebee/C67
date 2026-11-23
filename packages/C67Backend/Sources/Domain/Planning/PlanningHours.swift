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
    public struct EntryRule: Decodable, Sendable {
        public enum Kind: String, Decodable, Sendable {
            case walkIn = "walk_in"
            case onsiteRegistration = "walk_in_with_onsite_registration"
            case onsiteTicket = "walk_in_with_onsite_ticket"
            case reservation = "reservation_required"
            case membership = "membership_required"
            case ticket = "ticket_required"
        }

        public let kind: Kind
        public let sourceURL: URL

        public init(kind: Kind, sourceURL: URL) {
            self.kind = kind
            self.sourceURL = sourceURL
        }
    }

    public let status: String
    public let hours: PlanningRegularHours?
    public let entryRule: EntryRule?

    public init(status: String, hours: PlanningRegularHours? = nil, entryRule: EntryRule? = nil) {
        self.status = status
        self.hours = hours
        self.entryRule = entryRule
    }

    private enum CodingKeys: String, CodingKey { case status, hours, entryRule }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = try values.decode(String.self, forKey: .status)
        hours = try values.decodeIfPresent(PlanningRegularHours.self, forKey: .hours)
        entryRule = try? values.decode(EntryRule.self, forKey: .entryRule)
    }
}

/// Typical visit times used as a preference when a venue's hours cannot be verified.
public struct EstimatedVisitWindow: Sendable {
    public let opensHour: Int
    public let closesHour: Int
    public static let source = "estimated_visit_window"

    public init(categories: [String]) {
        let keys = Set(categories.map {
            $0.lowercased().filter { $0.isLetter || $0.isNumber }.replacingOccurrences(of: "mkpoicategory", with: "")
        })
        if keys.contains("museum") { (opensHour, closesHour) = (9, 16) }
        else if !keys.isDisjoint(with: ["cinema", "movietheater", "movietheatre"]) { (opensHour, closesHour) = (10, 26) }
        else if !keys.isDisjoint(with: ["mall", "shoppingmall"]) { (opensHour, closesHour) = (10, 22) }
        else { (opensHour, closesHour) = (10, 17) }
    }

    public func interval(on date: Date, timeZone: String) -> DateInterval? {
        guard let zone = TimeZone(identifier: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = calendar.startOfDay(for: date)
        guard let opens = calendar.date(bySettingHour: opensHour, minute: 0, second: 0, of: day),
              let closeDay = calendar.date(byAdding: .day, value: closesHour / 24, to: day),
              let closes = calendar.date(bySettingHour: closesHour % 24, minute: 0, second: 0, of: closeDay),
              opens < closes else { return nil }
        return .init(start: opens, end: closes)
    }

    public var clockLabel: String {
        String(format: "%02d:00–%02d:00", opensHour, closesHour % 24)
    }
}
