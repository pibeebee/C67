import Foundation
import PlaceContextEngine

public struct OpenVenue: Codable, Sendable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var address: String
    public var branch: String
    public var latitude: Double
    public var longitude: Double
    public var categories: [String]
    public var sourceIDs: [String]
    public var sourceURLs: [String]
    public var operatorHosts: [String]
    public var operatorURLs: [URL]?
    public var areaHints: [String]?
    public var branchAliases: [String]?

    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "id_ID"))
            .lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }
}

public enum VenueField: String, CaseIterable, Codable, Sendable {
    case hours, access, activity
}

public struct VenueFact: Codable, Sendable {
    public var field: VenueField
    public var status: String
    public var value: String
    public var checkedAt: Date
    public var source: URL?
    public var quote: String?
    public var branchQuote: String?
    public var hours: [VenueHours]?
    public var validThrough: String?

    static func unknown(_ field: VenueField, at date: Date) -> Self {
        .init(field: field, status: "unknown", value: "", checkedAt: date)
    }

    public var freshUntil: Date { checkedAt.addingTimeInterval(30 * 86400) }
    func fresh(at now: Date) -> Bool { checkedAt <= now && freshUntil > now }

    func resolution(day: String) -> OperatingResolution? {
        guard field == .hours, status == "supported", let hours, let date = ContextClock.day(day),
              validThrough.map({ day <= $0 }) ?? true else { return nil }
        let weekday = ContextClock.calendar.component(.weekday, from: date)
        let previous = weekday == 1 ? 7 : weekday - 1
        let today = hours.filter { $0.weekday == weekday }
        let lastNight = hours.filter { $0.weekday == previous && !$0.closed && $0.endMinute > 1440 }
        guard !today.isEmpty || !lastNight.isEmpty else { return nil }
        var intervals = today.filter { !$0.closed }.map {
            OperatingInterval(start: date.addingTimeInterval(Double($0.startMinute * 60)),
                              end: date.addingTimeInterval(Double(min($0.endMinute, 1440) * 60)))
        }
        intervals += lastNight.map { .init(start: date, end: date.addingTimeInterval(Double(($0.endMinute - 1440) * 60))) }
        return .init(state: intervals.isEmpty ? "closed" : "available", source: source?.absoluteString ?? "Sumber publik",
                     intervals: intervals.sorted { $0.start < $1.start },
                     warnings: ["Jadwal reguler. Perubahan hari libur atau tanggal khusus perlu dikonfirmasi."])
    }
}

public struct VenueHours: Codable, Equatable, Sendable {
    public var weekday: Int  // Calendar convention: Sunday = 1
    public var startMinute: Int
    public var endMinute: Int
    public var closed: Bool

    private static let weekdays = [
        ["minggu", "ahad", "sunday", "sun"], ["senin", "monday", "mon"], ["selasa", "tuesday", "tue"],
        ["rabu", "wednesday", "wed"], ["kamis", "thursday", "thu"], ["jumat", "jum at", "friday", "fri"],
        ["sabtu", "saturday", "sat"]
    ]

    static func supported(_ rows: [Self], quote: String) -> Bool {
        guard !rows.isEmpty, rows.count <= 21 else { return false }
        let normalized = OpenVenue.normalized(quote)
        let text = " " + normalized + " "
        let blocked = [" libur nasional ", " jadwal khusus ", " sementara ", " temporary ", " holiday only ",
                       " berlaku mulai ", " acara ", " selama ramadan ", " event "]
        guard !blocked.contains(where: { text.contains($0) }) else { return false }

        let daily = [" setiap hari ", " tiap hari ", " daily ", " every day "].contains(where: { text.contains($0) })
        var days = Set(weekdays.indices.filter { index in
            weekdays[index].contains { text.contains(" " + $0 + " ") }
        }.map { $0 + 1 })
        if daily {
            days = Set(1 ... 7)
        } else {
            let dashNormalized = quote.lowercased().replacingOccurrences(of: "–", with: "-")
                .replacingOccurrences(of: "—", with: "-")
            for start in weekdays.indices {
                for end in weekdays.indices where start != end {
                    let matched = weekdays[start].contains { first in
                        weekdays[end].contains { last in
                            ["-", "sampai", "hingga", "to"].contains { separator in
                                let pair = "\\b" + first + "\\s*" + separator + "\\s*" + last + "\\b"
                                return dashNormalized.range(of: pair, options: .regularExpression) != nil
                            }
                        }
                    }
                    guard matched else { continue }
                    var cursor = start
                    while cursor != end {
                        days.insert(cursor + 1)
                        cursor = (cursor + 1) % 7
                    }
                    days.insert(end + 1)
                }
            }
        }

        let format = #"(?<![\d\p{L}])([01]?\d|2[0-4])(?:(?:[:.]([0-5]\d))\s*(am|pm)?|\s*(am|pm))(?![\d\p{L}])"#
        let regex = try! NSRegularExpression(pattern: format, options: [.caseInsensitive])
        let matches = regex.matches(in: quote, range: NSRange(quote.startIndex..., in: quote))
        let minutes = matches.compactMap { match -> Int? in
            guard let h = Range(match.range(at: 1), in: quote), var hour = Int(quote[h]) else { return nil }
            let minute = Range(match.range(at: 2), in: quote).flatMap { Int(quote[$0]) } ?? 0
            if let suffix = Range(match.range(at: 3), in: quote) ?? Range(match.range(at: 4), in: quote) {
                guard (1 ... 12).contains(hour) else { return nil }
                hour = hour % 12 + (quote[suffix].lowercased() == "pm" ? 12 : 0)
            }
            guard hour != 24 || minute == 0 else { return nil }
            return hour * 60 + minute
        }

        // One cited time range can apply to multiple days. Mixed schedules are
        // conservatively withheld when the quote cannot bind each range to its days.
        guard rows.allSatisfy({ days.contains($0.weekday) }),
              Set(rows.map(\.weekday)).count == rows.count else { return false }
        if rows.allSatisfy(\.closed) {
            return minutes.isEmpty && [" tutup ", " closed ", " libur "].contains(where: { text.contains($0) })
                && rows.allSatisfy { $0.startMinute == 0 && $0.endMinute == 0 }
        }
        guard minutes.count == 2, minutes[0] != minutes[1], minutes[0] < 1440 else { return false }
        let closing = minutes[1] < minutes[0] ? minutes[1] + 1440 : minutes[1]
        return rows.allSatisfy { !$0.closed && $0.startMinute == minutes[0] && $0.endMinute == closing }
    }
}
