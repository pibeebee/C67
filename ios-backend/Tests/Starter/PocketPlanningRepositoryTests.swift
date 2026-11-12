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
    let services = PocketPlanningServices(catalog: { catalog }, discover: { _, _ in [] },
                                          travel: { _, _, _, _ in await counter.route(); return .init(seconds: 120, meters: 500) },
                                          weather: { _, _, _ in .init(maxRainChance: nil, summary: "Synthetic weather unavailable") },
                                          advise: { _ in
                                              await counter.advised()
                                              return .init(slotID: selection, requestedModel: "cx/gpt-6-luna(max)", reportedModel: model)
                                          })
    return try PocketPlanningRepository(services: services, connection: PocketTestConnection(), storageURL: storageURL, synthetic: true)
}

@Test func pocketStructuredPreferencesDiscoverWithoutRequiredPlaceAndKeepTaxonomy() async throws {
    let catalog = try PocketIntegrationFixture.catalog(), repository = try pocketTestRepository(catalog: catalog)
    let input = pocketTestInput(catalog, count: 0)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .suggest, input: input))
    #expect(job.result?.candidates.count == 3)
    #expect(job.result?.candidates.allSatisfy { $0.categories.contains("japanese_cuisine") } == true)
    #expect(repository.preferenceLabels.count == 62)
    #expect(Set(repository.preferenceLabels.map(\.id)).count == 62)
    #expect(job.input.enginePreferences?.labels == ["japanese_cuisine"])
    #expect(job.result?.synthetic == true)
}

@Test func pocketUnknownRequiredEvidenceDoesNotBecomeARecommendation() async throws {
    let catalog = try PocketIntegrationFixture.catalog(), repository = try pocketTestRepository(catalog: catalog)
    var input = pocketTestInput(catalog, count: 0)
    input.enginePreferences?.conditions["quiet"] = .required
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .suggest, input: input))
    #expect(job.result?.candidates.isEmpty == true)
    #expect(job.result?.warnings.contains(where: { $0.contains("Fewer than three") }) == true)
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
    #expect(proposal.finishesAt.timeIntervalSince(input.startsAt) == 143 * 60)
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
    #expect(throws: (any Error).self) { try PocketCatalogClient.validatedURL("https://user:password@example.com") }
    #expect(throws: (any Error).self) { try PocketCatalogClient.validatedURL("http://example.com") }
    #expect(try PocketCatalogClient.validatedURL("https://example.com/pocket").host == "example.com")
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

@Test func pocketUnrepresentedInterestRequiresUserAdjustment() async throws {
    let catalog = try PocketIntegrationFixture.catalog(), repository = try pocketTestRepository(catalog: catalog)
    var input = pocketTestInput(catalog, count: 0)
    input.enginePreferences?.themes.insert("culture")
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .suggest, input: input))
    #expect(job.result?.candidates.isEmpty == true)
    #expect(job.result?.warnings.contains(where: { $0.contains("no interest was removed automatically") }) == true)
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
    #expect(stop.departureAt.timeIntervalSince(stop.visitStartsAt!) == 2700)
}
