import Foundation
import Testing
import C67Domain
import C67Data

@Test func mockCopiesSnapshotAndRetriesWithoutDuplicating() async throws {
    let repository = try MockRundownRepository()
    let source = try #require(try await repository.listRundowns().first)
    let request = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let trip = try await repository.createTrip(from: source.id, startsAt: start, requestID: request)
    let retry = try await repository.createTrip(from: source.id, startsAt: start, requestID: request)
    #expect(trip == retry)
    #expect(trip.id != source.id)
    #expect(trip.stops == source.stops)
    #expect(trip.startsAt == start)
    let unchanged = try await repository.rundown(id: source.id)
    #expect(unchanged == source)
    await #expect(throws: RepositoryError.idempotencyConflict) {
        try await repository.createTrip(from: source.id, startsAt: start.addingTimeInterval(60), requestID: request)
    }
}

@Test func liveTripRequiresTravellerSessionBeforeNetwork() async throws {
    let repository = try SupabaseRundownRepository(baseURL: #require(URL(string: "https://example.com")), clientKey: "example-client-key")
    await #expect(throws: RepositoryError.authenticationRequired) {
        try await repository.createTrip(from: UUID(), startsAt: Date(), requestID: UUID())
    }
}

@Test func invalidRemoteConfigurationIsRejected() throws {
    #expect(throws: RepositoryError.invalidConfiguration) {
        try SupabaseRundownRepository(baseURL: #require(URL(string: "http://example.com")), clientKey: "example")
    }
}
