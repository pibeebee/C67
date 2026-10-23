import Foundation
import C67Domain

/// Synthetic data and memory-only trips. No network, authentication or disk persistence.
public actor MockRundownRepository: RundownRepository {
    private let rundowns: [Rundown]
    private var trips: [UUID: Trip] = [:]

    public init() throws {
        guard let url = Bundle.module.url(forResource: "rundowns", withExtension: "json") else {
            throw RepositoryError.notFound
        }
        rundowns = try JSONDecoder().decode([Rundown].self, from: Data(contentsOf: url))
    }

    public func listRundowns() async throws -> [Rundown] { rundowns }
    public func rundown(id: UUID) async throws -> Rundown {
        guard let value = rundowns.first(where: { $0.id == id }) else { throw RepositoryError.notFound }
        return value
    }
    public func createTrip(from versionID: UUID, startsAt: Date, requestID: UUID) async throws -> Trip {
        if let existing = trips[requestID] {
            guard existing.sourceVersionID == versionID, existing.startsAt == startsAt else {
                throw RepositoryError.idempotencyConflict
            }
            return existing
        }
        let source = try await rundown(id: versionID)
        let trip = Trip(id: UUID(), sourceVersionID: source.id, title: source.title,
                        startsAt: startsAt, stops: source.stops)
        trips[requestID] = trip
        return trip
    }
}
