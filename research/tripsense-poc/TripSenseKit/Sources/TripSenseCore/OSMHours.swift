import Foundation

/// A deliberately limited grammar. Unsupported clauses invalidate the entire expression.
public enum WeeklyHoursParser {
    private static let days = ["Su": 1, "Mo": 2, "Tu": 3, "We": 4, "Th": 5, "Fr": 6, "Sa": 7]
    private struct Interval { let start: Int; let end: Int }
    public static func windows(_ expression: String, start: Date, end: Date, timeZone: TimeZone) -> [HoursWindow]? {
        guard end >= start else { return nil }
        // Ambiguous/missing wall times around DST transitions are not guessed.
        if let transition = timeZone.nextDaylightSavingTimeTransition(after: start.addingTimeInterval(-172800)), transition <= end.addingTimeInterval(86400) { return nil }
        var rules: [Int: [Interval]] = [:]
        if expression.trimmingCharacters(in: .whitespacesAndNewlines) == "24/7" {
            for day in 1 ... 7 { rules[day] = [Interval(start: 0, end: 1440)] }
        } else {
            let parts = expression.split(separator: ";", omittingEmptySubsequences: false)
            guard !parts.isEmpty else { return nil }
            for raw in parts {
                let clause = raw.trimmingCharacters(in: .whitespaces)
                let pieces = clause.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard pieces.count == 2 else { return nil }
                var selected: Set<Int> = []
                for piece in pieces[0].split(separator: ",", omittingEmptySubsequences: false) {
                    let range = piece.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                    guard (1 ... 2).contains(range.count), let first = days[range[0]] else { return nil }
                    if range.count == 1 { selected.insert(first) }
                    else {
                        guard let last = days[range[1]] else { return nil }
                        var current = first
                        while true { selected.insert(current); if current == last { break }; current = current % 7 + 1 }
                    }
                }
                guard !selected.isEmpty, selected.allSatisfy({ rules[$0] == nil }) else { return nil }
                var intervals: [Interval] = []
                if pieces[1] != "off" {
                    for value in pieces[1].split(separator: ",", omittingEmptySubsequences: false) {
                        let pair = value.split(separator: "-", omittingEmptySubsequences: false)
                        guard pair.count == 2, let open = time(String(pair[0]), allow24: false),
                              let close = time(String(pair[1]), allow24: true), open != close else { return nil }
                        intervals.append(.init(start: open, end: close <= open ? close + 1440 : close))
                    }
                    let sorted = intervals.sorted { $0.start < $1.start }
                    for i in 1 ..< max(1, sorted.count) where sorted[i].start < sorted[i - 1].end { return nil }
                }
                for day in selected { rules[day] = intervals }
            }
        }
        // Do not guess how an explicit next-day rule interacts with an overnight rule.
        for (weekday, intervals) in rules where intervals.contains(where: { $0.end > 1440 }) {
            if rules[weekday % 7 + 1] != nil { return nil }
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let first = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)),
              let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) else { return nil }
        var result: [HoursWindow] = []; var day = first
        while day <= last {
            let weekday = calendar.component(.weekday, from: day)
            for interval in rules[weekday] ?? [] {
                guard let opens = calendar.date(byAdding: .minute, value: interval.start, to: day),
                      let closes = calendar.date(byAdding: .minute, value: interval.end, to: day) else { return nil }
                if closes > start && opens <= end { result.append(.init(opens: opens, closes: closes)) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { return nil }
            day = next
        }
        var merged: [HoursWindow] = []
        for window in result.sorted(by: { $0.opens < $1.opens }) {
            if let previous = merged.last, window.opens <= previous.closes {
                merged[merged.count - 1].closes = max(previous.closes, window.closes)
            } else { merged.append(window) }
        }
        return merged
    }
    private static func time(_ value: String, allow24: Bool) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]), (0 ... 59).contains(m),
              (0 ... 23).contains(h) || (allow24 && h == 24 && m == 0) else { return nil }
        return h * 60 + m
    }
}

@MainActor public final class OSMHoursProvider: OpeningHoursProviding {
    public typealias Loader = @Sendable (URLRequest) async throws -> Data
    private let endpoint: URL
    private let loader: Loader
    private let diagnostics: Diagnostics
    private let gate: OSMRequestGate
    private var cache: [String: (Date, Data)] = [:]
    public private(set) var websites: [String: URL] = [:]
    public private(set) var sourceLinks: [String: URL] = [:]
    public init(diagnostics: Diagnostics, endpoint: URL = URL(string: "https://overpass-api.de/api/interpreter")!,
                loader: Loader? = nil, gate: OSMRequestGate? = nil) {
        self.diagnostics = diagnostics; self.endpoint = endpoint; self.gate = gate ?? .shared
        self.loader = loader ?? { request in try await OverpassHTTP.load(request).0 }
    }
    public func hours(for place: Place) -> OpeningHours { .unknown }
    public func fetchHours(for places: [Place], start: Date, end: Date, timeZone: TimeZone) async -> [String: OpeningHours] {
        guard !places.isEmpty, places.count <= 6, Set(places.map(\.id)).count == places.count,
              places.allSatisfy({ $0.coordinate.isValid }) else { return [:] }
        let key = places.map { "\($0.id):\($0.coordinate.latitude),\($0.coordinate.longitude)" }.joined(separator: "|")
        let data: Data
        let fetched: Date
        websites.removeAll(); sourceLinks.removeAll()
        do {
            if let (date, saved) = cache[key], Date().timeIntervalSince(date) < 3600 { data = saved; fetched = date }
            else {
                let queries = places.map { "nwr(around:150,\($0.coordinate.latitude),\($0.coordinate.longitude))[name];" }.joined()
                let query = "[out:json][timeout:20];(\(queries));out center;"
                try gate.acquire(endpoint)
                defer { gate.release(endpoint) }
                let request = OverpassHTTP.request(endpoint: endpoint, query: query)
                data = try await loader(request)
                guard data.count <= 2_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
                try Task.checkCancellation(); fetched = Date()
            }
            let response = try JSONDecoder().decode(OSMResponse.self, from: data)
            cache[key] = (fetched, data)
            var results: [String: OpeningHours] = [:]
            for place in places {
                let match = Self.match(place: place, elements: response.elements, start: start, end: end, zone: timeZone, fetched: fetched)
                results[place.id] = match.hours
                websites[place.id] = match.website
                sourceLinks[place.id] = match.source
            }
            diagnostics.record("OpenStreetMap lookup: \(places.count) places, \(results.values.filter { $0.windows != nil }.count) sourced hours; coordinates redacted")
            return results
        } catch is CancellationError { return [:] }
        catch HoursServiceError.httpStatus(let status, let retryAfter) {
            if status == 406 || status == 429 || (status == 503 && retryAfter != nil) {
                let until = gate.reject(endpoint, retryAfter: retryAfter)
                diagnostics.record("OpenStreetMap HTTP \(status); cooldown until UTC \(until.ISO8601Format()); no automatic retry")
            } else { diagnostics.record("OpenStreetMap returned HTTP \(status); hours unknown") }
            return Dictionary(uniqueKeysWithValues: places.map { ($0.id, .unknownDetail("OpenStreetMap unavailable")) })
        }
        catch HoursServiceError.cooldown(let until) {
            diagnostics.record("OpenStreetMap cooldown until UTC \(until.ISO8601Format()); no network request sent")
            return Dictionary(uniqueKeysWithValues: places.map { ($0.id, .unknownDetail("OpenStreetMap is cooling down; try again later")) })
        }
        catch HoursServiceError.busy {
            diagnostics.record("OpenStreetMap request already active; duplicate request suppressed")
            return Dictionary(uniqueKeysWithValues: places.map { ($0.id, .unknownDetail("OpenStreetMap request already active")) })
        }
        catch {
            let failure = error as NSError
            diagnostics.record("OpenStreetMap unavailable or invalid: \(failure.domain) code \(failure.code); hours unknown")
            return Dictionary(uniqueKeysWithValues: places.map { ($0.id, .unknownDetail("OpenStreetMap unavailable")) })
        }
    }
    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func houseNumber(in address: String) -> String? {
        let patterns = ["^\\s*([0-9]+[a-zA-Z]?)\\b", "(?i)\\b(?:no\\.?|nomor)\\s*([0-9]+[a-zA-Z]?)\\b"]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)),
                  let range = Range(match.range(at: 1), in: address) else { continue }
            return String(address[range])
        }
        return nil
    }
    private static func match(place: Place, elements: [OSMElement], start: Date, end: Date, zone: TimeZone, fetched: Date) -> (hours: OpeningHours, website: URL?, source: URL?) {
        let wanted = normalize(place.name)
        guard !wanted.isEmpty else { return (.unknownDetail("No reliable place name"), nil, nil) }
        let matches = elements.filter { element in
            guard ["node", "way", "relation"].contains(element.type), element.id > 0,
                  let coordinate = element.coordinate, place.coordinate.distance(to: coordinate) <= 100 else { return false }
            let names = [element.tags["name"], element.tags["name:en"], element.tags["alt_name"]]
                .compactMap { $0 }.flatMap { $0.split(separator: ";").map(String.init) }
            guard names.contains(where: { normalize($0) == wanted }) else { return false }
            // A recognized house-number conflict is enough to reject a match.
            if let house = element.tags["addr:housenumber"], let found = houseNumber(in: place.address),
               normalize(house) != normalize(found) { return false }
            return true
        }
        guard matches.count == 1, let item = matches.first else { return (.unknownDetail(matches.isEmpty ? "No matching OSM place" : "Ambiguous OSM match"), nil, nil) }
        let website = (item.tags["website"] ?? item.tags["contact:website"]).flatMap(URL.init(string:)).flatMap { (["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil) ? $0 : nil }
        let source = URL(string: "https://www.openstreetmap.org/\(item.type)/\(item.id)")
        guard let expression = item.tags["opening_hours"],
              let windows = WeeklyHoursParser.windows(expression, start: start, end: end, timeZone: zone),
              let source else { return (.unknownDetail("Missing or unsupported OSM hours"), website, source) }
        return (.sourced(windows: windows, metadata: .init(objectID: "\(item.type)/\(item.id)", expression: expression,
                                                           sourceURL: source, websiteURL: website, fetchedAt: fetched,
                                                           checkedDate: item.tags["check_date:opening_hours"])), website, source)
    }
}
private struct OSMResponse: Decodable { let elements: [OSMElement] }
private struct OSMElement: Decodable {
    struct Center: Decodable { let lat: Double; let lon: Double }
    let type: String
    let id: Int64
    let lat: Double?
    let lon: Double?
    let center: Center?
    let tags: [String: String]
    var coordinate: Coordinate? {
        if let lat, let lon { return Coordinate(lat, lon) }
        if let center { return Coordinate(center.lat, center.lon) }
        return nil
    }
}
