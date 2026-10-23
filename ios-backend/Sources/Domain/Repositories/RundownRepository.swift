import Foundation

public protocol RundownRepository: Sendable {
    func listRundowns() async throws -> [Rundown]
    func rundown(id: UUID) async throws -> Rundown
    /// Reuse requestID when retrying the same command after an uncertain response.
    func createTrip(from versionID: UUID, startsAt: Date, requestID: UUID) async throws -> Trip
}
