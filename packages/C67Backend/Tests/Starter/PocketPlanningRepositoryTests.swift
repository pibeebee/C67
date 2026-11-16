import Foundation
import Testing
import C67Domain
import C67Data
import PocketEngine

private actor PocketTestConnection: PocketConnectionProviding {
    func credentials() -> PocketCredentials { .init(serverURL: "https://fixture.invalid", token: "fixture") }
    func update(serverURL: String, token: String) {}
}
private actor PocketCallCounter {
    var routes = 0
    var advice = 0
    func route() { routes += 1 }
    func advised() { advice += 1 }
}
private func pocketTestInput(_ catalog: Catalog, count: Int = 3) -> PlanningInput {
    var input = PocketIntegrationFixture.input()
    var preferences = PlanningPreferences()
    preferences.themes = ["foodie"]; preferences.labels = ["japanese_cuisine"]; preferences.allowsAIProcessing = true
    input.enginePreferences = preferences
    input.places = catalog.venues.prefix(count).map { venue in
        var place = PlanningPlace(id: PocketPlanningRepository.identity(venue.id), name: venue.name,
                                  location: .init(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude), visitSeconds: 2700)
        place.sourceID = venue.id; place.categories = venue.categories
        return place
    }
    return input
}
private func pocketTestRepository(catalog: Catalog, counter: PocketCallCounter = PocketCallCounter(), selection: String = "S1", model: String = "gpt-6-luna(max)", storageURL: URL? = nil) throws -> PocketPlanningRepository {
    let services = PocketPlanningServices(travel: { _, _, _, _ in await counter.route(); return .init(seconds: 120, meters: 500) },
                                          weather: { _, _, _ in .init(maxRainChance: nil, summary: "Synthetic weather unavailable") },
                                          advise: { _ in
                                              await counter.advised()
                                              return .init(slotID: selection, requestedModel: "cx/gpt-6-luna(max)", reportedModel: model)
                                          }, resolve: { input, _ in PocketIntegrationFixture.resolution(input, catalog: catalog) })
    return try PocketPlanningRepository(services: services, connection: PocketTestConnection(), storageURL: storageURL, synthetic: true)
}

@Test func pocketPlanningRequiresSelectedPlacesInsteadOfCatalogSuggestions() async throws {
    let catalog = try PocketIntegrationFixture.catalog(), counter = PocketCallCounter()
    let repository = try pocketTestRepository(catalog: catalog, counter: counter)
    let input = pocketTestInput(catalog, count: 0)
    await #expect(throws: (any Error).self) {
        try await repository.requestPlan(.init(requestID: UUID(), purpose: .suggest, input: input))
    }
    #expect(await counter.routes == 0)
    #expect(await counter.advice == 0)
    #expect(repository.preferenceLabels.count == 62)
}

@Test func pocketUnknownRequiredEvidenceCannotProduceAVisit() async throws {
    let catalog = try PocketIntegrationFixture.catalog(), repository = try pocketTestRepository(catalog: catalog)
    var input = pocketTestInput(catalog, count: 1)
    input.enginePreferences?.conditions["quiet"] = .required
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(job.result?.proposal == nil)
}

@Test func pocketManualOrderReturnLegAndLunaAreRevalidated() async throws {
    let catalog = try PocketIntegrationFixture.catalog(), counter = PocketCallCounter()
    let repository = try pocketTestRepository(catalog: catalog, counter: counter)
    var input = pocketTestInput(catalog)
    input.places.reverse(); input.preservesPlaceOrder = true
    input.enginePreferences?.returnToOrigin = true
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .plan, input: input))
    let proposal = try #require(job.result?.proposal)
    #expect(proposal.stops.map(\.id) == input.places.map(\.id))
    #expect(proposal.returnTravelSeconds == 120)
    #expect((try #require(proposal.finishesAt)).timeIntervalSince(input.startsAt) == 143 * 60)
    #expect(await counter.advice == 1)
    #expect(await counter.routes <= 60)
    #expect(proposal.input == input)
}

@Test(arguments: [("S99", "gpt-6-luna(max)"), ("S1", "different-model")])
func pocketBadLunaResponseNeverFallsBack(_ selection: String, _ model: String) async throws {
    let catalog = try PocketIntegrationFixture.catalog()
    let repository = try pocketTestRepository(catalog: catalog, selection: selection, model: model)
    do {
        _ = try await repository.requestPlan(.init(requestID: UUID(), purpose: .plan, input: pocketTestInput(catalog)))
        Issue.record("Invalid Luna response must not publish a proposal")
    } catch { }
    #expect(await repository.personalTrips().isEmpty)
    #expect(await repository.resumePlanning()?.result == nil)
}

@Test func pocketMissingHoursFailBeforeRoutingAndPersonalConfirmationStaysLocal() async throws {
    var catalog = try PocketIntegrationFixture.catalog()
    for index in catalog.venues.indices { catalog.venues[index].facts = []; catalog.venues[index].hours = nil }
    let counter = PocketCallCounter(), repository = try pocketTestRepository(catalog: catalog, counter: counter)
    var input = pocketTestInput(catalog)
    do {
        _ = try await repository.requestPlan(.init(requestID: UUID(), purpose: .plan, input: input))
        Issue.record("Missing opening/access evidence must not produce an itinerary")
    } catch { }
    #expect(await counter.routes == 0)
    for index in input.places.indices {
        input.places[index].visitConfirmation = .init(opensAt: input.startsAt, closesAt: input.finishBy, publicAccessConfirmed: true)
    }
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .plan, input: input))
    #expect(job.result?.proposal?.stops.count == 3)
    #expect(catalog.venues.allSatisfy { $0.hours == nil && $0.facts.isEmpty })
}

@Test func pocketConsentIsRequiredBeforeAnyRouteOrModelCall() async throws {
    let catalog = try PocketIntegrationFixture.catalog(), counter = PocketCallCounter()
    let repository = try pocketTestRepository(catalog: catalog, counter: counter)
    var input = pocketTestInput(catalog)
    input.enginePreferences?.allowsAIProcessing = false
    do {
        _ = try await repository.requestPlan(.init(requestID: UUID(), purpose: .plan, input: input))
        Issue.record("AI consent must be explicit")
    } catch { }
    #expect(await counter.routes == 0)
    #expect(await counter.advice == 0)
}

@Test func pocketSavedTripsAndRetryIdentitySurviveRepositoryReload() async throws {
    let catalog = try PocketIntegrationFixture.catalog()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("trips.json")
    let first = try pocketTestRepository(catalog: catalog, storageURL: url)
    var input = pocketTestInput(catalog)
    input.enginePreferences?.themes = ["foodie", "culture"]
    let request = PlanningRequest(requestID: UUID(), purpose: .plan, input: input)
    let job = try await first.requestPlan(request)
    let trip = try await first.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
    let second = try pocketTestRepository(catalog: catalog, storageURL: url)
    var retry = request
    retry.input.enginePreferences?.themes = Set(["culture", "foodie"])
    #expect(try await second.requestPlan(retry).id == job.id)
    #expect(await second.personalTrips() == [trip])
    retry.input.enginePreferences?.labels = ["korean_cuisine"]
    await #expect(throws: PlanningError.requestConflict) { try await second.requestPlan(retry) }
}

@Test func pocketServerURLRejectsCredentialsAndNonLocalPlainHTTP() throws {
    #expect(throws: (any Error).self) { try PocketResearchClient.validatedURL("https://user:password@example.com") }
    #expect(throws: (any Error).self) { try PocketResearchClient.validatedURL("http://example.com") }
    #expect(try PocketResearchClient.validatedURL("https://example.com/pocket").host == "example.com")
}

@Test func pocketApplyRetryCannotRollBackAnActiveSavedTrip() async throws {
    let catalog = try PocketIntegrationFixture.catalog(), repository = try pocketTestRepository(catalog: catalog)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .plan, input: pocketTestInput(catalog)))
    let trip = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
    let active = try await repository.recordEvent(tripID: trip.id, event: .init(requestID: UUID(), expectedRevision: 1, kind: .start))
    let retried = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
    #expect(retried.id == trip.id)
    #expect(await repository.personalTrips() == [active])
    #expect(active.revision == 2 && active.status == .active)
}

@Test func pocketResolvedVisitsOutsideFormerAdministrativeAreasAreScheduled() async throws {
    var catalog = try PocketIntegrationFixture.catalog()
    catalog.venues[0].coordinate = .init(latitude: -6.191242, longitude: 106.675692)
    let repository = try pocketTestRepository(catalog: catalog)
    let input = pocketTestInput(catalog, count: 1)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(job.result?.proposal?.stops.count == 1)
    #expect(job.result?.proposal?.unscheduledPlaces?.isEmpty == true)
}

@Test func pocketTravelArrivalAndVisitStartKeepWaitingSeparate() async throws {
    let catalog = try PocketIntegrationFixture.catalog(), repository = try pocketTestRepository(catalog: catalog)
    var input = pocketTestInput(catalog)
    input.enginePreferences?.maximumWaitMinutes = 15
    input.places[0].preferredAfter = input.startsAt.addingTimeInterval(10 * 60)
    input.places[0].visitTiming = .required
    input.firstPlaceID = input.places[0].id
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .plan, input: input))
    let stop = try #require(job.result?.proposal?.stops.first)
    #expect(stop.travelSeconds == 120)
    #expect(stop.arrivalAt == input.startsAt.addingTimeInterval(120))
    #expect(stop.visitStartsAt == input.startsAt.addingTimeInterval(600))
    #expect((try #require(stop.departureAt)).timeIntervalSince(stop.visitStartsAt!) == 2700)
}

@Test func firstPocketItineraryKeepsLargeSelectionAndSavesOnlyVerifiedStops() async throws {
    let catalog = try PocketIntegrationFixture.catalog(), counter = PocketCallCounter()
    let repository = try pocketTestRepository(catalog: catalog, counter: counter)
    var input = pocketTestInput(catalog, count: 6)
    let main = try #require(input.places.last)
    let unknown = PlanningPlace(id: UUID(), name: "Unknown branch", location: main.location, visitSeconds: 2700)
    input.places.insert(unknown, at: 0)
    input.enginePreferences?.mainSpotID = main.id
    input.enginePreferences?.allowsAIProcessing = false

    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let proposal = try #require(job.result?.proposal)
    #expect(input.places.count == 7)
    #expect(job.originalInput == input)
    #expect(Set(proposal.stops.map(\.id)) == Set(input.places.dropFirst().map(\.id)))
    #expect(proposal.input.places.count == 6)
    #expect(proposal.stops.first(where: { $0.id == main.id })?.visitSeconds == 75 * 60)
    #expect(proposal.unscheduledPlaces == ["Unknown branch: Visit information is still unresolved after web research."])
    #expect(proposal.returnTravelSeconds == 120)
    #expect(await counter.routes <= 840)
    #expect(await counter.advice == 1)
    let trip = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
    #expect(trip.input == proposal.input)
    #expect(trip.plan.stops == proposal.stops)
}

@Test func firstPocketItineraryEnforcesVisitRulesAndUsesCustomEndPoint() async throws {
    var catalog = try PocketIntegrationFixture.catalog()
    catalog.venues[0].hours?.maximumVisitMinutes = 30
    catalog.venues[0].hours?.lastEntryMinute = 9 * 60 + 12
    catalog.venues[0].hours?.intervals = (1 ... 7).flatMap {
        [OpeningInterval(weekday: $0, startMinute: 9 * 60, endMinute: 10 * 60),
         OpeningInterval(weekday: $0, startMinute: 14 * 60, endMinute: 16 * 60)]
    }
    let tomorrow = PocketIntegrationFixture.input().startsAt
    catalog.venues[0].hours?.closedDates = [TripClock.day(tomorrow)]
    catalog.venues[1].hours?.reservationRequired = true
    let fixtureCatalog = catalog
    let end = PlanningPoint(latitude: -6.27, longitude: 106.81)
    let services = PocketPlanningServices(travel: { _, to, _, _ in .init(seconds: to.latitude == end.latitude ? 420 : 120, meters: 300) },
                                          weather: { _, _, _ in .init(maxRainChance: nil, summary: "Synthetic") },
                                          advise: { _ in .init(slotID: "S1", requestedModel: "cx/gpt-6-luna(max)", reportedModel: "gpt-6-luna(max)") },
                                          resolve: { input, _ in PocketIntegrationFixture.resolution(input, catalog: fixtureCatalog) })
    let repository = try PocketPlanningRepository(services: services, connection: PocketTestConnection(), storageURL: nil, synthetic: true)
    var input = pocketTestInput(catalog, count: 2)
    input.enginePreferences?.mainSpotID = input.places[0].id
    input.enginePreferences?.endPoint = end

    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let proposal = try #require(job.result?.proposal)
    let stop = try #require(proposal.stops.first)
    let visit = try #require(stop.visitStartsAt)
    #expect(proposal.stops.map(\.id) == [input.places[0].id])
    #expect(TripClock.day(visit) != TripClock.day(tomorrow))
    #expect(TripClock.calendar.component(.hour, from: visit) == 9)
    #expect(TripClock.calendar.component(.minute, from: visit) <= 12)
    #expect(stop.visitSeconds == 1800)
    #expect(proposal.returnTravelSeconds == 420)
    #expect(proposal.unscheduledPlaces?.first?.contains("reservation") == true)
}

@Test func firstPocketItineraryRejectsMissingReturnETAAndStopsWhenThrottled() async throws {
    let catalog = try PocketIntegrationFixture.catalog()
    let input = pocketTestInput(catalog, count: 1), counter = PocketCallCounter()
    let services = PocketPlanningServices(travel: { _, to, _, _ in
                                              await counter.route()
                                              if to.latitude == input.origin.latitude { throw TravelQuoteError.throttled }
                                              return .init(seconds: 120, meters: 300)
                                          },
                                          weather: { _, _, _ in .init(maxRainChance: nil, summary: "Synthetic") },
                                          advise: { _ in .init(slotID: "S1", requestedModel: "cx/gpt-6-luna(max)", reportedModel: "gpt-6-luna(max)") },
                                          resolve: { input, _ in PocketIntegrationFixture.resolution(input, catalog: catalog) })
    let repository = try PocketPlanningRepository(services: services, connection: PocketTestConnection(), storageURL: nil, synthetic: true)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(job.result?.proposal == nil)
    #expect(job.result?.candidates.isEmpty == true)
    #expect(job.result?.warnings.first?.contains("limited route requests") == true)
    #expect(await counter.routes == 2)
}

@Test func firstPocketItineraryDoesNotUseKnownConflictingCatalogHours() async throws {
    let catalog = try Catalog.bundled(), counter = PocketCallCounter()
    let venue = try #require(catalog.venues.first { $0.name == "Tebet Eco Park" })
    #expect(venue.hours?.conflictingSources?.count == 2)
    let repository = try pocketTestRepository(catalog: catalog, counter: counter)
    var input = PocketIntegrationFixture.input()
    input.places = [.init(id: PocketPlanningRepository.identity(venue.id), name: venue.name,
                          location: .init(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude),
                          visitSeconds: 2700)]
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(job.result?.proposal == nil)
    #expect(job.result?.warnings == ["Tebet Eco Park: Published opening hours disagree."])
    #expect(await counter.routes == 0)
}

@Test func firstPocketItineraryRejectsAnUnlistedSlotEvenIfItLooksLikeAnIndex() async throws {
    let catalog = try PocketIntegrationFixture.catalog()
    let repository = try pocketTestRepository(catalog: catalog, selection: "S01")
    await #expect(throws: PlanningError.invalidResponse) {
        try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: pocketTestInput(catalog, count: 1)))
    }
}

@Test func pocketNativeResponsesRequireTheActualReportedMaxEffort() throws {
    let requested = "cx/gpt-6-luna(max)"
    #expect(try PocketAdviceSelection(slotID: "S1", requestedModel: requested, reportedModel: "gpt-6-luna",
                                      reportedReasoningEffort: "max", providerProtocol: "responses").validated().reportedModel == "gpt-6-luna")
    for effort in [String?.none, "low", "high"] {
        #expect(throws: PlanningError.invalidResponse) {
            try PocketAdviceSelection(slotID: "S1", requestedModel: requested, reportedModel: "gpt-6-luna",
                                      reportedReasoningEffort: effort, providerProtocol: "responses").validated()
        }
    }
    #expect(throws: PlanningError.invalidResponse) {
        try PocketAdviceSelection(slotID: "S1", requestedModel: requested, reportedModel: "gpt-6-luna",
                                  reportedReasoningEffort: "max").validated()
    }
}
@Test func authenticatedAccountsUseSeparateLocalTripStores() throws {
    let first = UUID(), second = UUID()
    let firstURL = try PocketPlanningRepository.storageURL(for: first)
    #expect(firstURL == (try PocketPlanningRepository.storageURL(for: first)))
    #expect(firstURL != (try PocketPlanningRepository.storageURL(for: second)))
    #expect(firstURL != (try PocketPlanningRepository.defaultStorageURL()))
}
