import CryptoKit
import Foundation
import PreferenceLearning

/// Only project-owned passage vectors are persisted. Queries are never written to disk.
public actor LabEmbeddingCache: PreferenceEmbedding {
    private let runtime: LabE5Embedding
    private let directory: URL
    private let areaIDs: [String: String]
    public init(directory: URL, runtime: LabE5Embedding, areaIDs: [String: String]) { self.directory = directory; self.runtime = runtime; self.areaIDs = areaIDs }
    public func metadata() async throws -> EmbeddingMetadata { try await runtime.metadata() }
    public func encode(_ text: String, query: Bool) async throws -> [Float] {
        if query { return try await runtime.encode(text, query: true) }
        let identity = "area=\(areaIDs[text] ?? "unregistered")|e5-v1|\(E5Embedding.revision)|passage: \(text)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent(key + ".json")
        if let data = try? Data(contentsOf: url), let vector = try? JSONDecoder().decode([Float].self, from: data),
           vector.count == 384, vector.allSatisfy(\.isFinite),
           abs(vector.reduce(Float(0)) { $0 + $1 * $1 } - 1) < 0.001 { return vector }
        let vector = try await runtime.encode(text, query: false)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(vector).write(to: url, options: .atomic)
        return vector
    }
}
