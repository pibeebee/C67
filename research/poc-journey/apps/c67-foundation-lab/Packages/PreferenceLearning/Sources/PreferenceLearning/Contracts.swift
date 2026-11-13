import Foundation

public enum PreferenceTag: String, Codable, CaseIterable, Identifiable, Sendable {
    case coffee, reading, nature, culture, food, art, shopping, photography, quiet, lively, indoor,
         outdoor, entertainment
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .coffee: "Kopi"
        case .reading: "Membaca"
        case .nature: "Alam"
        case .culture: "Budaya"
        case .food: "Kuliner"
        case .art: "Seni"
        case .shopping: "Belanja"
        case .photography: "Fotografi"
        case .quiet: "Tenang"
        case .lively: "Ramai / hidup"
        case .indoor: "Indoor"
        case .outdoor: "Outdoor"
        case .entertainment: "Hiburan"
        }
    }
}
public struct PreferencePlace: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var tags: [PreferenceTag]
    public var latitude: Double
    public var longitude: Double
    public var source: String
    public var observedAt: String
    public var synthetic: Bool
    public var unknowns: [String]
    public var address: String? = nil
    public var category: String? = nil
}
public struct PreferenceCatalog: Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var provenance: String
    public var places: [PreferencePlace]
    public static func load(_ name: String = "synthetic-v1") throws -> Self {
        if name == "mapkit-live-v1" { return .liveEmpty }
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw PreferenceError.invalid("Katalog tidak ditemukan.")
        }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }
    public static var liveEmpty: Self {
        .init(
            id: "mapkit-live-v1", title: "MapKit langsung · Jakarta",
            provenance:
            "Live MKLocalSearch results; fetched only when requested. Identity/category and coordinates only; amenities and visiting times remain unknown.",
            places: [])
    }
    public func validate() throws {
        guard !id.isEmpty, !places.isEmpty || id == "mapkit-live-v1", places.count <= 30,
              Set(places.map(\.id)).count == places.count,
              places.allSatisfy({
                  !$0.id.isEmpty && !$0.description.isEmpty && !$0.source.isEmpty && $0.latitude.isFinite
                      && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180
              })
        else { throw PreferenceError.invalid("Katalog tidak valid.") }
    }
}
public enum PlaceFeedback: String, Codable, Sendable { case liked, disliked }
public struct LocalPreferenceProfile: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var interests: Set<PreferenceTag> = []
    public var avoids: Set<PreferenceTag> = []
    public var text = ""
    public var feedback: [String: PlaceFeedback] = [:]
    // Optional to decode existing v0.3 profiles. Keep source-bearing liked/disliked identities
    // across changing live result sets; do not make missing candidates erase preferences.
    public var rememberedPlaces: [PreferencePlace]? = nil
    public init() {}
    public func validate(catalog: PreferenceCatalog) throws {
        guard schemaVersion == 1, text.count <= 400,
              interests.isDisjoint(with: avoids),
              (rememberedPlaces?.count ?? 0) <= 100,
              Set((rememberedPlaces ?? []).map(\.id)).count == (rememberedPlaces?.count ?? 0),
              (rememberedPlaces ?? []).allSatisfy({
                  !$0.id.isEmpty && !$0.source.isEmpty && !$0.description.isEmpty && $0.latitude.isFinite
                      && $0.longitude.isFinite
              }),
              Set(feedback.keys).isSubset(of: Set(knownPlaces(catalog: catalog).map(\.id))),
              feedback.values.filter({ $0 == .liked }).count <= 6
        else {
            throw PreferenceError.invalid(
                "Periksa preferensi, maksimal 400 karakter dan enam tempat disukai.")
        }
    }
    public var hasSignal: Bool {
        !interests.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || feedback.values.contains(.liked)
    }
    public var textNeedsAvoidControls: Bool {
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        return !words.isDisjoint(with: [
            "tidak", "jangan", "tanpa", "bukan", "hindari", "not", "no", "avoid", "without",
        ])
    }
    public func learnedWeights(catalog: PreferenceCatalog) -> [PreferenceTag: Double] {
        let liked = knownPlaces(catalog: catalog).filter { feedback[$0.id] == .liked }
        var result = Dictionary(uniqueKeysWithValues: interests.map { ($0, 2.0) })
        for place in liked {
            for tag in Set(place.tags) where !avoids.contains(tag) {
                result[tag, default: 0] += 1.0 / Double(max(liked.count, 1))
            }
        }
        for tag in avoids { result.removeValue(forKey: tag) }
        return result
    }
    public func query(catalog: PreferenceCatalog) -> String {
        var parts: [String] = []
        if !interests.isEmpty {
            parts.append(
                "Activities I enjoy: " + interests.map(\.rawValue).sorted().joined(separator: ", "))
        }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(text) }
        for place in knownPlaces(catalog: catalog).filter({ feedback[$0.id] == .liked }).sorted(by: {
            $0.id < $1.id
        }) {
            parts.append("A place I like: " + place.description)
        }
        // Avoids are enforced by native filtering, never by assuming embedding understands negation.
        return parts.joined(separator: ". ")
    }
    public func knownPlaces(catalog: PreferenceCatalog) -> [PreferencePlace] {
        var seen = Set<String>()
        return ((rememberedPlaces ?? []) + catalog.places).filter { seen.insert($0.id).inserted }
    }
    public mutating func setFeedback(
        _ value: PlaceFeedback?, for place: PreferencePlace, remember: Bool
    ) {
        feedback[place.id] = value
        if remember {
            var saved = rememberedPlaces ?? []
            saved.removeAll { $0.id == place.id || feedback[$0.id] == nil }
            if value != nil { saved.append(place) }
            rememberedPlaces = saved
        }
    }
}
public struct RankedPreferencePlace: Codable, Identifiable, Sendable {
    public var place: PreferencePlace
    public var score: Double
    public var matchingTags: [PreferenceTag]
    public var id: String { place.id }
}
public struct EmbeddingMetadata: Codable, Sendable {
    public var model: String
    public var revision: String
    public var artifactSHA256: String
    public var runtime: String
    public var dimensions: Int
}
public struct PreferenceComparisonRun: Codable, Identifiable, Sendable {
    public var schemaVersion = 1
    public var id = UUID().uuidString
    public var createdAt = Date().ISO8601Format()
    public var catalog: PreferenceCatalog
    public var profile: LocalPreferenceProfile
    public var query: String
    public var categoryRanking: [RankedPreferencePlace]
    public var semanticRanking: [RankedPreferencePlace]
    public var embedding: EmbeddingMetadata?
    public var status: String
    public var error: String
    public var elapsedSeconds: Double
    public var os = ProcessInfo.processInfo.operatingSystemVersionString
    public var routingPerformed = false
    public var search: PreferenceSearchRecord? = nil
    public var markdown: String {
        """
        # Preference Lab — local ranking comparison
        Run \(id), \(createdAt). Catalog: \(catalog.title).
        Source: \(catalog.provenance)
        Search: \(search?.choices.map(\.query).joined(separator: "; ") ?? "stored catalog; no live search").
        Search errors: \(search?.errors.joined(separator: "; ") ?? "none").
        Status: \(status). Duration: \(elapsedSeconds) s. Error: \(error).
        Model: \(embedding?.model ?? "not used"), \(embedding?.revision ?? "n/a").
        Category top three: \(categoryRanking.prefix(3).map { $0.place.name }.joined(separator: ", ")).
        Semantic top three: \(semanticRanking.prefix(3).map { $0.place.name }.joined(separator: ", ")).
        Similarity is a relative ranking score, not a probability of personal fit.
        Explicit dislikes/excluded tags filter candidates; the model generates no IDs, facts, times or routes.
        This run is not evidence of user benefit or real venue quality.
        """
    }
}
public enum PreferenceError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let value) = self { value } else { nil } }
}
