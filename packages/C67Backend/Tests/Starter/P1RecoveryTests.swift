import Foundation
import Testing
import PocketEngine
import C67Domain
@testable import C67Data

private struct P1Connection: PocketConnectionProviding {
    func credentials() -> PocketCredentials { .init(serverURL: "https://fixture.invalid", token: "fixture") }
    func update(serverURL: String, token: String) {}
}

private actor P1ModelCalls {
    var count = 0
    func experience(_ inputs: [PlanningInput]) throws -> [PlanningExperiencePlan] {
        count += 1
        return try inputs.map(PocketIntegrationFixture.experience)
    }
}

@Test(arguments: [false, true])
func p1ActiveTripKeepsExtendedStayAndReturnsToEndpointWithoutCallingLuna(hasActivitySession: Bool) async throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-11-19T09:00:00+07:00"))
    let clock = TestClock()
    clock.advance(now.timeIntervalSince(clock.now()))
    let model = P1ModelCalls()
    var services = v41Services(V41Calls(), model: false)
    services.experience = { inputs, _ in try await model.experience(inputs) }
    let repository = try PocketPlanningRepository(services: services, connection: P1Connection(), storageURL: nil,
                                                  synthetic: true, jobClock: { clock.now() })
    var input = try v41Input(count: 2)
    input.startsAt = now
    input.finishBy = now.addingTimeInterval(8 * 3600)
    input.enginePreferences?.orderingMethod = .hybridV42
    input.enginePreferences?.returnToOrigin = true
    input.enginePreferences?.semanticAssistance = .whenNeeded
    input.enginePreferences?.allowsAIProcessing = true
    input.enginePreferences?.usesLuna = true
    input.preservesPlaceOrder = true
    for index in input.places.indices { input.places[index].durationOverridden = false }
    if hasActivitySession {
        input.enginePreferences?.maximumWaitMinutes = 60
        input.places[0].activitySession = .init(startsAt: now.addingTimeInterval(3600), endsAt: now.addingTimeInterval(7200))
    }
    let request = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    _ = try await finished(repository, id: request.id)
    var trip = try await repository.applyProposal(jobID: request.id, expectedRevision: nil, requestID: UUID())

    func event(_ kind: PlanningEventKind, trip: PersonalPlanningTrip, stopID: UUID? = nil,
               extraSeconds: Int? = nil, preparationID: UUID? = nil) async throws -> PersonalPlanningTrip {
        var event = PlanningEvent(requestID: UUID(), expectedRevision: trip.revision, kind: kind, stopID: stopID, extraSeconds: extraSeconds)
        event.preparationID = preparationID
        return try await repository.recordEvent(tripID: trip.id, event: event)
    }

    let preparation = try await repository.prepareStart(tripID: trip.id, expectedRevision: trip.revision)
    trip = try await event(.start, trip: trip, preparationID: preparation?.id)
    let first = try #require(trip.nextStop)
    if hasActivitySession { clock.advance(3600) }
    trip = try await event(.arrive, trip: trip, stopID: first.id)
    trip = try await event(.extendStay, trip: trip, stopID: first.id, extraSeconds: 1800)
    let extendedDeparture = try #require(trip.plan.stops.first?.departureAt)
    let replan = try await repository.requestPlan(.init(requestID: UUID(), purpose: .replan, input: trip.input,
                                                        tripID: trip.id, baseRevision: trip.revision))
    let updated = try await finished(repository, id: replan.id)
    let proposal = try #require(updated.result?.proposal)
    #expect(proposal.stops.map(\.id) == input.places.map(\.id))
    #expect(proposal.stops.first?.visitSeconds == first.visitSeconds + 1800)
    #expect(proposal.stops.first?.departureAt == extendedDeparture)
    #expect(try #require(proposal.stops.last?.arrivalAt) >= extendedDeparture)
    #expect(proposal.input.planningEndpoint == input.origin)
    trip = try await repository.applyProposal(jobID: updated.id, expectedRevision: trip.revision, requestID: UUID())
    #expect(trip.plan.stops.first?.departureAt == extendedDeparture)
    trip = try await event(.completeStop, trip: trip, stopID: first.id)
    let second = try #require(trip.nextStop)
    trip = try await event(.arrive, trip: trip, stopID: second.id)
    trip = try await event(.completeStop, trip: trip, stopID: second.id)
    #expect(trip.status == .active)
    #expect(trip.pendingEndpoint == input.origin)
    trip = try await event(.arriveAtEndpoint, trip: trip)
    #expect(trip.status == .completed)
    #expect(await model.count == 1)
}

@Test func p1EditDateUsesNewLunaEstimateAndKeepsOrder() async throws {
    let model = P1ModelCalls()
    var services = v41Services(V41Calls(), model: false)
    services.experience = { inputs, _ in try await model.experience(inputs) }
    let repository = try PocketPlanningRepository(services: services, connection: P1Connection(), storageURL: nil)
    var input = try v41Input(count: 1)
    input.enginePreferences?.orderingMethod = .hybridV42
    input.enginePreferences?.semanticAssistance = .whenNeeded
    input.enginePreferences?.allowsAIProcessing = true
    input.enginePreferences?.usesLuna = true
    input.places[0].durationOverridden = false
    let request = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let original = try await finished(repository, id: request.id)
    let departure = try #require(original.result?.proposal?.departureAt).addingTimeInterval(86400)
    let edited = try await repository.updateExperienceRoute(jobID: request.id, orderedIDs: nil, departure: departure)
    #expect(edited.result?.proposal?.departureAt == departure)
    #expect(edited.result?.proposal?.stops.map(\.id) == input.places.map(\.id))
    #expect(await model.count == 2)
}

@Test func p1PartialComparisonKeepsAValidatedDateWhenNextDateIsUnavailable() async throws {
    let clock = try #require(ISO8601DateFormatter().date(from: "2026-11-19T09:00:00+07:00"))
    var input = try v41Input(count: 1)
    input.enginePreferences?.orderingMethod = .hybridV42
    input.enginePreferences?.scheduleSource = .timingAnswer
    input.enginePreferences?.tripTiming = .inAFewDays
    input.enginePreferences?.timingAnchor = clock
    input.enginePreferences?.allowsAIProcessing = true
    input.enginePreferences?.usesLuna = true
    input.enginePreferences?.semanticAssistance = .whenNeeded
    input.places[0].durationOverridden = false
    let first = try #require(try PlanningDayWindow.v41Inputs(input, at: clock).first)
    let firstDay = PocketOrderCodec.candidateDay(first)
    var services = v41Services(V41Calls(), model: false)
    services.experience = { inputs, _ in
        guard inputs.count == 1 else { throw PlanningError.invalidResponse }
        guard PocketOrderCodec.candidateDay(inputs[0]) == firstDay else { throw PlanningError.unavailable }
        return try inputs.map(PocketIntegrationFixture.experience)
    }
    let planner = V41ItineraryPlanner(services: services, hours: { _ in .init(status: "unavailable") }, synthetic: true)
    let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input,
                          tripID: nil, baseRevision: nil, result: nil, errorCode: nil, createdAt: clock)
    let result = try await planner.plan(job)
    let proposal = try #require(result.proposal)
    #expect(proposal.experiencePlan?.candidateDate == firstDay)
    #expect(proposal.scheduleAssessment?.dates.last?.stopReason == "provider_unverified")
}

@Test func p1CancellationReleasesPlanningSlotAndKeepsCommand() async throws {
    var services = v41Services(V41Calls(), model: false)
    services.experience = { _, _ in
        try await Task.sleep(for: .seconds(30))
        throw PlanningError.unavailable
    }
    let repository = try PocketPlanningRepository(services: services, connection: P1Connection(), storageURL: nil)
    var input = try v41Input(count: 1)
    input.enginePreferences?.orderingMethod = .hybridV42
    input.enginePreferences?.semanticAssistance = .whenNeeded
    input.enginePreferences?.allowsAIProcessing = true
    input.enginePreferences?.usesLuna = true
    input.places[0].durationOverridden = false
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
    let running = try await repository.requestPlan(command)
    try await repository.cancelPlanning(id: running.id)
    #expect(try await repository.planningJob(id: running.id).errorCode == "PLANNING_CANCELLED")
    #expect(await repository.resumePlanning()?.command == command)
    input.places[0].durationOverridden = true
    let next = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(try await finished(repository, id: next.id).status == .succeeded)
}

private actor P1StorageFault {
    let store: URL
    let movedStore: URL
    var calls = 0

    init(store: URL, movedStore: URL) {
        self.store = store
        self.movedStore = movedStore
    }

    func quote() throws -> LegQuote {
        calls += 1
        if calls == 1 {
            try FileManager.default.moveItem(at: store, to: movedStore)
            try Data("synthetic unavailable store".utf8).write(to: store)
        }
        return .init(seconds: 120, meters: 500)
    }
}

@Test func p1CheckingStatusWritesTheComputedResultWithoutRepeatingTheProvider() async throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = temp.appendingPathComponent("store")
    let backup = temp.appendingPathComponent("backup")
    defer { try? FileManager.default.removeItem(at: temp) }
    let fault = P1StorageFault(store: directory, movedStore: backup)
    let services = PocketPlanningServices(travel: { _, _, _, _ in try await fault.quote() },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable })
    let repository = try PocketPlanningRepository(services: services, connection: P1Connection(),
                                                  storageURL: directory.appendingPathComponent("trips.json"))
    var input = try v41Input(count: 1)
    input.enginePreferences?.orderingMethod = .hybridV42
    input.enginePreferences?.flexibleDeparture = false
    input.preservesPlaceOrder = true
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    var sawStorageFailure = false
    for _ in 0 ..< 100 {
        do { _ = try await repository.checkPlanningJob(id: job.id) }
        catch PlanningError.unavailable { sawStorageFailure = true; break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(sawStorageFailure)
    try FileManager.default.removeItem(at: directory)
    try FileManager.default.moveItem(at: backup, to: directory)
    let recovered = try await repository.checkPlanningJob(id: job.id)
    #expect(recovered.status == .succeeded)
    #expect(await fault.calls == 1)
}

@Test func p1RejectsStartForTripOnAnotherDate() async throws {
    var input = try v41Input(count: 1)
    input.enginePreferences?.orderingMethod = .hybridV42
    let clock = input.startsAt.addingTimeInterval(-86400)
    let services = v41Services(V41Calls(), model: false)
    let repository = try PocketPlanningRepository(services: services, connection: P1Connection(), storageURL: nil, synthetic: true, jobClock: { clock })
    let request = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    _ = try await finished(repository, id: request.id)
    let trip = try await repository.applyProposal(jobID: request.id, expectedRevision: nil, requestID: UUID())
    await #expect(throws: PlanningError.failed("START_DATE_MISMATCH")) {
        try await repository.prepareStart(tripID: trip.id, expectedRevision: trip.revision)
    }
}

@Test func externalAIConsentIsPerTripAndEnforcedAcrossRetryAndRelaunch() async throws {
    let model = P1ModelCalls()
    var services = v41Services(V41Calls(), model: false)
    services.experience = { inputs, _ in try await model.experience(inputs) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = folder.appendingPathComponent("trips.json")
    var input = try v41Input(count: 2)
    input.enginePreferences?.orderingMethod = .hybridV42
    input.enginePreferences?.semanticAssistance = .whenNeeded
    input.enginePreferences?.allowsAIProcessing = true // Flags from a legacy job do not grant permission.
    input.enginePreferences?.usesLuna = true
    for index in input.places.indices { input.places[index].durationOverridden = false }
    let now = input.startsAt
    let checkedServices = services
    func repository(_ disclosure: String) throws -> PocketPlanningRepository {
        try PocketPlanningRepository(services: checkedServices, connection: P1Connection(), storageURL: store,
                                     synthetic: true, jobClock: { now }, requiresExternalAIConsent: true,
                                     externalAIDisclosure: disclosure)
    }
    let first = try repository("v1")
    let legacy = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
    let denied = try await first.requestPlan(legacy)
    #expect(try await finished(first, id: denied.id).errorCode == "AI_CONSENT_REQUIRED")
    _ = try await first.requestPlan(legacy)
    #expect(await model.count == 0)

    var manual = input
    manual.enginePreferences?.semanticAssistance = .disabled
    for index in manual.places.indices { manual.places[index].durationOverridden = true }
    let calculated = try await first.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: manual))
    #expect(try await finished(first, id: calculated.id).status == .succeeded)
    #expect(await model.count == 0)

    let repo: any PlanningRepository = first
    let consent = try await repo.grantExternalAIConsent()
    input.enginePreferences?.externalAIConsentID = consent
    let reopened = try repository("v1")
    let allowed = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
    let job = try await reopened.requestPlan(allowed)
    #expect(try await finished(reopened, id: job.id).status == .succeeded)
    _ = try await reopened.requestPlan(allowed)
    #expect(await model.count == 1)

    let upgraded = try repository("v2")
    #expect(await !upgraded.hasExternalAIConsent(consent))
    try await reopened.withdrawExternalAIConsent()
    let withdrawn = try repository("v1")
    #expect(await !withdrawn.hasExternalAIConsent(consent))
    let blocked = try await withdrawn.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(try await finished(withdrawn, id: blocked.id).errorCode == "AI_CONSENT_REQUIRED")
    #expect(await model.count == 1)
}
