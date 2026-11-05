import Foundation
import XCTest

@testable import TripIntelligence

final class RecommendationTests: XCTestCase {
    func testDiscoverStartsWithoutTripOrPlaces() throws {
        let brief = RecommendationBriefV1(date: "2026-11-05")
        XCTAssertNoThrow(try brief.validate())
        XCTAssertTrue(brief.places.isEmpty)
    }
    func testOwnPlacesRequireAnExplicitSelection() {
        var brief = RecommendationBriefV1(date: "2026-11-05")
        brief.hasPlaces = true
        XCTAssertThrowsError(try brief.validate())
    }
    func testInvalidCalendarDateRejected() {
        var brief = RecommendationBriefV1(date: "2026-02-30")
        XCTAssertThrowsError(try brief.validate())
        brief.date = "2026-11-05"
        XCTAssertNoThrow(try brief.validate())
    }
    func testContradictoryAndDuplicateOwnPlacesRejected() {
        var brief = RecommendationExamples.brief(knownPlaces: true)
        brief.avoids = [.coffee]
        XCTAssertThrowsError(try brief.validate())
        brief.avoids = []
        brief.places.append(brief.places[0])
        XCTAssertThrowsError(try brief.validate())
    }
    func testOwnPlaceOutsideJakartaRejected() {
        var brief = RecommendationExamples.brief(knownPlaces: true)
        brief.places[0].place.latitude = 35
        XCTAssertThrowsError(try brief.validate())
    }
    func testCategoryDoesNotEstablishBudgetPopularityOrWalkingAccess() {
        var brief = RecommendationBriefV1()
        brief.spending = .under100k
        brief.destinations = .local
        brief.walking = .minimal
        XCTAssertTrue(brief.notices.contains { $0.contains("biaya belum") })
        XCTAssertTrue(brief.notices.contains { $0.contains("popularitas") })
        XCTAssertTrue(brief.notices.contains { $0.contains("tidak dihitung") })
    }
    func testParkingCategoryIsNotANaturePark() {
        var candidate = RecommendationExamples.places()[0]
        candidate.place.category = "MKPOICategoryParking"
        XCTAssertFalse(RecommendationRelevance.supportedActivities(candidate).contains(.nature))
        candidate.place.category = "MKPOICategoryPark"
        XCTAssertTrue(RecommendationRelevance.supportedActivities(candidate).contains(.nature))
    }
    func testGeneralActivityTimeIsExplicitlyTentative() throws {
        let c = RecommendationExamples.places()[0]
        let value = output(candidate: c, window: .morning, basis: .generalActivitySuggestion)
        let result = try RecommendationValidation.advice(Codec.text(value), candidate: c)
        XCTAssertEqual(result.timeBasis, .generalActivitySuggestion)
    }
    func testUnknownCannotCarrySpecificTime() throws {
        let c = RecommendationExamples.places()[0]
        XCTAssertThrowsError(
            try RecommendationValidation.advice(
                Codec.text(output(candidate: c, window: .morning, basis: .unknown)), candidate: c))
    }
    func testEvidenceFromAnotherPlaceRejected() throws {
        let c = RecommendationExamples.places()[0]
        var value = output(candidate: c)
        value.evidenceIDs = ["P1-info"]
        XCTAssertThrowsError(try RecommendationValidation.advice(Codec.text(value), candidate: c))
    }
    func testClaimedTimeFactsRequireActualTimeSource() throws {
        let c = RecommendationExamples.places().first { $0.id == "P1" }!
        XCTAssertThrowsError(
            try RecommendationValidation.advice(
                Codec.text(output(candidate: c, window: .morning, basis: .suppliedFacts)), candidate: c))
    }
    func testGeneralSuggestionAlsoRespectsKnownClosingTime() throws {
        let c = RecommendationExamples.places()[0]
        XCTAssertThrowsError(
            try RecommendationValidation.advice(
                Codec.text(output(candidate: c, window: .evening, basis: .generalActivitySuggestion)),
                candidate: c))
    }
    func testSinglePlaceSchemaRejectsAdditionalMutationField() throws {
        let c = RecommendationExamples.places()[0]
        var object =
            try JSONSerialization.jsonObject(with: Codec.encode(output(candidate: c))) as! [String: Any]
        object["apply"] = true
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        XCTAssertThrowsError(try RecommendationValidation.advice(raw, candidate: c))
    }
    func testExplanationRejectsUnknownSources() throws {
        let raw = try Codec.text(DiscoveryExplanation(summary: "Example", evidenceIDs: ["invented"]))
        XCTAssertThrowsError(
            try RecommendationValidation.explanation(
                raw, evidence: RecommendationExamples.places()[0].evidence))
    }
    func testDiscoveryFallbackNeverBecomesModelRecommendation() async throws {
        let run = try await RecommendationPipeline(
            model: FixtureModelEngine(), search: RecommendationFixtureSearch()
        ).run(brief: RecommendationExamples.brief())
        XCTAssertFalse(run.advice.isEmpty)
        XCTAssertTrue(run.selectedIDs.isEmpty)
        XCTAssertTrue(
            run.advice.allSatisfy {
                $0.source == "deterministic" && $0.advice.suitability == .insufficientData
            })
        XCTAssertFalse(run.routingPerformed)
        XCTAssertFalse(run.records.contains { $0.capability == .preferences })
    }
    func testOwnPlacesSurviveEvenIfModelIsUnavailable() async throws {
        let brief = RecommendationExamples.brief(knownPlaces: true)
        let run = try await RecommendationPipeline(
            model: FixtureModelEngine(), search: RecommendationFixtureSearch()
        ).run(brief: brief)
        XCTAssertEqual(run.selectedIDs, brief.places.map(\.id))
        XCTAssertEqual(run.advice.map(\.id), brief.places.map(\.id))
        XCTAssertTrue(run.search.queries.isEmpty)
    }
    func testNoMainCourseOrRouteIsInvented() async throws {
        let run = try await RecommendationPipeline(
            model: GoodAdviceModel(), search: RecommendationFixtureSearch()
        ).run(brief: RecommendationExamples.brief(knownPlaces: true))
        XCTAssertEqual(run.selectedIDs.count, 3)
        XCTAssertFalse(run.routingPerformed)
        XCTAssertTrue(
            run.records.allSatisfy { [.placeAdvice, .discoveryExplanation].contains($0.capability) })
    }
    func testModelAdviceUsesOnlyExistingCandidateAndCapturesRawOutput() async throws {
        let run = try await RecommendationPipeline(
            model: GoodAdviceModel(), search: RecommendationFixtureSearch()
        ).run(brief: RecommendationExamples.brief())
        XCTAssertEqual(run.selectedIDs.count, 2)
        XCTAssertTrue(Set(run.selectedIDs).isSubset(of: Set(run.search.candidates.map(\.id))))
        XCTAssertTrue(
            run.advice.filter { $0.source == "Foundation Models" }.allSatisfy {
                $0.record.rawOutput == $0.record.displayedOutput
            })
        XCTAssertTrue(
            run.advice.filter { $0.candidate.place.category == "museum" }.allSatisfy {
                !run.selectedIDs.contains($0.id)
            })
    }
    func testRejectedAdvicePreservesCandidateAsUnverified() async throws {
        let run = try await RecommendationPipeline(
            model: BadAdviceModel(), search: RecommendationFixtureSearch()
        ).run(brief: RecommendationExamples.brief())
        XCTAssertTrue(run.selectedIDs.isEmpty)
        XCTAssertTrue(
            run.advice.allSatisfy { !$0.record.rawOutput.isEmpty && $0.record.source == "deterministic" })
    }
    func testAlternativeRequestExcludesPreviousCandidates() async throws {
        var brief = RecommendationExamples.brief()
        brief.excludedIDs = ["A", "B", "C"]
        let run = try await RecommendationPipeline(
            model: FixtureModelEngine(), search: RecommendationFixtureSearch()
        ).run(brief: brief)
        XCTAssertTrue(Set(run.advice.map(\.id)).isDisjoint(with: Set(brief.excludedIDs)))
    }
    func testProfileAndHistoryAreSeparateAndRestore() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RecommendationStore(directory: url)
        var brief = RecommendationExamples.brief(knownPlaces: true)
        brief.text = "Trip-only text"
        brief.excludedIDs = ["old"]
        try await store.saveProfile(brief)
        let savedProfile = try await store.profile()
        let profile = try XCTUnwrap(savedProfile)
        XCTAssertFalse(profile.hasPlaces)
        XCTAssertTrue(profile.places.isEmpty)
        XCTAssertTrue(profile.text.isEmpty)
        XCTAssertTrue(profile.excludedIDs.isEmpty)
        let run = try await RecommendationPipeline(
            model: FixtureModelEngine(), search: RecommendationFixtureSearch()
        ).run(brief: brief)
        try await store.save(run)
        let restored = try await RecommendationStore(directory: url).runs()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].id, run.id)
        XCTAssertEqual(restored[0].brief, brief)
    }
    private func output(
        candidate: CandidateV1, window: VisitWindow = .any, basis: VisitTimeBasis = .unknown
    ) -> PlaceAdviceOutput {
        .init(
            suitability: .possible, reason: "Category may fit", window: window, timeBasis: basis,
            timeReason: "Tentative", evidenceIDs: [candidate.evidence[0].id], unknowns: ["price"])
    }
}
private struct GoodAdviceModel: ModelGenerating {
    func runtime() async -> ModelRuntime {
        .init(
            available: true, englishSupported: true, indonesianSupported: false,
            availability: "Test double", contextSize: 4096, model: "Injected test double, no inference")
    }
    func generate(_ request: GenerationRequest) async throws -> RawGeneration {
        let root = try JSONSerialization.jsonObject(with: Data(request.prompt.utf8)) as! [String: Any]
        if request.capability == .placeAdvice {
            let candidate = root["candidate"] as! [String: Any]
            let evidence = candidate["evidence"] as! [[String: Any]]
            return .init(
                raw: try Codec.text(
                    PlaceAdviceOutput(
                        suitability: .possible, reason: "Test category", timeReason: "Unknown",
                        evidenceIDs: [evidence[0]["id"] as! String], unknowns: [])), duration: 0)
        }
        let evidence = root["evidence"] as! [[String: Any]]
        return .init(
            raw: try Codec.text(
                DiscoveryExplanation(
                    summary: "Test-only summary without a route", evidenceIDs: [evidence[0]["id"] as! String])
            ), duration: 0)
    }
}
private struct BadAdviceModel: ModelGenerating {
    func runtime() async -> ModelRuntime {
        .init(
            available: true, englishSupported: true, indonesianSupported: false,
            availability: "Test double", contextSize: 4096)
    }
    func generate(_ request: GenerationRequest) async throws -> RawGeneration {
        .init(raw: "{\"apply\":true}", duration: 0)
    }
}
