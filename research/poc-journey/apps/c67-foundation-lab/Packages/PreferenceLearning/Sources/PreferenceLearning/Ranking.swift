import Foundation

public protocol PreferenceEmbedding: Sendable {
    func metadata() async throws -> EmbeddingMetadata
    func encode(_ text: String, query: Bool) async throws -> [Float]
}
public struct PreferenceRanker: Sendable {
    public let embedding: any PreferenceEmbedding
    public init(embedding: any PreferenceEmbedding) { self.embedding = embedding }
    public static func cosine(_ a: [Float], _ b: [Float]) throws -> Double {
        guard !a.isEmpty, a.count == b.count, a.allSatisfy(\.isFinite), b.allSatisfy(\.isFinite) else {
            throw PreferenceError.invalid("Vektor tidak valid.")
        }
        let normA = sqrt(a.reduce(0.0) { $0 + Double($1) * Double($1) })
        let normB = sqrt(b.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard normA > 0, normB > 0 else { throw PreferenceError.invalid("Vektor kosong.") }
        return min(
            1, max(-1, zip(a, b).reduce(0.0) { $0 + Double($1.0) * Double($1.1) } / (normA * normB)))
    }
    public func compare(
        profile: LocalPreferenceProfile, catalog: PreferenceCatalog, useEmbedding: Bool = true,
        progress: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> PreferenceComparisonRun {
        try catalog.validate()
        try profile.validate(catalog: catalog)
        try Task.checkCancellation()
        let began = Date()
        let weights = profile.learnedWeights(catalog: catalog)
        let eligible = catalog.places.filter {
            profile.feedback[$0.id] == nil && Set($0.tags).isDisjoint(with: profile.avoids)
        }
        func sort(_ rows: [RankedPreferencePlace]) -> [RankedPreferencePlace] {
            rows.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        }
        let baseline = sort(
            eligible.map { place in
                RankedPreferencePlace(
                    place: place, score: Set(place.tags).reduce(0) { $0 + (weights[$1] ?? 0) },
                    matchingTags: place.tags.filter { (weights[$0] ?? 0) > 0 })
            })
        var run = PreferenceComparisonRun(
            catalog: catalog, profile: profile, query: profile.query(catalog: catalog),
            categoryRanking: baseline, semanticRanking: [], embedding: nil,
            status: "category_fallback", error: "", elapsedSeconds: 0)
        guard profile.hasSignal else {
            run.status = "general_not_personalized"
            run.elapsedSeconds = Date().timeIntervalSince(began)
            return run
        }
        guard useEmbedding, !eligible.isEmpty else {
            run.status = eligible.isEmpty ? "no_eligible_places" : "category_only"
            run.elapsedSeconds = Date().timeIntervalSince(began)
            return run
        }
        do {
            await progress("Memuat model lokal")
            run.embedding = try await embedding.metadata()
            let query = try await embedding.encode(run.query, query: true)
            var values: [RankedPreferencePlace] = []
            for (index, row) in baseline.enumerated() {
                try Task.checkCancellation()
                await progress("Mencocokkan tempat \(index + 1)/\(baseline.count)")
                let vector = try await embedding.encode(row.place.description, query: false)
                values.append(
                    .init(
                        place: row.place, score: try Self.cosine(query, vector), matchingTags: row.matchingTags)
                )
            }
            try Task.checkCancellation()
            run.semanticRanking = sort(values)
            run.status = "semantic_completed"
        } catch is CancellationError { throw CancellationError() } catch {
            run.error = String(describing: error)
            run.semanticRanking = []
            run.status = "category_fallback"
        }
        run.elapsedSeconds = Date().timeIntervalSince(began)
        return run
    }
}
public actor PreferenceStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func encode<T: Encodable>(_ value: T, at url: URL) throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    public func save(_ profile: LocalPreferenceProfile, catalogID: String) throws {
        guard ["synthetic-v1", "mapkit-snapshot-v1", "mapkit-live-v1"].contains(catalogID) else {
            throw PreferenceError.invalid("Katalog penyimpanan tidak dikenal.")
        }
        try encode(profile, at: directory.appendingPathComponent("profile-" + catalogID + ".json"))
    }
    public func profile(catalogID: String) throws -> LocalPreferenceProfile {
        guard ["synthetic-v1", "mapkit-snapshot-v1", "mapkit-live-v1"].contains(catalogID) else {
            throw PreferenceError.invalid("Katalog penyimpanan tidak dikenal.")
        }
        let url = directory.appendingPathComponent("profile-" + catalogID + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        return try JSONDecoder().decode(LocalPreferenceProfile.self, from: Data(contentsOf: url))
    }
    public func save(_ run: PreferenceComparisonRun) throws {
        try encode(run, at: directory.appendingPathComponent("run-" + run.id + ".json"))
    }
    public func runs() throws -> [PreferenceComparisonRun] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        // Preserve malformed files for diagnosis and recover valid runs instead of losing the whole history.
        return try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("run-") && $0.pathExtension == "json" }
        .compactMap {
            try? JSONDecoder().decode(PreferenceComparisonRun.self, from: Data(contentsOf: $0))
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}
