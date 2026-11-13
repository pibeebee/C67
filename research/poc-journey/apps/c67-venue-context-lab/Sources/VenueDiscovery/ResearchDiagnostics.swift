import Foundation

struct EvidenceBlock: Codable, Sendable {
    var kind: String
    var text: String
    var sourceURL: URL?
    var title: String?
}

public struct PageAttempt: Codable, Sendable {
    var url: URL
    var resolvedURL: URL?
    var attempt: Int
    var status: Int
    var reason: String
    var durationSeconds: Double
}

public struct FieldDiagnostic: Codable, Sendable {
    var field: VenueField
    var outcome: String
    var reason: String
    var proposed: GiovancExtractor.Claim?
}

public struct VenueResearchReport: Codable, Sendable {
    var venueID: String
    var startedAt: Date
    var completedAt: Date?
    var stage: String
    var error: String?
    var pageAttempts: [PageAttempt] = []
    var discoveredURLs: [URL] = []
    var pageURLs: [URL] = []
    var cachedPages = 0
    var excerpts = 0
    var searchURLs: [URL]?
    var searchCacheHit: Bool?
    var searchError: String?
    var modelAttempts = 0
    var modelErrors: [String] = []
    var fields: [FieldDiagnostic] = []
}
