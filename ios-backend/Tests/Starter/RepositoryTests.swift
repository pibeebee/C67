import Foundation
import Testing
import C67Domain
@testable import C67Data

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

@Test func mockPlanningPreservesRequestedOrderAndRecalculatesTimes() async throws {
    let repository = MockPlanningRepository()
    var input = try MockPlanningRepository.sampleInput()
    input.places.reverse()
    input.preservesPlaceOrder = true
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .plan, input: input))
    let proposal = try #require(job.result?.proposal)
    #expect(proposal.stops.map(\.id) == input.places.map(\.id))
    var previous = input.startsAt
    for stop in proposal.stops {
        #expect(stop.arrivalAt == previous.addingTimeInterval(Double(stop.travelSeconds)))
        #expect(stop.departureAt == stop.arrivalAt.addingTimeInterval(Double(stop.visitSeconds)))
        previous = stop.departureAt
    }
    #expect(proposal.finishesAt == previous)
}

@Test func manualOrderWireFlagRoundTripsAndDefaultsForOlderPayloads() throws {
    var input = try MockPlanningRepository.sampleInput()
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let olderPayload = try encoder.encode(PlanningInputDTO(input))
    let olderJSON = try #require(JSONSerialization.jsonObject(with: olderPayload) as? [String: Any])
    #expect(olderJSON["preserve_place_order"] == nil)
    #expect(try decoder.decode(PlanningInputDTO.self, from: olderPayload).domain == input)
    input.preservesPlaceOrder = true
    let fixedPayload = try encoder.encode(PlanningInputDTO(input))
    let fixedJSON = try #require(JSONSerialization.jsonObject(with: fixedPayload) as? [String: Any])
    #expect(fixedJSON["preserve_place_order"] as? Bool == true)
    #expect(try decoder.decode(PlanningInputDTO.self, from: fixedPayload).domain == input)
}
