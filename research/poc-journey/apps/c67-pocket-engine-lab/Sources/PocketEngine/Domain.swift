import Foundation

public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    public var valid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
    public func distance(to other: Self) -> Double {
        let a = latitude * .pi / 180, b = other.latitude * .pi / 180
        let d = (other.longitude - longitude) * .pi / 180
        let h = pow(sin((b - a) / 2), 2) + cos(a) * cos(b) * pow(sin(d / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}

public enum Facet: String, Codable, CaseIterable, Identifiable, Sendable {
    case publicAccess, reading, coffee, quiet, outdoor, children, wheelchair, noMembership
    case indoor
    case semi_outdoor
    case rooftop
    case garden_seating
    case nature
    case heritage
    case architecture
    case city_view
    case public_art
    case local_cuisine
    case walking_path
    case children_play_area
    case cafe, restaurant, bakery, dessert_shop, tea_house, food_court, street_food_area
    case park, botanical_garden, urban_forest, public_square, waterfront_walk
    case museum, art_gallery, cultural_center, heritage_site, cinema, performance_venue, live_music_venue, karaoke
    case library, bookstore, coworking_space, creative_studio, workshop_venue
    case shopping_mall, traditional_market, thrift_shop, record_store, craft_shop
    case sports_center, swimming_pool, climbing_gym, bowling_alley, arcade, playground, cycling_track
    case specialty_coffee, brunch_cafe, dessert_cafe
    case indonesian_cuisine, japanese_cuisine, korean_cuisine
    case art_museum, history_museum, science_museum
    case used_books, comics, childrens_books

    public static let activityOptions: [Self] = [
        .publicAccess, .reading, .coffee, .quiet, .outdoor, .children, .wheelchair, .noMembership,
        .indoor, .semi_outdoor, .rooftop, .garden_seating, .nature, .heritage, .architecture, .city_view,
        .public_art, .local_cuisine, .walking_path, .children_play_area
    ]
    private static let activityFields = Set(activityOptions)
    public var isCategoryLabel: Bool { !Self.activityFields.contains(self) }
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .publicAccess: "Akses pengunjung umum"
        case .noMembership: "Tanpa keanggotaan"
        case .reading: "Membaca di tempat"
        case .coffee: "Minum kopi"
        case .quiet: "Suasana tenang"
        case .outdoor: "Kegiatan di luar ruang"
        case .children: "Kegiatan untuk anak"
        case .wheelchair: "Akses kursi roda"
        default: Interests.title(Interests.canonical(rawValue))
        }
    }
}
public enum Preference: String, Codable, CaseIterable, Identifiable, Sendable {
    case neutral, liked, required, avoided
    public var id: String { rawValue }
    public var title: String {
        switch self { case .neutral: "Bebas"; case .liked: "Disukai"; case .required: "Wajib"; case .avoided: "Hindari" }
    }
}
public enum FactStatus: String, Codable, Sendable { case supported, contradicted, unknown }

public struct Fact: Codable, Sendable {
    public var field: Facet
    public var status: FactStatus
    public var value: String
    public var sourceURL: String
    public var quote: String
    public var checkedAt: Date
    public var expiresAt: Date
    public func fresh(at date: Date) -> Bool {
        checkedAt <= date && date < min(expiresAt, checkedAt.addingTimeInterval(30 * 86400))
    }
}
public struct OpeningInterval: Codable, Hashable, Sendable {
    public var weekday: Int // Gregorian Sunday = 1.
    public var startMinute: Int
    public var endMinute: Int // May exceed 1440 for an explicit overnight interval.
    public var date: String? // YYYY-MM-DD, when the source supplies date-specific hours.
    public init(weekday: Int, startMinute: Int, endMinute: Int, date: String? = nil) {
        self.weekday = weekday; self.startMinute = startMinute; self.endMinute = endMinute; self.date = date
    }
    public var valid: Bool { (1 ... 7).contains(weekday) && (0 ..< 1440).contains(startMinute) && endMinute > startMinute && endMinute <= 2880 }
}
public struct HoursEvidence: Codable, Sendable {
    public var intervals: [OpeningInterval]
    public var checkedAt: Date
    public var expiresAt: Date
    public var sourceURL: String
    public var quote: String
    public func fresh(at date: Date) -> Bool {
        !intervals.isEmpty && intervals.allSatisfy(\.valid) && checkedAt <= date && date < min(expiresAt, checkedAt.addingTimeInterval(30 * 86400))
    }
}
public struct Venue: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var branch: String
    public var address: String
    public var coordinate: Coordinate
    public var categories: [String]
    public var aliases: [String]
    public var sourceURLs: [String]
    public var operatorURLs: [String]
    public var license: String
    public var facts: [Fact]
    public var hours: HoursEvidence?
    public init(id: String, name: String, branch: String, address: String, coordinate: Coordinate,
                categories: [String], aliases: [String] = [], sourceURLs: [String] = [],
                operatorURLs: [String] = [], license: String, facts: [Fact] = [], hours: HoursEvidence? = nil) {
        self.id = id; self.name = name; self.branch = branch; self.address = address
        self.coordinate = coordinate; self.categories = categories; self.aliases = aliases
        self.sourceURLs = sourceURLs; self.operatorURLs = operatorURLs; self.license = license
        self.facts = facts; self.hours = hours
    }
    public func effectiveCategories(at date: Date) -> [String] {
        var result = Set(categories.map(Interests.canonical))
        let reviewed = Dictionary(grouping: facts.filter { $0.field.isCategoryLabel && $0.fresh(at: date) }, by: \.field)
        for (field, facts) in reviewed {
            let key = Interests.canonical(field.rawValue)
            if facts.contains(where: { $0.status == .supported }) && !facts.contains(where: { $0.status == .contradicted }) {
                result.insert(key)
            } else {
                result.remove(key)
            }
        }
        return result.sorted()
    }
    public func status(_ field: Facet, at now: Date = .now) -> FactStatus {
        let values = facts.filter { $0.field == field && $0.fresh(at: now) }.map(\.status)
        if values.contains(.supported) && values.contains(.contradicted) { return .unknown }
        return values.contains(.contradicted) ? .contradicted : (values.contains(.supported) ? .supported : .unknown)
    }
}
public struct Catalog: Codable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var attribution: String
    public var venues: [Venue]
    public init(schemaVersion: Int, generatedAt: Date, attribution: String, venues: [Venue]) {
        self.schemaVersion = schemaVersion; self.generatedAt = generatedAt; self.attribution = attribution; self.venues = venues
    }
    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else { throw EngineError.invalid("Katalog bawaan tidak ditemukan.") }
        return try Codec.decoder().decode(Self.self, from: Data(contentsOf: url))
    }
    public func validated() throws -> Self {
        guard schemaVersion == 1, venues.count <= 20_000, Set(venues.map(\.id)).count == venues.count,
              venues.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.coordinate.valid && $0.facts.count <= Facet.allCases.count * 2 && ($0.hours?.intervals.allSatisfy(\.valid) ?? true) }) else {
            throw EngineError.invalid("Format katalog tidak sesuai kontrak Pocket Engine v1.")
        }
        return self
    }
}
public enum Codec {
    public static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    public static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }
}
public enum EngineError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}
public enum TripClock {
    public static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Jakarta")!; return c }
    public static func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "id_ID"), timeZone: calendar.timeZone))
    }
}

public struct Profile: Codable, Equatable, Sendable {
    public var categories: Set<String> = []
    public var themes: Set<PreferenceTheme> = []
    public var preferences: [Facet: Preference] = [:]
    public init() {}
    enum CodingKeys: CodingKey { case categories, themes, preferences }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decodeIfPresent(Set<String>.self, forKey: .categories) ?? []
        themes = try c.decodeIfPresent(Set<PreferenceTheme>.self, forKey: .themes) ?? []
        preferences = try c.decodeIfPresent([Facet: Preference].self, forKey: .preferences) ?? [:]
    }
}
public struct Assessment: Identifiable, Sendable {
    public var venue: Venue
    public var score: Int
    public var matchedInterests: Set<String>
    public var reasons: [String]
    public var reasonDescriptors: [String]
    public var blockers: [String]
    public var unknowns: [String]
    public var id: String { venue.id }
    public var eligible: Bool { blockers.isEmpty }
}
public enum Recommender {
    public static let minimumRecommendations = 3

    public static func recommendations(from assessments: [Assessment], profile: Profile) -> [Assessment] {
        let ordered = eligibleMatches(from: assessments, profile: profile)
        guard ordered.count >= minimumRecommendations else { return [] }
        // Maximum bipartite matching assigns a different venue to every representable interest.
        let interests = profile.interests.sorted()
        var assigned: [Int: String] = [:]
        func assign(_ interest: String, visited: inout Set<Int>) -> Bool {
            for index in ordered.indices where ordered[index].matchedInterests.contains(interest) {
                guard visited.insert(index).inserted else { continue }
                if let previous = assigned[index] {
                    if assign(previous, visited: &visited) { assigned[index] = interest; return true }
                } else { assigned[index] = interest; return true }
            }
            return false
        }
        for interest in interests { var visited = Set<Int>(); _ = assign(interest, visited: &visited) }
        let first = ordered.indices.filter { assigned[$0] != nil }
        return (first + ordered.indices.filter { assigned[$0] == nil }).map { ordered[$0] }
    }

    public static func eligibleMatches(from assessments: [Assessment], profile: Profile) -> [Assessment] {
        let hasPositive = !profile.interests.isEmpty || profile.preferences.values.contains { $0 == .liked || $0 == .required }
        var ids = Set<String>()
        return assessments.filter { assessment in
            let categoryMatches = profile.interests.isEmpty || !assessment.matchedInterests.isEmpty
            return assessment.eligible && categoryMatches && (!hasPositive || assessment.score > 0) && ids.insert(assessment.id).inserted
        }
        .sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
    }

    public static func assess(_ venue: Venue, profile: Profile, now: Date = .now) -> Assessment {
        var score = 0, reasons: [String] = [], descriptors: [String] = [], blockers: [String] = [], unknowns: [String] = []
        let hits = profile.interests.filter { profile.matches($0, venue: venue, at: now) }
        if !hits.isEmpty {
            score += hits.count * 20; reasons.append("Kategori sesuai minat: " + hits.sorted().joined(separator: ", "))
            descriptors.append("Place category matches user interests: " + hits.sorted().joined(separator: ", "))
        }
        for (facet, choice) in profile.preferences.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard choice != .neutral else { continue }
            let status = venue.status(facet, at: now)
            if choice == .required && status != .supported { blockers.append("\(facet.title): \(status == .unknown ? "belum diketahui" : "bertentangan")") }
            if choice == .avoided && status == .supported { blockers.append("Memiliki atribut yang dihindari: " + facet.title) }
            if status == .unknown { unknowns.append(facet.title) }
            if status == .supported && choice != .avoided {
                score += choice == .required ? 30 : 10; reasons.append(facet.title + " didukung bukti")
                descriptors.append("Supported evidence for " + choice.rawValue + " preference: " + facet.rawValue)
            }
            if status == .contradicted && choice == .liked { score -= 10 }
        }
        if reasons.isEmpty {
            reasons.append("Kandidat umum; kecocokan kegiatan belum terbukti.")
            descriptors.append("Unpersonalized candidate. No supported personalized activity evidence.")
        }
        return .init(venue: venue, score: score, matchedInterests: hits, reasons: reasons, reasonDescriptors: descriptors, blockers: blockers, unknowns: unknowns)
    }
}

public struct TripOverride: Codable, Equatable, Sendable {
    public var day: String
    public var opens: Int
    public var closes: Int
    public var publicAccessConfirmed: Bool
    public init(day: String, opens: Int, closes: Int, publicAccessConfirmed: Bool) {
        self.day = day; self.opens = opens; self.closes = closes; self.publicAccessConfirmed = publicAccessConfirmed
    }
}
public enum VisitTiming: Codable, Equatable, Sendable {
    case preferred(Int)
    case required(Int)
    case notBefore(Int)

    public var minute: Int {
        switch self {
        case .preferred(let minute), .required(let minute), .notBefore(let minute): minute
        }
    }
}
public struct StopChoice: Codable, Identifiable, Equatable, Sendable {
    public var venueID: String
    public var required: Bool
    public var durationMinutes: Int
    public var override: TripOverride?
    public var timing: VisitTiming?
    public var id: String { venueID }
    public init(venueID: String, required: Bool = true, durationMinutes: Int = 60,
                override: TripOverride? = nil, timing: VisitTiming? = nil) {
        self.venueID = venueID; self.required = required; self.durationMinutes = durationMinutes
        self.override = override; self.timing = timing
    }
}
