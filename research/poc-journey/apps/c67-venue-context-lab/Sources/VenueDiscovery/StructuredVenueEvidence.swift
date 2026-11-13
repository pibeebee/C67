import Foundation

/// Deterministic parsing of a branch's own schema.org metadata. No LLM inference.
enum StructuredVenueEvidence {
    static func branchAnchors(for venue: OpenVenue) -> [String] {
        guard venue.branchAliases?.isEmpty ?? true else { return [] }
        let generic: Set<String> = ["jakarta", "selatan", "barat", "pusat", "timur", "utara", "jalan", "gedung", "ground", "floor", "lantai", "online", "delivery", "record"]
        return OpenVenue.normalized(venue.branch).split(separator: " ").map(String.init)
            .filter { $0.count >= 5 && !generic.contains($0) }
    }

    static func identityMatches(_ text: String, venue: OpenVenue, source: URL? = nil) -> Bool {
        let actual = OpenVenue.normalized(text)
        let names = ([venue.name] + venue.aliases + (venue.branchAliases ?? [])).map(OpenVenue.normalized).filter { $0.count >= 5 }
        let named = names.contains(where: { actual.contains($0) })
        if !named {
            // A branded operator domain can supply brand identity, but the cited text
            // must independently prove the street/branch and its number.
            guard let source, FirecrawlClient.allowed(source, for: venue), let host = source.host else { return false }
            let ignored: Set<String> = ["coffee", "library", "perpustakaan", "museum", "toko", "kopi", "jakarta", "the", "and", "cafe"]
            let branchWords = Set(OpenVenue.normalized(venue.branch).split(separator: " ").map(String.init))
            let brand = OpenVenue.normalized(venue.name).split(separator: " ").map(String.init)
                .filter { !ignored.contains($0) && !branchWords.contains($0) }.joined()
            let numeric = branchWords.filter { $0.allSatisfy(\.isNumber) }
            let locationWords = branchWords.filter { $0.count >= 5 && !ignored.contains($0) }
            let actualTokens = Set(actual.split(separator: " ").map(String.init))
            guard brand.count >= 5, OpenVenue.normalized(host).replacingOccurrences(of: " ", with: "").contains(brand),
                  !numeric.isEmpty, numeric.isSubset(of: actualTokens),
                  !locationWords.isEmpty, locationWords.isSubset(of: actualTokens) else { return false }
        }
        if (venue.branchAliases ?? []).map(OpenVenue.normalized).contains(where: { $0.count >= 8 && actual.contains($0) }) { return true }
        let branch = OpenVenue.normalized(venue.branch)
        let address = OpenVenue.normalized(venue.address)
        if branch.count >= 5 && actual.contains(branch) || address.count >= 8 && actual.contains(address) { return true }
        let generic: Set<String> = ["jalan", "jakarta", "selatan", "barat", "pusat", "timur", "utara", "raya", "lantai", "ground", "floor", "map", "record", "says"]
        let expected = Set(branch.split(separator: " ").map(String.init).filter { $0.count >= 4 && !generic.contains($0) })
        let actualTokens = Set(actual.split(separator: " ").map(String.init))
        return !expected.isEmpty && expected.intersection(actualTokens).count >= min(2, expected.count)
    }

    static func hours(in page: SourcePage, venue: OpenVenue) -> VenueFact? {
        for block in page.blocks ?? [] where block.kind == "jsonld" {
            guard let data = block.text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = object["name"] as? String, !name.isEmpty else { continue }
            let addressData = object["address"].flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed, .sortedKeys]) }
            let address = addressData.map { String(decoding: $0, as: UTF8.self) } ?? ""
            // Hours, descriptions and unrelated nested objects cannot establish branch identity.
            guard identityMatches(name + " " + address, venue: venue), let rows = parseHours(object), !rows.isEmpty else { continue }
            return .init(field: .hours, status: "supported", value: "Jadwal mingguan dari metadata cabang resmi",
                         checkedAt: page.fetchedAt, source: page.url, quote: block.text, branchQuote: block.text, hours: rows)
        }
        return nil
    }

    static func parseHours(_ object: [String: Any]) -> [VenueHours]? {
        // Dated schedules require separate holiday/validity handling, so are withheld here.
        guard object["specialOpeningHoursSpecification"] == nil else { return nil }
        if let specification = object["openingHoursSpecification"] {
            let entries: [[String: Any]]
            if let array = specification as? [[String: Any]] { entries = array }
            else if let item = specification as? [String: Any] { entries = [item] }
            else { return nil }
            var rows: [VenueHours] = []
            for item in entries {
                guard item["validFrom"] == nil, item["validThrough"] == nil,
                      let opens = minute(item["opens"] as? String), let closes = minute(item["closes"] as? String),
                      opens < 1440, opens != closes else { return nil }
                let days = (item["dayOfWeek"] as? [String]) ?? (item["dayOfWeek"] as? String).map { [$0] } ?? []
                guard !days.isEmpty, days.allSatisfy({ weekday($0) != nil }) else { return nil }
                rows += days.compactMap { day in weekday(day).map {
                    VenueHours(weekday: $0, startMinute: opens, endMinute: closes < opens ? closes + 1440 : closes, closed: false)
                } }
            }
            return consistent(rows)
        }
        let strings = (object["openingHours"] as? [String]) ?? (object["openingHours"] as? String).map { [$0] } ?? []
        guard !strings.isEmpty else { return nil }
        let days = ["Su": 1, "Mo": 2, "Tu": 3, "We": 4, "Th": 5, "Fr": 6, "Sa": 7]
        let regex = try! NSRegularExpression(pattern: #"^((?:Mo|Tu|We|Th|Fr|Sa|Su)(?:\s*[-,]\s*(?:Mo|Tu|We|Th|Fr|Sa|Su))*)\s+(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})$"#)
        var rows: [VenueHours] = []
        for text in strings {
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let d = Range(match.range(at: 1), in: text), let o = Range(match.range(at: 2), in: text), let c = Range(match.range(at: 3), in: text),
                  let opens = minute(String(text[o])), let closes = minute(String(text[c])), opens < 1440, opens != closes else { return nil }
            var selected = Set<Int>()
            for group in text[d].split(separator: ",") {
                let bounds = group.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let first = bounds.first.flatMap({ days[$0] }), let last = bounds.last.flatMap({ days[$0] }) else { return nil }
                var day = first
                selected.insert(day)
                while day != last { day = day == 7 ? 1 : day + 1; selected.insert(day) }
            }
            rows += selected.sorted().map { .init(weekday: $0, startMinute: opens, endMinute: closes < opens ? closes + 1440 : closes, closed: false) }
        }
        return consistent(rows)
    }

    private static func weekday(_ value: String) -> Int? {
        let text = value.split(separator: "/").last.map(String.init) ?? value
        return ["Sunday": 1, "Monday": 2, "Tuesday": 3, "Wednesday": 4, "Thursday": 5, "Friday": 6, "Saturday": 7][text]
    }
    private static func minute(_ value: String?) -> Int? {
        guard let value, value.range(of: #"^\d{2}:\d{2}(:00)?$"#, options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0 ... 24).contains(parts[0]), (0 ... 59).contains(parts[1]), parts[0] < 24 || parts[1] == 0 else { return nil }
        return parts[0] * 60 + parts[1]
    }
    private static func consistent(_ rows: [VenueHours]) -> [VenueHours]? {
        guard !rows.isEmpty, rows.count <= 21 else { return nil }
        let sorted = rows.sorted { $0.weekday == $1.weekday ? $0.startMinute < $1.startMinute : $0.weekday < $1.weekday }
        for (a, b) in zip(sorted, sorted.dropFirst()) where a.weekday == b.weekday && a.endMinute > b.startMinute { return nil }
        return sorted
    }
}
