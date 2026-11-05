import Foundation
import FoundationModels

public enum Experience: String, Codable, CaseIterable, Identifiable, Sendable {
    case coffee, reading, food, nature, culture, shopping, entertainment, photography, art
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .coffee: "Kopi"
        case .reading: "Membaca"
        case .food: "Kuliner"
        case .nature: "Alam dan outdoor"
        case .culture: "Budaya dan sejarah"
        case .shopping: "Belanja dan lifestyle"
        case .entertainment: "Hiburan"
        case .photography: "Arsitektur dan fotografi"
        case .art: "Seni dan kreativitas"
        }
    }
    var query: String {
        switch self {
        case .coffee: "coffee shop"
        case .reading: "bookstore"
        case .food: "restaurant"
        case .nature: "park"
        case .culture: "museum"
        case .shopping: "shopping mall"
        case .entertainment: "cinema"
        case .photography: "landmark"
        case .art: "art gallery"
        }
    }
    var legacy: Interest? {
        switch self {
        case .coffee: .coffee
        case .reading: .reading
        case .food: .food
        case .nature: .outdoor
        case .culture, .art: .culture
        case .photography: .photography
        default: nil
        }
    }
}
public enum SpendingPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case flexible, under100k, from100to250k, from250to500k, above500k
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .flexible: "Fleksibel"
        case .under100k: "Di bawah Rp100.000"
        case .from100to250k: "Rp100.000–250.000"
        case .from250to500k: "Rp250.000–500.000"
        case .above500k: "Di atas Rp500.000"
        }
    }
}
public enum DestinationPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case noPreference, popular, local, mix
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .noPreference: "Tidak ada preferensi"
        case .popular: "Populer"
        case .local: "Lokal / hidden gems"
        case .mix: "Campuran"
        }
    }
}
public enum GettingAround: String, Codable, CaseIterable, Identifiable, Sendable {
    case flexible, publicTransport, car, motorcycle, walking
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .flexible: "Fleksibel"
        case .publicTransport: "Transportasi umum"
        case .car: "Mobil"
        case .motorcycle: "Motor"
        case .walking: "Jalan kaki"
        }
    }
}
public enum WalkingPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case depends, minimal, moderate, long
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .depends: "Tergantung perjalanan"
        case .minimal: "Sedikit berjalan"
        case .moderate: "Sedang"
        case .long: "Nyaman berjalan jauh"
        }
    }
}
public struct RecommendationBriefV1: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var hasPlaces = false
    public var places: [CandidateV1] = []
    public var experiences: [Experience] = []
    public var avoids: [Experience] = []
    public var pace: Pace = .balanced
    public var spending: SpendingPreference = .flexible
    public var destinations: DestinationPreference = .noPreference
    public var transport: GettingAround = .flexible
    public var walking: WalkingPreference = .depends
    public var date: String
    public var area = "Jakarta"
    public var text = ""
    public var excludedIDs: [String] = []
    public init(date: String = Self.today()) { self.date = date }
    public static func today() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        (try? Codec.encode(lhs)) == (try? Codec.encode(rhs))
    }
    public func validate() throws {
        guard schemaVersion == 1, area == "Jakarta", date.count == 10,
              let parsed = Codec.date(date + "T12:00:00+07:00"),
              !text.contains("\u{0000}"), text.count <= 1500,
              places.count <= 6, Set(places.map(\.id)).count == places.count,
              !hasPlaces || !places.isEmpty,
              Set(experiences).isDisjoint(with: Set(avoids))
        else {
            throw LabError.invalid(
                "Periksa tanggal, pilihan minat, dan maksimal enam tempat. Pilih setidaknya satu tempat jika sudah punya tujuan."
            )
        }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.string(from: parsed) == date else {
            throw LabError.invalid("Tanggal tidak valid.")
        }
        for place in places { try RecommendationValidation.candidate(place) }
    }
    public var notices: [String] {
        var result = [
            "Jam operasional, harga, keramaian, aksesibilitas, dan status populer/lokal hanya diketahui jika ada sumbernya."
        ]
        if spending != .flexible {
            result.append(
                "Budget \(spending.title) dicatat; kesesuaian biaya belum dapat diverifikasi dari data MapKit yang tersedia."
            )
        }
        if destinations != .noPreference {
            result.append(
                "Preferensi \(destinations.title) dicatat; popularitas/hidden gems belum diverifikasi.")
        }
        if transport != .flexible || walking != .depends {
            result.append(
                "Preferensi transportasi dan berjalan dicatat; jarak, akses, rute, dan waktu perpindahan tidak dihitung pada eksperimen ini."
            )
        }
        return result
    }
}

@Generable public enum PlaceSuitability: String, Codable, Sendable {
    case relevant, possible, unrelated, insufficientData
}
@Generable public enum VisitTimeBasis: String, Codable, Sendable {
    case suppliedFacts, generalActivitySuggestion, unknown
}
@Generable public struct PlaceAdviceOutput: Codable, Sendable {
    @Guide(description: "Personal fit supported by the supplied candidate category or facts")
    public var suitability: PlaceSuitability
    @Guide(description: "Brief reason for fit; missing facts remain unknown")
    public var reason: String
    @Guide(description: "Broad visit suggestion only, not a schedule or proven best time")
    public var window: VisitWindow
    @Guide(
        description:
        "Use generalActivitySuggestion for activity ideas; suppliedFacts ONLY for cited opensMinute, closesMinute or experienceWindow facts; otherwise unknown"
    )
    public var timeBasis: VisitTimeBasis
    @Guide(
        description:
        "Explain tentative activity timing or the supplied time fact; never treat identity as time evidence"
    )
    public var timeReason: String
    @Guide(
        description: "Copy exact evidence IDs from this candidate, never place IDs", .maximumCount(4))
    public var evidenceIDs: [String]
    @Guide(.maximumCount(5)) public var unknowns: [String]
    public init(
        suitability: PlaceSuitability, reason: String, window: VisitWindow = .unknown,
        timeBasis: VisitTimeBasis = .unknown, timeReason: String, evidenceIDs: [String],
        unknowns: [String]
    ) {
        self.suitability = suitability
        self.reason = reason
        self.window = window
        self.timeBasis = timeBasis
        self.timeReason = timeReason
        self.evidenceIDs = evidenceIDs
        self.unknowns = unknowns
    }
}
@Generable public struct DiscoveryExplanation: Codable, Sendable {
    public var summary: String
    @Guide(description: "Copy only exact IDs from evidence[].id", .maximumCount(6)) public
    var evidenceIDs: [String]
    @Guide(.maximumCount(5)) public var unknowns: [String]
    public init(summary: String, evidenceIDs: [String] = [], unknowns: [String] = []) {
        self.summary = summary
        self.evidenceIDs = evidenceIDs
        self.unknowns = unknowns
    }
}
public struct PlaceAdviceV1: Codable, Identifiable, Sendable {
    public var candidate: CandidateV1
    public var advice: PlaceAdviceOutput
    public var source: String
    public var record: StageRecord
    public var id: String { candidate.id }
}
public struct RecommendationRunV1: Codable, Identifiable, Sendable {
    public var schemaVersion = 1
    public var id = UUID().uuidString
    public var createdAt = Date().ISO8601Format()
    public var promptVersion = "recommendations-v1"
    public var brief: RecommendationBriefV1
    public var runtime: ModelRuntime
    public var profile: PreferenceExtraction
    public var search: SearchBatch
    public var advice: [PlaceAdviceV1]
    public var explanation: DiscoveryExplanation
    public var records: [StageRecord]
    public var selectedIDs: [String]
    public var elapsedSeconds: Double
    public var inputSubmissions = 1
    public var correctionRounds = 0
    public var routingPerformed = false
    public var markdown: String {
        """
        # Foundation Lab · place and visit-time recommendations
        Run: \(id), created \(createdAt), prompt \(promptVersion).
        Service date: \(brief.date), Jakarta/WIB. Source model: \(runtime.model).
        No route, ETA, timetable, new finish time or travel feasibility was calculated.
        \(explanation.summary)

        \(advice.map { "- \($0.candidate.place.name): \($0.advice.window.rawValue) [\($0.advice.timeBasis.rawValue)] — \($0.advice.reason). Source: \($0.source)" }.joined(separator: "\n"))

        \(brief.notices.joined(separator: "\n"))
        Submitted inputs: \(inputSubmissions), correction rounds: \(correctionRounds).
        These are session counters, not measured user benefit. Model factual prose still requires human review.
        """
    }
}
