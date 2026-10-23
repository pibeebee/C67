import Foundation

public struct Stop: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let order: Int
}

/// A published creator snapshot. A personal trip keeps its own copy.
public struct Rundown: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let area: String
    public let summary: String
    public let stops: [Stop]
}

public struct Trip: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceVersionID: UUID
    public let title: String
    public let startsAt: Date
    public let stops: [Stop]

    public init(id: UUID, sourceVersionID: UUID, title: String, startsAt: Date, stops: [Stop]) {
        self.id = id
        self.sourceVersionID = sourceVersionID
        self.title = title
        self.startsAt = startsAt
        self.stops = stops
    }

    enum CodingKeys: String, CodingKey {
        case id, title, stops
        case sourceVersionID = "source_version_id"
        case startsAt = "starts_at"
    }
}

public enum RepositoryError: Error, Equatable, LocalizedError, Sendable {
    case notFound, authenticationRequired, invalidConfiguration, idempotencyConflict
    case server(status: Int)

    public var errorDescription: String? {
        switch self {
        case .notFound: "This rundown is no longer available."
        case .authenticationRequired: "A traveller session is required. App sign-in is a follow-up task."
        case .invalidConfiguration: "Check the local Supabase URL and client key."
        case .idempotencyConflict: "This request ID was already used for a different trip."
        case .server(let status): "The server could not complete this request (HTTP \(status))."
        }
    }
}
