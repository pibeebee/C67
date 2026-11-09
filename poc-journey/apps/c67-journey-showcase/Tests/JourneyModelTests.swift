import XCTest
import TripIntegration
import UIKit
@testable import C67JourneyShowcase

@MainActor final class JourneyModelTests: XCTestCase {
    private var folder: URL!
    private var model: JourneyModel!
    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("JourneyUnit-\(UUID())")
        model = JourneyModel(root: folder)
        await model.load()
        model.switchArea(city: false)
    }
    override func tearDown() async throws {
        model.cancel(); await model.flushDraft()
        try? FileManager.default.removeItem(at: folder)
    }
    private func settled() async throws {
        let end = Date.now.addingTimeInterval(20)
        while model.busy, Date.now < end { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
    }
    private func generateOne() async throws {
        model.newTrip(); model.switchArea(city: false)
        model.edit { input in input.desiredCount = 1; input.profile.prefer = [.coffee, .wifi] }
        model.advanceToPreferences(); model.recommend(); try await settled()
        XCTAssertEqual(model.selected, ["bm08"])
        model.verify(); try await settled()
        model.generate(); try await settled()
    }
    func testPersonalizedTJCanSaveRestoreExportAndRevise() async throws {
        try await generateOne()
        let plan = try XCTUnwrap(model.session.proposal)
        XCTAssertTrue(plan.feasible); XCTAssertEqual(plan.evidenceMode, "synthetic_replay")
        XCTAssertTrue(plan.legs.contains { $0.busway?.ride != nil })
        XCTAssertTrue(model.canApply)
        model.accept(); try await settled(); await model.flushDraft()
        XCTAssertEqual(model.session.accepted?.id, plan.id)
        model.export(plan); try await settled()
        XCTAssertEqual(model.exportURLs.count, 2)
        XCTAssertTrue(model.exportURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let restored = JourneyModel(root: folder); await restored.load()
        XCTAssertEqual(restored.session.accepted?.id, plan.id)
        let stop = try XCTUnwrap(plan.stops.first)
        model.extend(stop, in: plan); try await settled()
        XCTAssertEqual(model.selected, ["bm08"])
        model.verify(); try await settled(); model.generate(); try await settled()
        let revised = try XCTUnwrap(model.session.proposal)
        XCTAssertEqual(revised.baseAcceptedID, plan.id)
        XCTAssertEqual(revised.stops.first?.duration, 90)
        model.reject(); try await settled()
        XCTAssertEqual(model.session.accepted?.id, plan.id)
        XCTAssertNil(model.session.proposal)
        await restored.flushDraft()
    }
    func testDraftAndModeStorageRemainSeparate() async throws {
        model.newTrip(); model.edit { $0.desiredCount = 2; $0.profile.prefer = [.nature] }
        model.persist(); await model.flushDraft()
        let restored = JourneyModel(root: folder); await restored.load()
        XCTAssertEqual(restored.request.desiredCount, 2)
        XCTAssertTrue(restored.request.profile.prefer.contains(.nature))
        restored.resume(); XCTAssertEqual(restored.phase, .setup)
        await model.switchMode(.live)
        XCTAssertEqual(model.request.desiredCount, 3)
        XCTAssertFalse(model.request.profile.hasSignal)
        model.edit { $0.desiredCount = 5 }; await model.flushDraft()
        await model.switchMode(.demo)
        XCTAssertEqual(model.request.desiredCount, 2)
        XCTAssertTrue(model.request.profile.prefer.contains(.nature))
        await restored.flushDraft()
    }
    func testCancelledRecommendationCannotAdvanceFlow() async throws {
        model.newTrip(); model.advanceToPreferences()
        model.recommend(); model.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.phase, .preferences)
        XCTAssertNil(model.review); XCTAssertFalse(model.busy)
    }
    func testNewTripsKeepTheCurrentModesEmbeddingPolicy() async throws {
        model.newTrip()
        XCTAssertEqual(model.mode, .demo)
        XCTAssertFalse(model.request.useEmbedding)

        await model.switchMode(.live)
        model.newTrip()
        XCTAssertEqual(model.mode, .live)
        XCTAssertTrue(model.request.useEmbedding)
        await model.flushDraft()

        let restored = JourneyModel(root: folder)
        await restored.switchMode(.live)
        XCTAssertTrue(restored.request.useEmbedding)
        restored.newTrip()
        XCTAssertTrue(restored.request.useEmbedding)
        await restored.flushDraft()

        await model.switchMode(.demo)
        model.newTrip()
        XCTAssertFalse(model.request.useEmbedding)
    }
    func testRequiredPlaceTogglePreservesOtherSelections() async throws {
        model.recommend(); try await settled()
        let previous = model.selected
        let suggestion = try XCTUnwrap(model.review?.suggestions.first { previous.contains($0.id) })
        model.toggleRequired(suggestion)
        XCTAssertEqual(model.selected, previous)
        XCTAssertTrue(model.request.requiredCandidateIDs.contains(suggestion.id))
        XCTAssertEqual(model.review?.request, model.request)
        XCTAssertEqual(model.review?.suggestions.first { $0.id == suggestion.id }?.required, true)
    }
    func testImpossibleDeadlineProducesUnsaveableProposal() async throws {
        model.edit { input in
            input.requiredCandidateIDs = ["bm01"]; input.desiredCount = 1
            input.deadline = input.departure.addingTimeInterval(3600)
        }
        model.recommend(); try await settled(); model.verify(); try await settled(); model.generate(); try await settled()
        let plan = try XCTUnwrap(model.session.proposal)
        XCTAssertFalse(plan.feasible); XCTAssertFalse(model.canApply)
        model.accept(); XCTAssertNotNil(model.error)
        XCTAssertNil(model.session.accepted)
        XCTAssertEqual(plan.prepared.selectedIDs, ["bm01"])
    }
    func testUnknownRequiredAttributeProducesEmptySelection() async throws {
        model.edit { $0.profile.must = [.quietPolicy] }
        model.recommend(); try await settled()
        XCTAssertTrue(model.selected.isEmpty)
        XCTAssertEqual(model.review?.quality.status, "no_verified_match")
    }
    func testBrandFontIsBundledAndRegistered() {
        XCTAssertNotNil(UIFont(name: "Gabarito-Regular", size: 17))
    }
    func testBudgetAdjustmentPreservesChosenVenuesAndRequiresRecalculation() async throws {
        model.newTrip(); model.recommend(); try await settled()
        let selected = model.selected
        let deadline = model.request.deadline
        model.adjustTimeBudget(longerDay: true)
        XCTAssertEqual(model.selected, selected)
        XCTAssertEqual(model.request.deadline, deadline.addingTimeInterval(3600))
        XCTAssertNil(model.prepared); XCTAssertNil(model.review)
        model.recommend(); try await settled()
        XCTAssertEqual(model.selected, selected)
        model.adjustTimeBudget(longerDay: false)
        XCTAssertEqual(model.request.defaultDuration, 45)
        XCTAssertEqual(model.selected, selected)
    }
    func testCityCatalogChoiceSurvivesDraftReload() async throws {
        model.newTrip(); model.switchArea(city: true)
        XCTAssertNotNil(model.catalog.candidate("cikini"))
        model.edit { $0.desiredCount = 1; $0.requiredCandidateIDs = ["cikini"] }
        model.recommend(); try await settled()
        XCTAssertTrue(model.selected.contains("cikini"))
        await model.flushDraft()
        let restored = JourneyModel(root: folder); await restored.load()
        XCTAssertTrue(restored.request.useCityCatalog == true)
        XCTAssertNotNil(restored.catalog.candidate("cikini"))
        XCTAssertTrue(restored.selected.contains("cikini"))
        await restored.flushDraft()
    }
    func testOriginAreaAndMandatorySpotSurviveDraftAndProduceCustomTrip() async throws {
        model.newTrip(); model.switchArea(city: true)
        model.chooseOrigin(try XCTUnwrap(BlokMReplay.origins.first { $0.name == "Senayan" }))
        model.toggleArea(.blokM)
        model.toggleDesiredSpot("bm08")
        model.edit { $0.desiredCount = 1 }
        model.recommend(); try await settled()
        XCTAssertEqual(model.selected, ["bm08"])
        model.verify(); try await settled(); model.generate(); try await settled()
        let plan = try XCTUnwrap(model.plan)
        XCTAssertTrue(plan.feasible)
        XCTAssertEqual(plan.request.originQuery, "Senayan")
        XCTAssertEqual(plan.request.targetAreas, [.blokM])
        XCTAssertTrue(plan.legs.contains { $0.busway?.ride != nil })
        await model.flushDraft()
        let restored = JourneyModel(root: folder); await restored.load()
        XCTAssertEqual(restored.request, model.request)
        XCTAssertEqual(restored.prepared?.locations.first { $0.id == "origin" }?.selected, model.request.originPin)
        await restored.flushDraft()
    }
    func testOriginEditsClearPinAndCancelledSearchCannotApplyResults() async throws {
        model.chooseOrigin(BlokMReplay.origins[0])
        XCTAssertNotNil(model.request.originPin)
        model.setOriginQuery("Unknown location")
        XCTAssertNil(model.request.originPin)
        model.searchOrigin()
        XCTAssertTrue(model.originResults.isEmpty)
        XCTAssertNotNil(model.originSearchMessage)
        model.setOriginQuery("Tebet"); model.searchOrigin()
        XCTAssertEqual(model.originResults.first?.name, "Tebet")
        model.cancel()
        XCTAssertTrue(model.originResults.isEmpty)
    }

    func testLateOriginSearchCannotReplaceNewQueryOrConfirmedCoordinate() async throws {
        let search = LateOriginSearch()
        let other = JourneyModel(root: folder.appendingPathComponent("Search"), originSearch: search)
        await other.load(); await other.switchMode(.live)
        other.setOriginQuery("Old origin"); other.searchOrigin()
        try await Task.sleep(for: .milliseconds(20))
        other.setOriginQuery("New origin"); other.searchOrigin()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(other.originResults.map(\.name), ["New origin"])
        other.chooseOrigin(try XCTUnwrap(other.originResults.first))
        XCTAssertEqual(other.request.originPin?.name, "New origin")
        XCTAssertFalse(other.originSearching)
        other.cancel(); await other.flushDraft()
    }

}

@MainActor private final class LateOriginSearch: TripPlaceSearching {
    func cancel() {}
    func search(query: String) async throws -> [PlacePin] {
        // Deliberately emulate a provider that returns a late callback after cancellation.
        try? await Task.sleep(for: .milliseconds(query == "Old origin" ? 200 : 30))
        return [.init(id: query, name: query, address: "Jakarta", latitude: -6.22, longitude: 106.81)]
    }
}
