import Foundation
import Testing
import C67Domain
import PocketEngine
@testable import C67Data

@Test func orderingMethodRequiresMatchingServerEchoAndDecodesOldPreferences() throws {
    let original = try JSONDecoder().decode(PlanningPreferences.self, from: JSONEncoder().encode(PlanningPreferences()))
    #expect(original.orderingMethod == nil)
    try PocketOrderCodec.validateMethod(nil, expected: .luna)
    try PocketOrderCodec.validateMethod(.hybridLegacy, expected: .hybridLegacy)
    try PocketOrderCodec.validateMethod(.hybridWeather, expected: .hybridWeather)
    #expect(throws: PlanningError.self) { try PocketOrderCodec.validateMethod(nil, expected: .hybridWeather) }
    #expect(throws: PlanningError.self) { try PocketOrderCodec.validateMethod(.hybridLegacy, expected: .hybridWeather) }
    var selection = PlanningPreferences()
    selection.orderingMethod = .hybridWeather
    let restored = try JSONDecoder().decode(PlanningPreferences.self, from: JSONEncoder().encode(selection))
    #expect(restored.orderingMethod == .hybridWeather)
}

@Test func orderingMethodIsRetainedInThePlanningJob() async throws {
    let services = PocketPlanningServices(travel: { _, _, _, _ in throw PlanningError.invalidResponse },
                                          weather: { _, _, _ in throw PlanningError.invalidResponse },
                                          advise: { _ in throw PlanningError.invalidResponse },
                                          order: { input, _ in try PocketIntegrationFixture.experience(input) })
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: nil)
    var input = try orderInput()
    input.enginePreferences?.orderingMethod = .hybridLegacy
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(job.input.enginePreferences?.orderingMethod == .hybridLegacy)
    #expect(job.command?.input.enginePreferences?.orderingMethod == .hybridLegacy)
}

private actor OrderConnection: PocketConnectionProviding {
    func credentials() -> PocketCredentials { .init(serverURL: "https://fixture.invalid", token: "synthetic") }
    func update(serverURL: String, token: String) {}
}

private struct MissingOrderToken: PocketConnectionProviding {
    func credentials() async -> PocketCredentials { .init(serverURL: "https://fixture.invalid", token: "") }
    func update(serverURL: String, token: String) async throws { throw PlanningError.unavailable }
}

private actor OrderCounter {
    var ids: [UUID] = []
    let failFirst: Bool
    let failAlways: Bool
    init(failFirst: Bool = false, failAlways: Bool = false) { self.failFirst = failFirst; self.failAlways = failAlways }
    func generate(_ input: PlanningInput, id: UUID) throws -> PlanningExperiencePlan {
        ids.append(id)
        if failAlways { throw PlanningError.failed("ORDER_GENERATION_FAILED") }
        if failFirst, ids.count == 1 { throw PlanningError.unavailable }
        return try PocketIntegrationFixture.experience(input)
    }
}

private actor DriveCounter {
    struct Call: Equatable, Sendable {
        let origin: Coordinate
        let destination: Coordinate
        let at: Date
        let mode: PlanningMode
    }

    private(set) var calls: [Call] = []
    private let failsOnCall: Int?
    init(failsOnCall: Int? = nil) { self.failsOnCall = failsOnCall }

    func quote(_ origin: Coordinate, _ destination: Coordinate, _ at: Date, _ mode: PlanningMode) throws -> LegQuote {
        calls.append(.init(origin: origin, destination: destination, at: at, mode: mode))
        if calls.count == failsOnCall { throw PlanningError.unavailable }
        return .init(seconds: Double(calls.count * 60), meters: Double(calls.count * 1000))
    }
}

private actor SuspendedOrder {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var starts = 0

    func wait() async {
        starts += 1
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted(_ count: Int) async {
        if starts < count { await withCheckedContinuation { startWaiter = $0 } }
    }

    func release() { continuation?.resume(); continuation = nil }
}

@Test func signingOutDiscardsLateOrderingResultAndAllowsRetry() async throws {
    let gate = SuspendedOrder()
    let services = PocketPlanningServices(travel: { _, _, _, _ in throw PlanningError.invalidResponse },
                                          weather: { _, _, _ in throw PlanningError.invalidResponse },
                                          advise: { _ in throw PlanningError.invalidResponse },
                                          resolve: { _, _ in throw PlanningError.invalidResponse },
                                          order: { input, _ in
                                              await gate.wait()
                                              return try PocketIntegrationFixture.experience(input)
                                          })
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("trip.json")
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: url)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: orderInput()))
    await gate.waitUntilStarted(1)
    let before = try Data(contentsOf: url)
    await repository.suspendOrdering()
    await gate.release()
    try await Task.sleep(for: .milliseconds(50))
    #expect(try Data(contentsOf: url) == before)
    let after = try #require(await repository.resumePlanning())
    #expect(after.status == .running)
    #expect(after.result == nil)
    await gate.waitUntilStarted(2)
    await gate.release()
    #expect(try await finished(repository, id: job.id).status == .succeeded)
}

private func orderInput(count: Int = 3) throws -> PlanningInput {
    var input = PocketIntegrationFixture.input()
    input.places = Array(try PocketIntegrationFixture.searchablePlaces().prefix(count))
    input.enginePreferences?.mainSpotID = input.places.first?.id
    return input
}

private func orderRepository(_ counter: OrderCounter, storage: URL? = nil, driving: DriveCounter? = nil) throws -> PocketPlanningRepository {
    let services = PocketPlanningServices(travel: { from, to, at, mode in
                                              guard let driving else { throw PlanningError.invalidResponse }
                                              return try await driving.quote(from, to, at, mode)
                                          },
                                          weather: { _, _, _ in throw PlanningError.invalidResponse }, advise: { _ in throw PlanningError.invalidResponse },
                                          resolve: { _, _ in throw PlanningError.invalidResponse }, order: { try await counter.generate($0, id: $1) })
    return try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: storage, synthetic: true)
}

private func finished(_ repository: PocketPlanningRepository, id: UUID) async throws -> PlanningJob {
    for _ in 0 ..< 100 {
        let job = try await repository.planningJob(id: id)
        if job.status == .succeeded || job.status == .failed { return job }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw PlanningError.unavailable
}

@Test func reasonableOrderKeepsUnknownPlacesAndHasNoInventedSchedule() async throws {
    let counter = OrderCounter(), repository = try orderRepository(counter)
    let input = try orderInput()
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(first.status == .running)
    let job = try await finished(repository, id: first.id)
    let plan = try #require(job.result?.proposal)
    #expect(plan.stops.map(\.id) == input.places.map(\.id))
    #expect(plan.stops.allSatisfy { $0.arrivalAt == nil && $0.departureAt == nil })
    #expect(plan.finishesAt == nil && plan.departureAt == nil && plan.returnTravelSeconds == nil)
    #expect(plan.experiencePlan?.stops.last?.duration == nil)
    #expect(plan.input.enginePreferences?.reasonableOrdering == true)
    #expect(await counter.ids.count == 1)
}

@Test func missingPocketTokenPreservesDraftAndReportsConfigurationFailure() async throws {
    let connection = MissingOrderToken()
    let client = PocketResearchClient(connection: connection)
    let services = PocketPlanningServices(travel: { _, _, _, _ in throw PlanningError.invalidResponse },
                                          weather: { _, _, _ in throw PlanningError.invalidResponse }, advise: { _ in throw PlanningError.invalidResponse },
                                          resolve: { _, _ in throw PlanningError.invalidResponse }, order: { try await client.order($0, requestID: $1) })
    let repository = try PocketPlanningRepository(services: services, connection: connection, storageURL: nil)
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: try orderInput())
    let job = try await repository.requestPlan(command)
    let failed = try await finished(repository, id: job.id)
    #expect(failed.status == .failed)
    #expect(failed.errorCode == "POCKET_CONNECTION_REQUIRED")
    #expect(failed.command == command)
    #expect(await repository.resumePlanning()?.id == job.id)
}

@Test func repeatedOrderCommandAndReadsDoNotRegenerateLuna() async throws {
    let counter = OrderCounter(), repository = try orderRepository(counter)
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: try orderInput())
    let first = try await repository.requestPlan(command)
    let second = try await repository.requestPlan(command)
    #expect(first.id == second.id)
    _ = try await finished(repository, id: first.id)
    _ = try await repository.requestPlan(command)
    _ = try await repository.planningJob(id: first.id)
    #expect(await counter.ids == [command.requestID])
    var changed = command; changed.input.preferences = "Changed wish"
    await #expect(throws: PlanningError.requestConflict) { try await repository.requestPlan(changed) }
}

@Test func untimedTripCanBeRenamedSavedReloadedAndStartedWithoutAnotherModelCall() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("trip.json")
    let counter = OrderCounter(), repository = try orderRepository(counter, storage: url)
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: try orderInput()))
    _ = try await finished(repository, id: first.id)
    let renamed = try await repository.renameProposal(jobID: first.id, title: "My ordered places")
    #expect(renamed.result?.proposal?.input.title == "My ordered places")
    let trip = try await repository.applyProposal(jobID: first.id, expectedRevision: nil, requestID: UUID())
    let reopened = try orderRepository(counter, storage: url)
    let saved = try #require(await reopened.personalTrips().first)
    #expect(saved == trip)
    #expect(saved.plan.finishesAt == nil && saved.plan.experiencePlan != nil)
    let active = try await reopened.recordEvent(tripID: trip.id, event: .init(requestID: UUID(), expectedRevision: trip.revision, kind: .start))
    #expect(active.status == .active)
    #expect(await counter.ids.count == 1)
}

@Test func experienceEstimatesUseConsistentLegsAndSaveAnEditedDepartureWithoutLuna() async throws {
    let counter = OrderCounter(), repository = try orderRepository(counter)
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: try orderInput())
    let started = try await repository.requestPlan(command)
    let completed = try await finished(repository, id: started.id)
    let original = try #require(completed.result?.proposal)
    let departure = try #require(original.estimatedExperienceDeparture)
    let stops = original.stopsWithExperienceEstimates
    #expect(stops[0].arrivalAt == departure.addingTimeInterval(360))
    #expect(stops[1].arrivalAt == stops[0].departureAt?.addingTimeInterval(360))
    #expect(stops.last?.visitSeconds == 1800)
    #expect(original.stops.allSatisfy { $0.arrivalAt == nil })

    let edited = departure.addingTimeInterval(25 * 3600)
    let changed = try await repository.setExperienceDeparture(jobID: started.id, departure: edited)
    #expect(changed.result?.proposal?.experiencePlan == original.experiencePlan)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: changed.input.timeZone))
    #expect(calendar.isDate(changed.input.startsAt, inSameDayAs: edited))
    let saved = try await repository.applyProposal(jobID: started.id, expectedRevision: nil, requestID: UUID())
    #expect(saved.plan.estimatedExperienceDeparture == edited)
    #expect(saved.input.startsAt == changed.input.startsAt)
    #expect(saved.plan.stopsWithExperienceEstimates.first?.arrivalAt == edited.addingTimeInterval(360))
    #expect(await counter.ids == [command.requestID])
}

@Test func manualReorderReusesMatchingLegAndDoesNotRequestAnotherLunaOrder() async throws {
    let counter = OrderCounter(), driving = DriveCounter()
    let repository = try orderRepository(counter, driving: driving)
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: try orderInput())
    let started = try await repository.requestPlan(command)
    let original = try #require(try await finished(repository, id: started.id).result?.proposal)
    let ids = original.stops.map(\.id)
    #expect(original.stops.map(\.travelSeconds) == [60, 120, 180])
    #expect(original.stops.map(\.roadDistanceMeters) == [1000, 2000, 3000])
    let prior = await driving.calls
    #expect(prior[1].at == original.stopsWithExperienceEstimates[0].departureAt)
    #expect(prior.allSatisfy { $0.mode == .automobile })

    let ordered = [ids[0], ids[2], ids[1]]
    let job = try await repository.updateExperienceRoute(jobID: started.id, orderedIDs: ordered, departure: nil)
    let proposal = try #require(job.result?.proposal)
    #expect(job.id == started.id)
    #expect(job.input.places.map(\.id) == ordered)
    #expect(job.input.preservesPlaceOrder)
    #expect(proposal.stops.map(\.id) == ordered)
    #expect(proposal.experiencePlan == original.experiencePlan)
    #expect(proposal.stops.map(\.travelSeconds) == [60, 240, 300])
    let all = await driving.calls
    #expect(all.count == 5)
    #expect(all[3].origin == prior[1].origin)
    #expect(all[3].destination == prior[2].destination)
    #expect(all[4].destination == prior[1].destination)

    let trip = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
    #expect(trip.plan.stops == proposal.stops)
    #expect(await counter.ids == [command.requestID])
}

@Test func unavailableDrivingLegKeepsSelectionWithAnExplicitFallback() async throws {
    let counter = OrderCounter(), driving = DriveCounter(failsOnCall: 2)
    let repository = try orderRepository(counter, driving: driving)
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: try orderInput())
    let started = try await repository.requestPlan(command)
    let plan = try #require(try await finished(repository, id: started.id).result?.proposal)
    #expect(plan.stops.map(\.id) == command.input.places.map(\.id))
    #expect(plan.hasExperienceTravelFallback)
    #expect(plan.stops.map(\.roadDistanceMeters) == [1000, nil, 3000])
    #expect(plan.stopsWithExperienceEstimates.map(\.travelSeconds) == [60, 360, 180])
    #expect(await counter.ids == [command.requestID])
}

@Test func disconnectedOrderRetriesTheSameRequestIdentity() async throws {
    let counter = OrderCounter(failFirst: true), repository = try orderRepository(counter)
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: try orderInput())
    let first = try await repository.requestPlan(command)
    var interrupted = false
    for _ in 0 ..< 100 {
        do { _ = try await repository.planningJob(id: first.id) }
        catch PlanningError.unavailable { interrupted = true; break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(interrupted)
    let retry = try await repository.requestPlan(command)
    #expect(retry.id == first.id)
    #expect(try await finished(repository, id: first.id).status == .succeeded)
    #expect(await counter.ids == [command.requestID, command.requestID])
}

@Test func failedOrderIsNotAutomaticallyRegeneratedOnRead() async throws {
    let counter = OrderCounter(failAlways: true), repository = try orderRepository(counter)
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: try orderInput())
    let first = try await repository.requestPlan(command)
    #expect(try await finished(repository, id: first.id).status == .failed)
    #expect(try await repository.requestPlan(command).status == .failed)
    _ = try await repository.planningJob(id: first.id)
    #expect(await counter.ids.count == 1)
}

@Test func reasonableOrderRejectsLostSelectionsAndBadDuration() throws {
    var input = try orderInput(); input.enginePreferences?.reasonableOrdering = true
    var plan = try PocketIntegrationFixture.experience(input)
    plan.orderedIDs.removeLast()
    #expect(throws: PlanningError.invalidResponse) { try plan.validated(for: input) }
    plan = try PocketIntegrationFixture.experience(input)
    plan.stops[0].duration?.minMinutes = 0
    #expect(throws: PlanningError.invalidResponse) { try plan.validated(for: input) }
}

@Test func untimedManualOrderAndLargerSelectionRemainSupported() async throws {
    let counter = OrderCounter(), repository = try orderRepository(counter)
    var input = try orderInput(count: 7)
    input.enginePreferences?.reasonableOrdering = true
    input.preservesPlaceOrder = true
    input.places.reverse()
    try input.validate()
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .plan, input: input))
    let plan = try #require(try await finished(repository, id: first.id).result?.proposal)
    #expect(plan.stops.map(\.id) == input.places.map(\.id))
    #expect(plan.stops.count == 7)
}

@Test func firstOrderInitializesMissingPreferencesAndKeepsTheRequestForResume() async throws {
    let counter = OrderCounter(), repository = try orderRepository(counter)
    var input = try orderInput(); input.enginePreferences = nil
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
    let first = try await repository.requestPlan(command)
    let complete = try await finished(repository, id: first.id)
    #expect(complete.status == .succeeded)
    #expect(complete.command == command)
    #expect(complete.result?.proposal?.experiencePlan?.orderedIDs.count == input.places.count)
}

@Test func recommendationFromADifferentForecastDayIsRejected() throws {
    let input = try orderInput()
    var plan = try PocketIntegrationFixture.experience(input)
    plan.candidateDate = "1999-01-01"
    #expect(throws: PlanningError.invalidResponse) { try plan.validated(for: input) }
}

@Test func serverContractResponseDecodesWithNullableDurationAndCalculatedLight() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/pocket-order-result.json"))
    let plan = try PocketOrderCodec.decoder().decode(PlanningExperiencePlan.self, from: data)
    let requestData = try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/pocket-order-request.json"))
    struct Selected: Decodable { let id: UUID; let name: String; let location: PlanningPoint }
    struct Request: Decodable { let places: [Selected]; let mainSpotID: UUID; let candidateDate: String }
    let request = try JSONDecoder().decode(Request.self, from: requestData)
    var input = PocketIntegrationFixture.input()
    input.startsAt = try #require(ISO8601DateFormatter().date(from: request.candidateDate + "T09:00:00+07:00"))
    input.finishBy = input.startsAt.addingTimeInterval(3600)
    input.places = request.places.map { .init(id: $0.id, name: $0.name, location: $0.location, visitSeconds: 0) }
    input.enginePreferences?.mainSpotID = request.mainSpotID
    _ = try plan.validated(for: input)
    #expect(plan.stops.count == 5)
    #expect(plan.stops[1].duration == nil)
    #expect(plan.solarWindows.count == 10)
}

@Test func weatherKitAttributionDecodesWithBackwardCompatibility() throws {
    let decoder = PocketOrderCodec.decoder()
    let base = #"{"id":"AW1","placeID":"11111111-1111-4111-8111-111111111111","source":"Apple Weather","url":"https://weatherkit.apple.com/legal-attribution.html","checkedAt":"2026-11-15T01:00:00Z","date":"2026-11-15","timeZone":"Asia/Jakarta","coordinates":{"latitude":-6.2,"longitude":106.8},"hourlySamples":[],"coverage":"Synthetic""#
    let withLogo = Data((base + #", "attributionLogoURL":"https://weatherkit.apple.com/assets/mark.png"}"#).utf8)
    let source = try decoder.decode(PlanningExperiencePlan.WeatherSource.self, from: withLogo)
    #expect(source.attributionLogoURL?.host == "weatherkit.apple.com")
    let old = try decoder.decode(PlanningExperiencePlan.WeatherSource.self, from: Data((base + "}").utf8))
    #expect(old.attributionLogoURL == nil)
}
