import Foundation
import PlaceContextEngine

public enum PersonalInterest: String, Codable, CaseIterable, Sendable, Identifiable {
    case coffee, reading, food, outdoors, culture, shopping, entertainment, architecture, arts
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .coffee: "Kopi"; case .reading: "Membaca"; case .food: "Kuliner"
        case .outdoors: "Alam dan outdoor"; case .culture: "Budaya dan sejarah"
        case .shopping: "Belanja"; case .entertainment: "Hiburan"
        case .architecture: "Arsitektur"; case .arts: "Seni dan kreativitas"
        }
    }
    public var searchTerm: String {
        switch self {
        case .coffee: "kedai kopi"; case .reading: "perpustakaan toko buku"; case .food: "restoran makanan"
        case .outdoors: "taman"; case .culture: "museum sejarah"; case .shopping: "pusat belanja"
        case .entertainment: "hiburan tempat wisata"; case .architecture: "bangunan bersejarah"
        case .arts: "galeri seni"
        }
    }
}
public enum PersonalPace: String, Codable, CaseIterable, Sendable {
    case relaxed, balanced, packed
    public var label: String { self == .relaxed ? "Santai" : self == .balanced ? "Seimbang" : "Padat" }
}
public struct PersonalProfile: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var revision = 1
    public var interests: [PersonalInterest] = []
    public var pace: PersonalPace = .balanced
    /// Keys are '<explicit interest>:<provider type>'. No cross-interest learned weight.
    public var facetAffinity: [String: Double] = [:]
    public init() {}
    public func validate() throws {
        guard schemaVersion == 1, revision > 0, revision < 1_000_000,
              interests.count <= 9, Set(interests).count == interests.count, facetAffinity.count <= 100,
              facetAffinity.allSatisfy({ key, value in
                  let parts = key.split(separator: ":")
                  return parts.count == 2 && interests.contains(where: { $0.rawValue == String(parts[0]) })
                      && key.utf8.count <= 100 && value.isFinite && (-1 ... 1).contains(value)
              }) else { throw ContextError.invalid("Profil atau pembelajaran di luar minat eksplisit tidak valid") }
    }
}
public struct PersonalTripContext: Codable, Sendable, Equatable {
    public var area: String
    public var day: String
    public var departureMinute: Int
    public var deadlineMinute: Int
    public init(area: String, day: String, departureMinute: Int = 540, deadlineMinute: Int = 1140) {
        self.area = area; self.day = day; self.departureMinute = departureMinute; self.deadlineMinute = deadlineMinute
    }
    public func validate(now: Date = .now) throws {
        guard !area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, area.count <= 100,
              let date = ContextClock.day(day), date >= ContextClock.calendar.startOfDay(for: now),
              date.timeIntervalSince(now) < 31 * 86400,
              (0 ... 1439).contains(departureMinute), (1 ... 1440).contains(deadlineMinute), departureMinute < deadlineMinute,
              date.addingTimeInterval(Double(departureMinute * 60)) >= now else {
            throw ContextError.invalid("Pilih area dan perjalanan satu hari mendatang, maksimal 30 hari")
        }
    }
}
public struct RecommendationStart: Codable, Sendable {
    public var profile: PersonalProfile
    public var context: PersonalTripContext
    public var continuationID: UUID?
    public init(profile: PersonalProfile, context: PersonalTripContext, continuationID: UUID? = nil) {
        self.profile = profile; self.context = context; self.continuationID = continuationID
    }
}
public struct CandidateEvidence: Codable, Sendable {
    public var id: String
    public var kind: String
    public var text: String
    public var source: String
    public var checkedAt: Date
    public init(id: String, kind: String, text: String, source: String, checkedAt: Date) {
        self.id = id; self.kind = kind; self.text = text; self.source = source; self.checkedAt = checkedAt
    }
}
public struct PersonalCandidate: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var address: String
    public var categories: [PersonalInterest]
    public var facetKeys: [String]
    public var description: String
    public var hoursState: String
    public var hours: [OperatingInterval]
    public var evidence: [CandidateEvidence]
    public var unknowns: [String]
    public var googleMapsURL: String?
    public var exposure: ActivityExposure
    /// Use automatic exposure when the activity has unambiguous provider types or place-specific evidence.
    public var suggestedOutdoorActivity: Bool {
        exposure == .outdoor && facetKeys.contains { ["outdoors:park", "outdoors:national_park",
                                                      "outdoors:garden", "outdoors:botanical_garden", "outdoors:coastal_walk"].contains($0) }
    }
    public init(id: String, name: String, address: String, categories: [PersonalInterest], facetKeys: [String], description: String,
                hoursState: String, hours: [OperatingInterval], evidence: [CandidateEvidence], unknowns: [String], googleMapsURL: String?, exposure: ActivityExposure) {
        self.id = id; self.name = name; self.address = address; self.categories = categories; self.facetKeys = facetKeys
        self.description = description; self.hoursState = hoursState; self.hours = hours; self.evidence = evidence
        self.unknowns = unknowns; self.googleMapsURL = googleMapsURL; self.exposure = exposure
    }
}
public struct PreparedRecommendation: Codable, Sendable {
    public var id: UUID
    public var profileRevision: Int
    public var context: PersonalTripContext
    public var expiresAt: Date
    public var candidates: [PersonalCandidate]
    public var acquisitionSeconds: Double
    public var weatherSummary: String
    public var hasMore: Bool?
    public var warnings: [String]
    public init(id: UUID, profileRevision: Int, context: PersonalTripContext, expiresAt: Date, candidates: [PersonalCandidate],
                acquisitionSeconds: Double, weatherSummary: String, warnings: [String], hasMore: Bool? = nil) {
        self.id = id; self.profileRevision = profileRevision; self.context = context; self.expiresAt = expiresAt
        self.candidates = candidates; self.acquisitionSeconds = acquisitionSeconds; self.weatherSummary = weatherSummary; self.warnings = warnings; self.hasMore = hasMore
    }
}
public struct LocalCandidateScore: Codable, Sendable {
    public var id: String
    public var semanticScore: Double?
    public init(id: String, semanticScore: Double?) { self.id = id; self.semanticScore = semanticScore }
}
public struct RecommendationComplete: Codable, Sendable {
    public var id: UUID
    public var profileRevision: Int
    public var scores: [LocalCandidateScore]
    public var embeddingStatus: String
    public var embeddingSeconds: Double
    public init(id: UUID, profileRevision: Int, scores: [LocalCandidateScore], embeddingStatus: String, embeddingSeconds: Double) {
        self.id = id; self.profileRevision = profileRevision; self.scores = scores
        self.embeddingStatus = embeddingStatus; self.embeddingSeconds = embeddingSeconds
    }
}
public struct LLMPlaceChoice: Codable, Sendable {
    public var id: String
    public var reasonCodes: [String]
    public var evidenceIDs: [String]
    public init(id: String, reasonCodes: [String], evidenceIDs: [String]) { self.id = id; self.reasonCodes = reasonCodes; self.evidenceIDs = evidenceIDs }
}
public struct LLMRecommendation: Codable, Sendable {
    public var items: [LLMPlaceChoice]
    public init(items: [LLMPlaceChoice]) { self.items = items }
}
public struct PersonalRecommendedPlace: Codable, Sendable, Identifiable {
    public var candidate: PersonalCandidate
    public var reasons: [String]
    public var llmRank: Int
    public var id: String { candidate.id }
    public init(candidate: PersonalCandidate, reasons: [String], llmRank: Int) { self.candidate = candidate; self.reasons = reasons; self.llmRank = llmRank }
}
public struct RecommendationMetrics: Codable, Sendable {
    public var acquisitionSeconds: Double
    public var embeddingSeconds: Double
    public var llmSeconds: Double
    public var serverElapsedSeconds: Double
    public var llmModel: String
    public var llmProvider: String
    public var promptTokens: Int
    public var completionTokens: Int
    public var costUSD: Double
    public var embeddingStatus: String
    public init(acquisitionSeconds: Double, embeddingSeconds: Double, llmSeconds: Double, serverElapsedSeconds: Double,
                llmModel: String, llmProvider: String, promptTokens: Int, completionTokens: Int, costUSD: Double, embeddingStatus: String) {
        self.acquisitionSeconds = acquisitionSeconds; self.embeddingSeconds = embeddingSeconds; self.llmSeconds = llmSeconds
        self.serverElapsedSeconds = serverElapsedSeconds; self.llmModel = llmModel; self.llmProvider = llmProvider
        self.promptTokens = promptTokens; self.completionTokens = completionTokens; self.costUSD = costUSD; self.embeddingStatus = embeddingStatus
    }
}
public struct PersonalRecommendationResult: Codable, Sendable {
    public var id: UUID
    public var profileRevision: Int
    public var context: PersonalTripContext
    public var validUntil: Date
    public var places: [PersonalRecommendedPlace]
    public var metrics: RecommendationMetrics
    public var warnings: [String]
    public var judgments: [LLMPlaceChoice]
    public var hasMore: Bool?
    public init(id: UUID, profileRevision: Int, context: PersonalTripContext, validUntil: Date, places: [PersonalRecommendedPlace], metrics: RecommendationMetrics, warnings: [String], judgments: [LLMPlaceChoice] = [], hasMore: Bool? = nil) {
        self.id = id; self.profileRevision = profileRevision; self.context = context; self.validUntil = validUntil; self.places = places; self.metrics = metrics; self.warnings = warnings; self.judgments = judgments; self.hasMore = hasMore
    }
}
public enum PersonalEventKind: String, Codable, Sendable { case shown, opened, saved, selected, skipped, removed }
public struct PersonalInteraction: Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var recommendationID: UUID
    public var candidateID: String
    public var kind: PersonalEventKind
    public var context: PersonalTripContext
    public var categories: [PersonalInterest]
    public var facetKeys: [String]
    public init(recommendationID: UUID, candidate: PersonalCandidate, kind: PersonalEventKind, context: PersonalTripContext, date: Date = .now) {
        id = UUID(); self.date = date; self.recommendationID = recommendationID; candidateID = candidate.id
        self.kind = kind; self.context = context; categories = candidate.categories; facetKeys = candidate.facetKeys
    }
}
public struct PersonalLearningState: Codable, Sendable {
    public var profile = PersonalProfile()
    public var events: [PersonalInteraction] = []
    public init() {}
    public mutating func record(_ event: PersonalInteraction) {
        guard !events.contains(where: {$0.id == event.id}) else { return }
        events.append(event); events = Array(events.suffix(500))
        // Only positive intentional actions tune a sourced facet; a skip can be caused by time/distance.
        let delta: Double = event.kind == .opened ? 0.02 : event.kind == .saved ? 0.12 : event.kind == .selected ? 0.18 : 0
        guard delta > 0 else { return }
        var changed = false
        for key in Set(event.facetKeys) {
            let parts = key.split(separator: ":")
            guard parts.count == 2, profile.interests.contains(where: {$0.rawValue == String(parts[0])}),
                  event.categories.contains(where: {$0.rawValue == String(parts[0])}), key.count <= 100 else { continue }
            profile.facetAffinity[key] = min(1, (profile.facetAffinity[key] ?? 0) + delta); changed = true
        }
        if profile.facetAffinity.count > 100 { profile.facetAffinity = Dictionary(uniqueKeysWithValues: profile.facetAffinity.sorted{$0.key < $1.key}.prefix(100).map{($0.key, $0.value)}) }
        if changed { profile.revision += 1 }
    }
    public mutating func setExplicit(interests: [PersonalInterest], pace: PersonalPace) {
        let new = PersonalInterest.allCases.filter{interests.contains($0)}
        guard new != profile.interests || pace != profile.pace else { return }
        profile.interests = new; profile.pace = pace; profile.revision += 1
        profile.facetAffinity = profile.facetAffinity.filter{key, _ in new.contains{key.hasPrefix($0.rawValue + ":")}}
    }
}
