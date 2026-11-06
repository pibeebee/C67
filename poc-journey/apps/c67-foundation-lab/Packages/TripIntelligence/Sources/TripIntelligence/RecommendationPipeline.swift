import Foundation

public enum RecommendationValidation {
    public static func candidate(_ candidate: CandidateV1) throws {
        guard !candidate.id.isEmpty, !candidate.place.name.isEmpty,
              let latitude = candidate.place.latitude, let longitude = candidate.place.longitude,
              JakartaBoundary.contains(latitude: latitude, longitude: longitude),
              !candidate.evidence.isEmpty,
              Set(candidate.evidence.map(\.id)).count == candidate.evidence.count,
              candidate.evidence.allSatisfy({
                  !$0.id.isEmpty && $0.subjectID == candidate.id && !$0.source.isEmpty
                      && Codec.date($0.observedAt) != nil
              })
        else { throw LabError.invalid("Kandidat/sumber di luar kontrak Jakarta.") }
    }
    public static func advice(_ raw: String, candidate: CandidateV1) throws -> PlaceAdviceOutput {
        let data = Data(raw.utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            Set(object?.keys.map { $0 } ?? [])
            == Set([
                "suitability", "reason", "window", "timeBasis", "timeReason", "evidenceIDs", "unknowns",
            ])
        else {
            throw LabError.invalid("Field nasihat tempat tidak sesuai kontrak.")
        }
        let output = try JSONDecoder().decode(PlaceAdviceOutput.self, from: data)
        let facts = candidate.evidence.filter { output.evidenceIDs.contains($0.id) }
        guard !output.reason.isEmpty, !output.timeReason.isEmpty, !output.evidenceIDs.isEmpty,
              output.evidenceIDs.count <= 4, output.unknowns.count <= 5,
              Set(output.evidenceIDs).isSubset(of: Set(candidate.evidence.map(\.id)))
        else {
            throw LabError.invalid("Referensi nasihat tidak mendukung kandidat yang sedang diperiksa.")
        }
        if output.timeBasis == .unknown && ![VisitWindow.any, .unknown].contains(output.window) {
            throw LabError.invalid("Jendela spesifik tanpa dasar waktu.")
        }
        if output.timeBasis == .suppliedFacts
            && !facts.contains(where: {
                ["opensMinute", "closesMinute", "experienceWindow"].contains($0.key)
            })
        {
            throw LabError.invalid("Klaim waktu bersumber tidak mempunyai fakta waktu.")
        }
        let ranges: [VisitWindow: Range<Int>] = [
            .morning: 360 ..< 720, .midday: 720 ..< 900, .afternoon: 900 ..< 1080, .evening: 1080 ..< 1440,
        ]
        func minute(_ key: String) -> Int? {
            guard let fact = candidate.evidence.first(where: { $0.key == key }) else { return nil }
            let parts = fact.value.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
        }
        if let range = ranges[output.window] {
            guard
                max(range.lowerBound, minute("opensMinute") ?? 0)
                < min(range.upperBound, minute("closesMinute") ?? 1440)
            else {
                throw LabError.invalid("Saran waktu bertentangan dengan jam operasional yang diketahui.")
            }
        }
        return output
    }
    public static func explanation(_ raw: String, evidence: [EvidenceV1]) throws
        -> DiscoveryExplanation
    {
        let data = Data(raw.utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard Set(object?.keys.map { $0 } ?? []) == Set(["summary", "evidenceIDs", "unknowns"]) else {
            throw LabError.invalid("Field ringkasan tidak valid.")
        }
        let output = try JSONDecoder().decode(DiscoveryExplanation.self, from: data)
        guard !output.summary.isEmpty, output.evidenceIDs.count <= 6, output.unknowns.count <= 5,
              evidence.isEmpty || !output.evidenceIDs.isEmpty,
              Set(output.evidenceIDs).isSubset(of: Set(evidence.map(\.id)))
        else { throw LabError.invalid("Sumber ringkasan tidak dikenal.") }
        return output
    }
}
public enum RecommendationRelevance {
    public static func supportedActivities(_ candidate: CandidateV1) -> Set<Experience> {
        let category = candidate.place.category.lowercased()
        let name = candidate.place.name.lowercased()
        var result = Set<Experience>()
        if category.contains("cafe") { result.formUnion([.coffee, .food]) }
        if category.contains("restaurant") || category.contains("foodmarket")
            || category.contains("bakery")
        {
            result.insert(.food)
        }
        if category.contains("library") || name.contains("bookstore") || name.contains("book store")
            || name.contains("toko buku")
        {
            result.insert(.reading)
        }
        if category.contains("museum") { result.formUnion([.culture, .art]) }
        if category.contains("gallery") { result.formUnion([.culture, .art]) }
        let baseCategory = category.replacingOccurrences(of: "mkpoicategory", with: "")
        if ["park", "nationalpark", "beach"].contains(baseCategory) {
            result.formUnion([.nature, .photography])
        }
        if category.contains("theater") || category.contains("cinema") || category.contains("amusement")
        {
            result.insert(.entertainment)
        }
        if category.contains("store") || category.contains("shopping") { result.insert(.shopping) }
        if category.contains("landmark") || category.contains("monument") {
            result.formUnion([.culture, .photography])
        }
        // These are category/name matches only, never a claim about price, noise, hours or reading seats.
        return result
    }
}

public protocol RecommendationSearching: Sendable {
    func discover(_ brief: RecommendationBriefV1, profile: PreferenceExtraction) async throws
        -> SearchBatch
    func resolve(_ query: String) async throws -> [CandidateV1]
}
public struct RecommendationReplaySearch: RecommendationSearching {
    public let batch: SearchBatch
    public init(batch: SearchBatch) { self.batch = batch }
    public func discover(_ brief: RecommendationBriefV1, profile: PreferenceExtraction) async throws
        -> SearchBatch
    {
        var result = batch
        result.candidates = result.candidates.filter { !brief.excludedIDs.contains($0.id) }
        result.source = "Frozen replay of: " + batch.source
        return result
    }
    public func resolve(_ query: String) async throws -> [CandidateV1] {
        batch.candidates.filter { $0.place.name.localizedCaseInsensitiveContains(query) }
    }
}
public struct RecommendationMapSearch: RecommendationSearching {
    public init() {}
    public func resolve(_ query: String) async throws -> [CandidateV1] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 200 else {
            throw LabError.invalid("Masukkan nama tempat, maksimal 200 karakter.")
        }
        let values = try await AsyncDeadline.run(seconds: 20) {
            try await MapKitPlaceSearch.lookup(query + ", Jakarta")
        }
        return CandidateFilter.clean(values).prefix(5).map { $0 }
    }
    public func discover(_ brief: RecommendationBriefV1, profile: PreferenceExtraction) async throws
        -> SearchBatch
    {
        let explicit = brief.experiences.filter { !brief.avoids.contains($0) }.map(\.query)
        let extracted = CandidateFilter.queries(profile).map {
            $0.replacingOccurrences(of: ", Jakarta", with: "")
        }
        var seen = Set<String>()
        let values = (explicit + extracted).filter { seen.insert($0).inserted }
        let queries = Array((values.isEmpty ? ["museum", "park", "coffee shop"] : values).prefix(3)).map
            { $0 + ", Jakarta" }
        var batches: [[CandidateV1]] = []
        var errors: [String] = []
        for query in queries {
            try Task.checkCancellation()
            do {
                batches.append(
                    try await AsyncDeadline.run(seconds: 20) { try await MapKitPlaceSearch.lookup(query) })
            } catch is CancellationError { throw CancellationError() } catch {
                errors.append("\(query): \(error.localizedDescription)")
            }
        }
        // Interleave categories before the bound, so the first category does not consume the shortlist.
        var combined: [CandidateV1] = []
        for index in 0 ..< (batches.map(\.count).max() ?? 0) {
            for batch in batches where batch.indices.contains(index) { combined.append(batch[index]) }
        }
        return .init(
            candidates: CandidateFilter.clean(combined, excluding: Set(brief.excludedIDs)),
            queries: queries,
            errors: errors,
            source: "MapKit live search; category-interleaved candidates; no route calculated")
    }
}
public struct RecommendationFixtureSearch: RecommendationSearching {
    public init() {}
    public func resolve(_ query: String) async throws -> [CandidateV1] {
        RecommendationExamples.places().filter { $0.place.name.localizedCaseInsensitiveContains(query) }
    }
    public func discover(_ brief: RecommendationBriefV1, profile: PreferenceExtraction) async throws
        -> SearchBatch
    {
        .init(
            candidates: RecommendationExamples.places().filter { !brief.excludedIDs.contains($0.id) },
            queries: ["Synthetic candidate retrieval"], source: "Synthetic fixture search; not MapKit")
    }
}
public enum RecommendationExamples {
    public static func places() -> [CandidateV1] {
        let c = try! LabFixtures.synthetic()
        return c.stops.map { stop in
            CandidateV1(place: stop.place, evidence: c.evidence.filter { $0.subjectID == stop.id })
        }
            + LabFixtures.candidates()
    }
    public static func brief(knownPlaces: Bool = false) -> RecommendationBriefV1 {
        var brief = RecommendationBriefV1(date: "2026-11-05")
        brief.experiences = [.coffee, .reading]
        brief.pace = .relaxed
        brief.hasPlaces = knownPlaces
        brief.places = knownPlaces ? Array(places().prefix(3)) : []
        return brief
    }
}
public struct RecommendationPipeline: Sendable {
    public let model: any ModelGenerating
    public let search: any RecommendationSearching
    public init(model: any ModelGenerating, search: any RecommendationSearching) {
        self.model = model
        self.search = search
    }
    public func run(
        brief: RecommendationBriefV1, useModel: Bool = true,
        progress: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> RecommendationRunV1 {
        try brief.validate()
        let start = Date()
        let runtime = await model.runtime()
        var records: [StageRecord] = []
        func request<T: Codable & Sendable>(
            _ capability: Capability, prompt: String, fallback: T,
            validate: @escaping @Sendable (String) throws -> T
        ) async throws -> (T, StageRecord) {
            try Task.checkCancellation()
            var record = StageRecord(
                capability: capability, source: "deterministic", status: "baseline",
                instructions: LabPrompts.instructions(capability), prompt: prompt, rawOutput: "",
                displayedOutput: try Codec.text(fallback), error: "", durationSeconds: 0, inputTokens: nil)
            guard useModel && runtime.available && runtime.englishSupported else {
                record.status = useModel ? "blocked" : "baseline"
                record.error = useModel ? runtime.availability : "Model disabled"
                return (fallback, record)
            }
            let began = Date()
            do {
                let response = try await model.generate(.init(capability: capability, prompt: prompt))
                record.rawOutput = response.raw
                record.inputTokens = response.inputTokens
                let output = try validate(response.raw)
                record.source = "Foundation Models"
                record.status = "validated_shape_and_references"
                record.displayedOutput = response.raw
                record.durationSeconds = Date().timeIntervalSince(began)
                return (output, record)
            } catch is CancellationError { throw CancellationError() } catch {
                record.error = String(describing: error)
                record.status = "rejected_or_error"
                if case LabError.timeout = error { record.status = "timeout" }
                record.durationSeconds = Date().timeIntervalSince(began)
                return (fallback, record)
            }
        }
        await progress("Memahami preferensi")
        var extracted = PreferenceExtraction()
        if !brief.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let (value, record) = try await request(
                .preferences, prompt: "CURRENT TEXT:\n" + brief.text,
                fallback: PreferenceExtraction()
            ) { raw in
                let c = try LabFixtures.synthetic()
                try OutputValidation.validate(raw, capability: .preferences, context: c, candidates: [])
                return try JSONDecoder().decode(PreferenceExtraction.self, from: Data(raw.utf8))
            }
            extracted = value
            records.append(record)
        }
        let profile = Baseline.merge(
            persistent: .init(),
            trip: .init(
                interests: brief.experiences.compactMap(\.legacy), avoids: brief.avoids.compactMap(\.legacy)
            ),
            extracted: extracted, paceOverride: brief.pace)
        await progress("Mencari kandidat Jakarta")
        let batch: SearchBatch
        if brief.hasPlaces {
            batch = .init(
                candidates: brief.places,
                source: "Places explicitly selected by the user; original sources retained")
        } else {
            batch = try await search.discover(brief, profile: profile)
        }
        var pool = CandidateFilter.clean(batch.candidates).filter {
            brief.hasPlaces || !brief.excludedIDs.contains($0.id)
        }
        let extractedExperiences = Experience.allCases.filter { experience in
            experience.legacy.map { profile.interests.contains($0) } ?? false
        }
        let extractedAvoids = Experience.allCases.filter { experience in
            experience.legacy.map { profile.avoids.contains($0) } ?? false
        }
        let requested = Set(brief.experiences + extractedExperiences)
            .subtracting(brief.avoids + extractedAvoids)
        if !brief.hasPlaces && !requested.isEmpty {
            let matched = pool.filter {
                !RecommendationRelevance.supportedActivities($0).isDisjoint(with: requested)
            }
            let others = pool.filter {
                RecommendationRelevance.supportedActivities($0).isDisjoint(with: requested)
            }
            pool = matched + others
        }
        let candidates = Array(pool.prefix(6))
        var advice: [PlaceAdviceV1] = []
        for (index, candidate) in candidates.enumerated() {
            try RecommendationValidation.candidate(candidate)
            await progress("Menilai tempat dan waktu \(index + 1)/\(candidates.count)")
            struct Input: Encodable {
                struct Fact: Encodable {
                    var id: String
                    var key: String
                    var value: String
                }
                struct Place: Encodable {
                    var name: String
                    var category: String
                    var evidence: [Fact]
                }
                var profile: PreferenceExtraction
                var candidate: Place
                var supportedCategoryMatches: [String]
                var hasSuppliedTimeFacts: Bool
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let prompt = String(
                decoding: try encoder.encode(
                    Input(
                        profile: profile,
                        candidate: .init(
                            name: candidate.place.name, category: candidate.place.category,
                            evidence: candidate.evidence.map { .init(id: $0.id, key: $0.key, value: $0.value) }),
                        supportedCategoryMatches: RecommendationRelevance.supportedActivities(candidate)
                            .intersection(requested).map(\.rawValue).sorted(),
                        hasSuppliedTimeFacts: candidate.evidence.contains {
                            ["opensMinute", "closesMinute", "experienceWindow"].contains($0.key)
                        })
                ), as: UTF8.self)
            let fallback = PlaceAdviceOutput(
                suitability: .insufficientData,
                reason: "Template: this is a retrieved place; model-based personal fit is unavailable.",
                timeReason: "Suitable visiting time is not established from available information.",
                evidenceIDs: Array(candidate.evidence.prefix(4).map(\.id)),
                unknowns: ["opening hours", "price", "crowds", "accessibility", "travel access"])
            let (output, record) = try await request(.placeAdvice, prompt: prompt, fallback: fallback) {
                let output = try RecommendationValidation.advice($0, candidate: candidate)
                if !brief.hasPlaces && !requested.isEmpty
                    && [.relevant, .possible].contains(output.suitability)
                    && RecommendationRelevance.supportedActivities(candidate).isDisjoint(with: requested)
                {
                    throw LabError.invalid(
                        "Positive relevance without a supported category/name match to requested interests.")
                }
                return output
            }
            records.append(record)
            advice.append(
                .init(candidate: candidate, advice: output, source: record.source, record: record))
        }
        let selected =
            brief.hasPlaces
                ? advice.map(\.id)
                : Array(
                    advice.filter {
                        [.relevant, .possible].contains($0.advice.suitability) && $0.source == "Foundation Models"
                    }.prefix(3).map(\.id))
        let evidence = advice.flatMap { $0.candidate.evidence }
        await progress("Merangkum rekomendasi")
        struct SummaryInput: Encodable {
            struct Fact: Encodable {
                var id: String
                var value: String
            }
            var selectedNames: [String]
            var recommendations: [String]
            var evidence: [Fact]
            var unknowns: [String]
        }
        let identity = evidence.filter { $0.key == "identity" || $0.key == "identityCategory" }
        let summaryEvidence = Array((identity.isEmpty ? evidence : identity).prefix(12))
        let finalSummaryInput = SummaryInput(
            selectedNames: advice.filter { selected.contains($0.id) }.map { $0.candidate.place.name },
            recommendations: advice.map {
                "\($0.candidate.place.name); fit=\($0.advice.suitability.rawValue); time=\($0.advice.window.rawValue), basis=\($0.advice.timeBasis.rawValue)"
            },
            evidence: summaryEvidence.map { .init(id: $0.id, value: $0.value) },
            unknowns: ["unverified opening hours", "price", "crowds", "accessibility", "popularity"])
        let fallback = DiscoveryExplanation(
            summary: selected.isEmpty
                ? "Belum ada pilihan model yang cukup untuk dijadikan rekomendasi. Kandidat hasil pencarian tetap dapat ditinjau; waktu yang cocok belum dipastikan."
                : "\(selected.count) tempat pilihan Anda/rekomendasi tersedia untuk ditinjau. Waktu kunjungan berupa saran; tidak ada urutan perjalanan atau rute yang dihitung.",
            evidenceIDs: Array(summaryEvidence.prefix(6).map(\.id)), unknowns: brief.notices)
        let (explanation, summaryRecord) = try await request(
            .discoveryExplanation,
            prompt: String(decoding: try JSONEncoder().encode(finalSummaryInput), as: UTF8.self),
            fallback: fallback
        ) {
            try RecommendationValidation.explanation($0, evidence: summaryEvidence)
        }
        records.append(summaryRecord)
        try Task.checkCancellation()
        return RecommendationRunV1(
            brief: brief, runtime: runtime, profile: profile, search: batch,
            advice: advice, explanation: explanation, records: records, selectedIDs: selected,
            elapsedSeconds: Date().timeIntervalSince(start))
    }
}
public actor RecommendationStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func save(_ run: RecommendationRunV1) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Codec.encode(run).write(
            to: directory.appendingPathComponent(run.id + ".json"), options: .atomic)
    }
    public func runs() throws -> [RecommendationRunV1] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }.map {
            try JSONDecoder().decode(RecommendationRunV1.self, from: Data(contentsOf: $0))
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
    public func saveProfile(_ brief: RecommendationBriefV1) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var profile = brief
        profile.places = []
        profile.hasPlaces = false
        profile.text = ""
        profile.excludedIDs = []
        try Codec.encode(profile).write(
            to: directory.appendingPathComponent("profile.data"), options: .atomic)
    }
    public func profile() throws -> RecommendationBriefV1? {
        let url = directory.appendingPathComponent("profile.data")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(RecommendationBriefV1.self, from: Data(contentsOf: url))
    }
}
