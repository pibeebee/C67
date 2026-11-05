import CryptoKit
import Foundation
import MapKit
import TripIntelligence

public struct PreferenceSearchChoice: Codable, Sendable {
    public var activity: PreferenceTag
    public var query: String
    public var basis: String
    public var score: Double?
}
public struct PreferenceSearchRecord: Codable, Sendable {
    public var provider: String
    public var fetchedAt: String
    public var choices: [PreferenceSearchChoice]
    public var errors: [String]
    public var notices: [String]
    public var receivedCount: Int
    public var filteredCount: Int
    public var searchSeconds: Double
    public var rankingSeconds: Double
    public var unmatchedActivityCount: Int? = nil
}
public struct PreferenceQueryPlan: Sendable {
    public var choices: [PreferenceSearchChoice]
    public var notices: [String]
}
public enum PreferenceQueryPlanner {
    public static let activities: [PreferenceTag] = [
        .coffee, .reading, .nature, .culture, .food, .art, .shopping, .photography, .entertainment,
    ]
    public static func query(_ tag: PreferenceTag) -> String {
        let names: [PreferenceTag: String] = [
            .coffee: "coffee shop", .reading: "bookstore", .nature: "park", .culture: "museum",
            .food: "restaurant", .art: "art gallery", .shopping: "shopping mall",
            .photography: "landmark", .entertainment: "cinema",
        ]
        return (names[tag] ?? "museum") + ", Jakarta"
    }
    private static let keywords: [PreferenceTag: Set<String>] = [
        .coffee: ["kopi", "ngopi", "coffee", "cafe", "kafe", "espresso"],
        .reading: [
            "buku", "membaca", "baca", "perpustakaan", "reading", "read", "book", "books", "bookstore",
            "library",
        ],
        .nature: ["alam", "taman", "nature", "park", "garden", "hiking"],
        .culture: ["budaya", "sejarah", "museum", "culture", "history", "heritage"],
        .food: ["kuliner", "makan", "restoran", "food", "restaurant", "dining"],
        .art: ["seni", "lukisan", "galeri", "art", "paintings", "painting", "gallery"],
        .shopping: ["belanja", "mall", "shopping", "fashion"],
        .photography: ["foto", "fotografi", "photography", "photo", "architecture", "arsitektur"],
        .entertainment: ["hiburan", "bioskop", "cinema", "entertainment", "movie"],
    ]
    public static func plan(
        profile: LocalPreferenceProfile, embedding: any PreferenceEmbedding, useSemantic: Bool = true
    ) async throws -> PreferenceQueryPlan {
        let context = PreferenceCatalog.liveEmpty
        try profile.validate(catalog: context)
        let learned = profile.learnedWeights(catalog: context)
        var priorities: [PreferenceTag: Double] = [:]
        var basis: [PreferenceTag: String] = [:]
        for tag in activities where !profile.avoids.contains(tag) {
            if profile.interests.contains(tag) {
                priorities[tag] = 100
                basis[tag] = "explicit interest"
            } else if let weight = learned[tag], weight > 0 {
                priorities[tag] = 50 + weight
                basis[tag] = "attributes of previously liked MapKit places"
            }
        }
        var notices = [
            "Category/name matching is a broad interpretation, not evidence of quietness, seating, price, crowds or opening hours."
        ]
        let text = profile.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if profile.textNeedsAvoidControls {
            notices.append(
                "Text with possible negation is not used to generate search categories. Use explicit interests and avoids; semantic ranking still does not reliably enforce text negation."
            )
        } else if !text.isEmpty {
            let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
            let matched = activities.filter {
                !profile.avoids.contains($0) && !words.isDisjoint(with: keywords[$0] ?? [])
            }
            for tag in matched where priorities[tag] == nil {
                priorities[tag] = 75
                basis[tag] = "recognized activity words in current text"
            }
            // With no identifiable activity use E5 only to choose a bounded search intent, not to invent a venue.
            if matched.isEmpty && priorities.isEmpty && useSemantic {
                do {
                    let vector = try await embedding.encode(text, query: true)
                    var ranked: [(PreferenceTag, Double)] = []
                    for tag in activities where !profile.avoids.contains(tag) {
                        try Task.checkCancellation()
                        let prototype =
                            "A day-trip activity focused on " + tag.rawValue + ". Search for " + query(tag)
                        let other = try await embedding.encode(prototype, query: false)
                        ranked.append((tag, try PreferenceRanker.cosine(vector, other)))
                    }
                    for (tag, score) in ranked.sorted(by: {
                        $0.1 == $1.1 ? $0.0.rawValue < $1.0.rawValue : $0.1 > $1.1
                    }).prefix(3) {
                        priorities[tag] = score
                        basis[tag] = "E5 semantic search intent; not a verified preference"
                    }
                } catch is CancellationError { throw CancellationError() } catch {
                    notices.append(
                        "Semantic query planning unavailable; broad category search used: \(error)")
                }
            }
        }
        if priorities.isEmpty {
            for tag in [PreferenceTag.culture, .nature, .coffee] where !profile.avoids.contains(tag) {
                priorities[tag] = -1
                basis[tag] = "general Jakarta discovery; no inferred personal activity"
            }
            notices.append(
                "Broad discovery is not a personalized search when no supported activity signal is available."
            )
        }
        let ordered = priorities.keys.sorted {
            priorities[$0] == priorities[$1]
                ? $0.rawValue < $1.rawValue : priorities[$0]! > priorities[$1]!
        }
        return .init(
            choices: ordered.prefix(3).map { tag in
                .init(
                    activity: tag, query: query(tag), basis: basis[tag]!,
                    score: priorities[tag]! < 1 && priorities[tag]! > -1 ? priorities[tag] : nil)
            }, notices: notices)
    }
}

public protocol PreferencePlaceSearching: Sendable {
    var provider: String { get }
    func lookup(_ query: String) async throws -> [PreferencePlace]
}
public struct MapKitPreferenceSearch: PreferencePlaceSearching {
    public let provider = "MapKit MKLocalSearch live"
    public init() {}
    @MainActor public func lookup(_ query: String) async throws -> [PreferencePlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: .init(latitude: -6.2, longitude: 106.83), latitudinalMeters: 35_000,
            longitudinalMeters: 35_000)
        let search = MKLocalSearch(request: request)
        let response = try await withTaskCancellationHandler {
            try await search.start()
        } onCancel: {
            search.cancel()
        }
        try Task.checkCancellation()
        let at = Date().ISO8601Format()
        return response.mapItems.compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            let coordinate = item.location.coordinate
            let category = item.pointOfInterestCategory?.rawValue ?? "unknown"
            let raw = "\(name.lowercased())|\(coordinate.latitude)|\(coordinate.longitude)"
            let hash = SHA256.hash(data: Data(raw.utf8)).prefix(12).map { String(format: "%02x", $0) }
                .joined()
            let id = item.identifier?.rawValue ?? "mk-coordinate-" + hash
            let tags = PreferenceLiveFilter.tags(name: name, category: category)
            let description =
                "\(name). MapKit category: \(category). Broad category/name activity matches: \(tags.map(\.rawValue).sorted().joined(separator: ", ")). No further venue attributes were supplied."
            return PreferencePlace(
                id: id, name: name, description: description, tags: tags,
                latitude: coordinate.latitude, longitude: coordinate.longitude,
                source:
                "MapKit MKLocalSearch identity/category/coordinate; native broad category/name interpretation only",
                observedAt: at, synthetic: false,
                unknowns: [
                    "opening hours", "reading seats", "quietness", "crowds", "price", "accessibility",
                    "travel feasibility",
                ], address: item.address?.fullAddress, category: category)
        }
    }
}
public enum PreferenceLiveFilter {
    public static func tags(name: String, category: String) -> [PreferenceTag] {
        let name = name.lowercased()
        let category = category.lowercased().replacingOccurrences(of: "mkpoicategory", with: "")
        var tags = Set<PreferenceTag>()
        if category == "cafe" { tags.formUnion([.coffee, .food]) }
        if ["restaurant", "bakery", "foodmarket"].contains(category) { tags.insert(.food) }
        if category == "library"
            || ["bookstore", "book store", "toko buku"].contains(where: name.contains)
        {
            tags.insert(.reading)
        }
        if ["park", "nationalpark", "beach"].contains(category) { tags.insert(.nature) }
        if category == "museum" { tags.insert(.culture) }
        if category == "artgallery" || category == "gallery" { tags.formUnion([.art, .culture]) }
        if ["landmark", "nationalmonument"].contains(category) {
            tags.formUnion([.culture, .photography])
        }
        if ["store", "shoppingcenter"].contains(category) { tags.insert(.shopping) }
        if ["movietheater", "theater", "amusementpark"].contains(category) {
            tags.insert(.entertainment)
        }
        return tags.sorted { $0.rawValue < $1.rawValue }
    }
    public static func clean(_ input: [PreferencePlace], limit: Int = 20) -> [PreferencePlace] {
        var ids = Set<String>()
        var kept: [PreferencePlace] = []
        for place in input {
            guard !place.id.isEmpty, !place.name.isEmpty, !place.synthetic,
                  !place.description.isEmpty, !place.source.isEmpty,
                  JakartaBoundary.contains(latitude: place.latitude, longitude: place.longitude),
                  ids.insert(place.id).inserted
            else { continue }
            let duplicate = kept.contains { old in
                let a = old.name.lowercased().filter { $0.isLetter || $0.isNumber }
                let b = place.name.lowercased().filter { $0.isLetter || $0.isNumber }
                let dx = (old.longitude - place.longitude) * cos(place.latitude * .pi / 180)
                let dy = old.latitude - place.latitude
                return a == b && sqrt(dx * dx + dy * dy) * 111_000 < 50
            }
            if !duplicate { kept.append(place) }
            if kept.count >= limit { break }
        }
        return kept
    }
}
public struct PreferenceDiscoveryPipeline: Sendable {
    public let embedding: any PreferenceEmbedding
    public let search: any PreferencePlaceSearching
    public let timeout: Double
    public init(
        embedding: any PreferenceEmbedding,
        search: any PreferencePlaceSearching = MapKitPreferenceSearch(), timeout: Double = 20
    ) {
        self.embedding = embedding
        self.search = search
        self.timeout = timeout
    }
    public func run(
        profile: LocalPreferenceProfile, useEmbedding: Bool = true,
        progress: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> PreferenceComparisonRun {
        let began = Date()
        await progress("Memahami profil untuk pencarian")
        let plan = try await PreferenceQueryPlanner.plan(
            profile: profile, embedding: embedding, useSemantic: useEmbedding)
        var batches: [[PreferencePlace]] = []
        var errors: [String] = []
        for (index, choice) in plan.choices.enumerated() {
            try Task.checkCancellation()
            await progress("Mencari MapKit \(index + 1)/\(plan.choices.count) · \(choice.activity.title)")
            do {
                let values = try await AsyncDeadline.run(seconds: timeout) {
                    try await search.lookup(choice.query)
                }
                batches.append(values)
            } catch is CancellationError { throw CancellationError() } catch {
                errors.append("\(choice.query): \(error)")
            }
        }
        try Task.checkCancellation()
        var interleaved: [PreferencePlace] = []
        for i in 0 ..< (batches.map(\.count).max() ?? 0) {
            for batch in batches where batch.indices.contains(i) { interleaved.append(batch[i]) }
        }
        let cleaned = PreferenceLiveFilter.clean(interleaved, limit: 30)
        let requested = Set(plan.choices.map(\.activity))
        let matching = cleaned.filter { !Set($0.tags).isDisjoint(with: requested) }
        let values = Array(matching.prefix(20))
        var catalog = PreferenceCatalog.liveEmpty
        catalog.places = values
        catalog.provenance =
            "\(search.provider); retrieved \(Date().ISO8601Format()); category-interleaved, deduplicated and checked against the frozen Jakarta geoBoundaries/OSM operational mask (2017, ODbL 1.0). No routing performed."
        let fetchedAt = Date().ISO8601Format()
        let searchSeconds = Date().timeIntervalSince(began)
        var run = try await PreferenceRanker(embedding: embedding).compare(
            profile: profile, catalog: catalog, useEmbedding: useEmbedding, progress: progress)
        let rankingSeconds = run.elapsedSeconds
        run.search = .init(
            provider: search.provider, fetchedAt: fetchedAt, choices: plan.choices, errors: errors,
            notices: plan.notices, receivedCount: interleaved.count, filteredCount: values.count,
            searchSeconds: searchSeconds, rankingSeconds: rankingSeconds)
        run.search?.unmatchedActivityCount = cleaned.count - matching.count
        if values.isEmpty { run.status = errors.isEmpty ? "search_empty" : "search_failed" }
        run.elapsedSeconds = Date().timeIntervalSince(began)
        try Task.checkCancellation()
        return run
    }
}
// Deterministic, explicitly labeled provider for UI/replay checks. No live search is implied.
public struct PreferenceReplaySearch: PreferencePlaceSearching {
    public let provider = "Injected replay of 5 Nov MapKit snapshot; no live request"
    public var delay: Double
    public init(delay: Double = 0.15) { self.delay = delay }
    public func lookup(_ query: String) async throws -> [PreferencePlace] {
        try await Task.sleep(for: .seconds(delay))
        return try PreferenceCatalog.load("mapkit-snapshot-v1").places
    }
}
