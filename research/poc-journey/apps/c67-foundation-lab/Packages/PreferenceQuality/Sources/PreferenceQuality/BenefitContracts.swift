import Foundation
import PreferenceLearning

public struct BenefitDocument: Codable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var sourceIDs: [String]
}

public struct BenefitJudgment: Codable, Sendable {
    public var grade: Int
    public var sourceIDs: [String]
    public var reason: String
}

public struct BenefitCase: Codable, Sendable, Identifiable {
    public var id: String
    public var group: String
    public var family: String
    public var title: String
    public var profile: QualityProfile
    public var judgments: [String: BenefitJudgment]
    public var expectedEligible: [String]
    public var expectedStatus: String
}

public struct BenefitDataset: Codable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var catalog: QualityCatalog
    public var documents: [BenefitDocument]
    public var cases: [BenefitCase]
    public static func load() throws -> Self {
        let url = Bundle.module.url(forResource: "embedding-benefit-v1", withExtension: "json")!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(Self.self, from: Data(contentsOf: url))
        try result.validate()
        return result
    }
    public var snapshotClock: Date {
        catalog.sources.map(\.checkedAt).max()!.addingTimeInterval(1)
    }
    public func validate() throws {
        try catalog.validate()
        let candidates = Dictionary(uniqueKeysWithValues: catalog.candidates.map { ($0.id, $0) })
        guard schemaVersion == 1, !id.isEmpty,
              Set(documents.map(\.id)) == Set(candidates.keys),
              documents.count == candidates.count,
              Set(cases.map(\.id)).count == cases.count,
              documents.allSatisfy({ document in
                  !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && document.text.count <= 1400 && !document.sourceIDs.isEmpty
                      && Set(document.sourceIDs).isSubset(of: Set(candidates[document.id]!.sourceIDs))
              })
        else { throw PreferenceError.invalid("Kontrak dataset semantik tidak valid.") }
        for item in cases {
            try item.profile.validate(catalog: catalog)
            guard !item.id.isEmpty, !item.group.isEmpty,
                  ["literal", "paraphrase", "safety"].contains(item.family),
                  Set(item.expectedEligible).isSubset(of: Set(candidates.keys)),
                  item.judgments.allSatisfy({ id, judgment in
                      guard let candidate = candidates[id] else { return false }
                      return (1 ... 2).contains(judgment.grade) && !judgment.reason.isEmpty
                          && !judgment.sourceIDs.isEmpty
                          && Set(judgment.sourceIDs).isSubset(of: Set(candidate.sourceIDs))
                          && item.expectedEligible.contains(id)
                  }), item.family == "safety" || !item.judgments.isEmpty
            else { throw PreferenceError.invalid("Relevansi/sumber kasus tidak valid: \(item.id)") }
        }
    }
    public func passage(_ candidateID: String, maskNames: Bool) -> String {
        let document = documents.first { $0.id == candidateID }!
        let candidate = catalog.candidates.first { $0.id == candidateID }!
        // Primary evaluation removes venue/scope names, addresses and identifiers from every method.
        let facts = candidate.claims.map { "\($0.feature.english): \($0.value.rawValue)." }
        return (maskNames ? "" : "\(candidate.name). \(candidate.scope). ")
            + document.text + " " + facts.joined(separator: " ")
    }
}

public struct BenefitRow: Codable, Sendable, Identifiable {
    public var id: String
    public var primary: Double
    public var secondary: Double
    public init(id: String, primary: Double, secondary: Double = 0) {
        self.id = id
        self.primary = primary
        self.secondary = secondary
    }
}

public struct BenefitMetrics: Codable, Sendable {
    public var ndcgAt3: Double
    public var precisionAt3: Double
    public var topOneRelevance: Double
}

public struct BenefitRanking: Codable, Sendable, Identifiable {
    public var id: String
    public var rows: [BenefitRow]
    public var metrics: BenefitMetrics?
}

public struct BenefitRun: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var schemaVersion = 1
    public var policy = "benefit-v1-bm25-1.2-0.75-combined-0.6-0.4"
    public var createdAt: Date
    public var evaluationClock: Date
    public var datasetID: String
    public var input: BenefitCase
    public var catalog: QualityCatalog
    public var documents: [BenefitDocument]
    public var maskedNames: Bool
    public var decisions: [QualityDecision]
    public var rankings: [BenefitRanking]
    public var embedding: EmbeddingMetadata?
    public var status: String
    public var error: String
    public var gatePassed: Bool
    public var lexicalSeconds: Double
    public var embeddingSeconds: Double
    public var totalSeconds: Double
    public var queryEncodes: Int
    public var documentEncodes: Int
}

public enum BenefitCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
