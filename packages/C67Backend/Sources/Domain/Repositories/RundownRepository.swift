import Foundation

public protocol RundownRepository: Sendable {
    func listRundowns() async throws -> [Rundown]
    func rundown(id: UUID) async throws -> Rundown
    func searchRundowns(query: String, area: String?, limit: Int, cursor: String?) async throws -> RepositoryPage<Rundown>
    func listMyTrips(limit: Int, cursor: String?) async throws -> RepositoryPage<Trip>
    func tripGraph(id: UUID) async throws -> TripGraph
    /// Reuse requestID when retrying the same command after an uncertain response.
    func createTrip(from versionID: UUID, startsAt: Date, requestID: UUID) async throws -> Trip
}

extension RundownRepository {
    public func searchRundowns(query: String = "", area: String? = nil) async throws -> RepositoryPage<Rundown> {
        try await searchRundowns(query: query, area: area, limit: 20, cursor: nil)
    }
    public func listMyTrips() async throws -> RepositoryPage<Trip> {
        try await listMyTrips(limit: 20, cursor: nil)
    }
}
