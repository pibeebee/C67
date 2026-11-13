import Foundation
import C67Domain

struct DiscoveryInteractor: Sendable {
    let repository: any RundownRepository
    func load() async throws -> [Rundown] { try await repository.listRundowns() }
    func save(_ rundown: Rundown, at start: Date, requestID: UUID) async throws -> Trip {
        try await repository.createTrip(from: rundown.id, startsAt: start, requestID: requestID)
    }
}
