import Foundation
import TripIntegration

struct JourneyDraft: Codable {
    var schemaVersion = 1
    var mode: JourneyMode
    var request: TripRequest
    var phase: JourneyPhase
    var selected: Set<String>
    var review: RecommendationReview?
    var prepared: PreparedTrip?
}

actor JourneyDraftStore {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func load() throws -> JourneyDraft? {
        let url = directory.appendingPathComponent("draft.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 25_000_000 else {
            throw IntegrationError.invalid("Draf terlalu besar untuk dibuka.")
        }
        let value = try IntegrationJSON.decoder().decode(JourneyDraft.self, from: Data(contentsOf: url))
        guard value.schemaVersion == 1 else { throw IntegrationError.invalid("Versi draf tidak didukung.") }
        return value
    }
    func save(_ value: JourneyDraft) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try IntegrationJSON.encoder().encode(value).write(to: directory.appendingPathComponent("draft.json"), options: .atomic)
    }
}
