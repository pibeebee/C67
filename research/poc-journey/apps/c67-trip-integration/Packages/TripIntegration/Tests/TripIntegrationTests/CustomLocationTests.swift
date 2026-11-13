import Foundation
import Testing
@testable import TripIntegration

@Suite("Custom origin and destination preferences", .serialized)
@MainActor struct CustomLocationTests {
    func setup() throws -> (IntegrationCatalog, IntegrationPipeline, Date, TripRequest) {
        let catalog = try IntegrationCatalog.load(includeBlokM: true)
        let now = max(BlokMExperiment.snapshotClock(catalog), try BuswayFeed.network().source.checkedAt.addingTimeInterval(1))
        var request = BlokMExperiment.request(now: now)
        request.useCityCatalog = true
        request.desiredCount = 1
        request.useEmbedding = false
        return (catalog, try BlokMReplay.pipeline(city: true, expanded: true), now, request)
    }
    @Test func combinedCatalogPreservesSourcedBranchBoundaries() throws {
        let (catalog, _, _, _) = try setup()
        #expect(catalog.quality.candidates.count == 26)
        #expect(catalog.candidate("cikini") != nil)
        #expect(catalog.candidate("bm08") != nil)
        #expect(catalog.region(for: "bm08") != nil)
        #expect(catalog.region(for: "cikini") == nil)
        try catalog.quality.validate(); try catalog.timing.validate()
    }
    @Test func areaFilterRestrictsProposalsAndKeepsRequiredConflictVisible() async throws {
        let (_, pipeline, now, base) = try setup()
        var request = base
        request.targetAreas = [.cikini]
        let review = try await pipeline.recommend(request, now: now)
        #expect(review.suggestions.filter(\.recommended).map(\.id) == ["cikini"])
        #expect(review.suggestions.filter(\.selectable).allSatisfy { TripArea.cikini.contains($0.id) })
        request.requiredCandidateIDs = ["bm08"]
        let conflict = try await pipeline.recommend(request, now: now)
        let required = try #require(conflict.suggestions.first { $0.id == "bm08" })
        #expect(required.required && !required.selectable)
        await #expect(throws: (any Error).self) { try await pipeline.prepare(conflict, selectedIDs: ["cikini"], now: now) }
    }
    @Test func multipleAreasAndUnavailableFactsNeverIntroduceOutsideVenues() async throws {
        let (_, pipeline, now, base) = try setup()
        var request = base
        request.targetAreas = [.tebet, .blokM]
        request.desiredCount = 6
        let review = try await pipeline.recommend(request, now: now)
        #expect(!review.suggestions.filter(\.recommended).isEmpty)
        #expect(review.suggestions.filter(\.recommended).allSatisfy { request.includesArea(candidateID: $0.id) })
        request.targetAreas = [.kemang]
        let empty = try await pipeline.recommend(request, now: now)
        #expect(empty.suggestions.filter(\.recommended).isEmpty)
    }
    @Test func confirmedTebetOriginAndCikiniSpotSurvivePlanningAndSerialization() async throws {
        let (_, pipeline, now, base) = try setup()
        var request = base
        request.originPin = BlokMReplay.origins.first { $0.name == "Tebet" }
        request.originQuery = "Tebet"
        request.targetAreas = [.cikini]
        request.requiredCandidateIDs = ["cikini"]
        request.transport = .automobile
        let review = try await pipeline.recommend(request, now: now)
        let prepared = try await pipeline.prepare(review, selectedIDs: ["cikini"], now: now)
        #expect(prepared.searchRequests == 1)
        #expect(prepared.locations.first { $0.id == "origin" }?.selected == request.originPin)
        let plan = try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: now)
        #expect(plan.feasible)
        #expect(plan.stops.map(\.id) == ["cikini"])
        #expect(plan.summary.contains("Return to Tebet"))
        let restored = try IntegrationJSON.decoder().decode(IntegratedPlan.self, from: IntegrationJSON.encoder().encode(plan))
        #expect(restored.request == request)
        try PlanAudit.validate(restored)
        var changed = restored
        changed.request.targetAreas = [.blokM]
        #expect(throws: (any Error).self) { try PlanAudit.validate(changed) }
    }
    @Test func senayanOriginCanProduceTJPlanToChosenBlokMSpot() async throws {
        let (_, pipeline, now, base) = try setup()
        var request = base
        request.originPin = BlokMReplay.origins.first { $0.name == "Senayan" }
        request.originQuery = "Senayan"
        request.targetAreas = [.blokM]
        request.requiredCandidateIDs = ["bm08"]
        request.transport = .transjakartaBRT
        let review = try await pipeline.recommend(request, now: now)
        let prepared = try await pipeline.prepare(review, selectedIDs: ["bm08"], now: now)
        let plan = try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: now)
        #expect(plan.feasible)
        #expect(plan.legs.contains { $0.busway?.ride != nil })
        #expect(plan.prepared.locations.first { $0.id == "origin" }?.selected == request.originPin)
        try PlanAudit.validate(plan)
    }
    @Test func invalidOriginAndDuplicateAreaAreRejected() throws {
        let (catalog, _, now, base) = try setup()
        var request = base
        request.originPin = .init(id: "outside", name: "Bandung", address: "Bandung", latitude: -6.9, longitude: 107.6)
        #expect(throws: (any Error).self) { try request.validate(catalog: catalog, now: now) }
        request.originPin = nil
        request.targetAreas = [.tebet, .tebet]
        #expect(throws: (any Error).self) { try request.validate(catalog: catalog, now: now) }
    }
    @Test func addressOriginRequiresExplicitChoiceAndUnknownDemoDoesNotInventGBK() async throws {
        let pin = PlacePin(id: "address", name: "Jalan Wijaya", address: "Jakarta Selatan", latitude: -6.25, longitude: 106.81)
        let review = PlaceIdentityPolicy.review(id: "origin", query: "alamat saya Wijaya Jakarta", words: ["alamat", "saya"], branch: nil, results: [pin])
        #expect(review.selected == nil && review.candidates == [pin])
        let results = try await ReplaySearch().search(query: "Unknown Jakarta place")
        #expect(results.isEmpty)
    }
    @Test func olderRequestJSONWithoutNewFieldsStillDecodes() throws {
        let (_, _, _, request) = try setup()
        var object = try #require(JSONSerialization.jsonObject(with: IntegrationJSON.encoder().encode(request)) as? [String: Any])
        object.removeValue(forKey: "originPin"); object.removeValue(forKey: "targetAreas")
        let restored = try IntegrationJSON.decoder().decode(TripRequest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.originPin == nil && restored.targetAreas == nil)
    }
}
