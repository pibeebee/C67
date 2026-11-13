import Foundation
import XCTest

@testable import PreferenceLearning

final class LivePreferenceTests: XCTestCase {
    func testTextBuildsBoundedEnglishMapKitQueries() async throws {
        var p = LocalPreferenceProfile()
        p.text = "Saya ingin ngopi sambil membaca"
        let plan = try await PreferenceQueryPlanner.plan(profile: p, embedding: NeverEmbedding())
        XCTAssertEqual(Set(plan.choices.map(\.activity)), [.coffee, .reading])
        XCTAssertTrue(
            plan.choices.allSatisfy { $0.query.hasSuffix(", Jakarta") && $0.basis.contains("text") })
    }
    func testExplicitAndLikedActivitiesWinAndAvoidsExclude() async throws {
        var p = LocalPreferenceProfile()
        p.interests = [.coffee, .art]
        p.avoids = [.shopping]
        let seed = try PreferenceCatalog.load("mapkit-snapshot-v1").places.first {
            $0.tags.contains(.reading)
        }!
        p.setFeedback(.liked, for: seed, remember: true)
        let plan = try await PreferenceQueryPlanner.plan(profile: p, embedding: NeverEmbedding())
        XCTAssertEqual(plan.choices.count, 3)
        XCTAssertEqual(Set(plan.choices.map(\.activity)), [.coffee, .art, .reading])
    }
    func testPossibleNegationDoesNotBecomePositiveSearchIntent() async throws {
        var p = LocalPreferenceProfile()
        p.text = "Saya tidak suka kopi"
        p.avoids = [.coffee]
        let plan = try await PreferenceQueryPlanner.plan(profile: p, embedding: NeverEmbedding())
        XCTAssertFalse(plan.choices.contains { $0.activity == .coffee })
        XCTAssertTrue(plan.notices.contains { $0.contains("negation") })
    }
    func testSemanticPlanningFailureStillMakesGeneralSearch() async throws {
        var p = LocalPreferenceProfile()
        p.text = "A memorable experience"
        let plan = try await PreferenceQueryPlanner.plan(profile: p, embedding: NeverEmbedding())
        XCTAssertEqual(plan.choices.count, 3)
        XCTAssertTrue(plan.notices.contains { $0.contains("unavailable") })
    }
    func testNativeOnlyPlanningDoesNotCallEmbedding() async throws {
        var p = LocalPreferenceProfile()
        p.text = "A memorable experience"
        let plan = try await PreferenceQueryPlanner.plan(
            profile: p, embedding: CancelEmbedding(), useSemantic: false)
        XCTAssertEqual(plan.choices.count, 3)
    }
    func testRememberedLikeSurvivesCompletelyNewCandidateSetAndStorage() async throws {
        let c = try PreferenceCatalog.load("mapkit-snapshot-v1")
        let seed = c.places.first { $0.tags.contains(.coffee) }!
        var p = LocalPreferenceProfile()
        p.setFeedback(.liked, for: seed, remember: true)
        XCTAssertNoThrow(try p.validate(catalog: .liveEmpty))
        XCTAssertTrue(p.query(catalog: .liveEmpty).contains(seed.description))
        XCTAssertGreaterThan(p.learnedWeights(catalog: .liveEmpty)[.coffee] ?? 0, 0)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PreferenceStore(directory: dir)
        try await store.save(p, catalogID: "mapkit-live-v1")
        let restored = try await store.profile(catalogID: "mapkit-live-v1")
        XCTAssertEqual(p, restored)
        let plan = try await PreferenceQueryPlanner.plan(profile: restored, embedding: NeverEmbedding())
        XCTAssertTrue(plan.choices.contains { $0.activity == .coffee && $0.basis.contains("liked") })
    }
    func testChangingAndRemovingFeedbackKeepsOneIdentity() throws {
        let place = try PreferenceCatalog.load("mapkit-snapshot-v1").places[0]
        var p = LocalPreferenceProfile()
        p.setFeedback(.liked, for: place, remember: true)
        p.setFeedback(.liked, for: place, remember: true)
        XCTAssertEqual(p.rememberedPlaces?.count, 1)
        p.setFeedback(.disliked, for: place, remember: true)
        XCTAssertFalse(p.hasSignal)
        p.setFeedback(nil, for: place, remember: true)
        XCTAssertTrue(p.feedback.isEmpty)
        XCTAssertTrue(p.rememberedPlaces!.isEmpty)
    }
    func testOriginalProfileWithoutRememberedFieldDecodes() throws {
        let data = Data(#"{"schemaVersion":1,"text":"","interests":[],"avoids":[],"feedback":{}}"#.utf8)
        let p = try JSONDecoder().decode(LocalPreferenceProfile.self, from: data)
        XCTAssertNil(p.rememberedPlaces)
    }
    func testBoundaryAndDuplicateFilteringAndNoInventedAmenities() throws {
        var place = try PreferenceCatalog.load("mapkit-snapshot-v1").places[0]
        var duplicate = place
        duplicate.id = "different-id"
        var outside = place
        outside.id = "outside"
        outside.latitude = 35
        var fake = place
        fake.id = "fake"
        fake.synthetic = true
        XCTAssertEqual(PreferenceLiveFilter.clean([place, duplicate, outside, fake]).count, 1)
        XCTAssertTrue(
            PreferenceLiveFilter.tags(name: "Parking", category: "MKPOICategoryParking").isEmpty)
        XCTAssertFalse(
            PreferenceLiveFilter.tags(name: "Cafe Books", category: "MKPOICategoryCafe").contains(.quiet))
        place.id = "changed"
        XCTAssertEqual(PreferenceLiveFilter.clean([place], limit: 1).count, 1)
    }
    func testPartialProviderFailureRetainsFreshCandidatesAndErrors() async throws {
        var p = LocalPreferenceProfile()
        p.interests = [.coffee, .reading]
        let r = try await PreferenceDiscoveryPipeline(
            embedding: NeverEmbedding(), search: InjectedSearch(mode: .partial)
        ).run(profile: p)
        XCTAssertEqual(r.search?.errors.count, 1)
        XCTAssertFalse(r.catalog.places.isEmpty)
        XCTAssertEqual(r.status, "category_fallback")
        XCTAssertFalse(r.routingPerformed)
        XCTAssertTrue(r.catalog.places.allSatisfy { !$0.synthetic })
        XCTAssertTrue(
            r.catalog.places.allSatisfy { $0.tags.contains(.coffee) || $0.tags.contains(.reading) })
        XCTAssertGreaterThan(r.search?.unmatchedActivityCount ?? 0, 0)
    }
    func testProviderFailureIsNotSilentlyReplayed() async throws {
        var p = LocalPreferenceProfile()
        p.interests = [.coffee]
        let r = try await PreferenceDiscoveryPipeline(
            embedding: NeverEmbedding(), search: InjectedSearch(mode: .failure)
        ).run(profile: p)
        XCTAssertEqual(r.status, "search_failed")
        XCTAssertTrue(r.catalog.places.isEmpty)
        XCTAssertTrue(r.categoryRanking.isEmpty)
        XCTAssertEqual(r.search?.errors.count, 1)
    }
    func testEmptySearchIsDistinctFromFailure() async throws {
        var p = LocalPreferenceProfile()
        p.interests = [.coffee]
        let r = try await PreferenceDiscoveryPipeline(
            embedding: NeverEmbedding(), search: InjectedSearch(mode: .empty)
        ).run(profile: p)
        XCTAssertEqual(r.status, "search_empty")
        XCTAssertEqual(r.search?.errors, [])
    }
    func testProviderTimeoutIsRecorded() async throws {
        var p = LocalPreferenceProfile()
        p.interests = [.coffee]
        let r = try await PreferenceDiscoveryPipeline(
            embedding: NeverEmbedding(), search: InjectedSearch(mode: .slow), timeout: 0.01
        ).run(profile: p)
        XCTAssertEqual(r.status, "search_failed")
        XCTAssertTrue(r.search!.errors[0].contains("timeout"))
    }
    func testSearchCancellationPropagatesAndDoesNotReturnFallback() async throws {
        var p = LocalPreferenceProfile()
        p.interests = [.coffee]
        do {
            _ = try await PreferenceDiscoveryPipeline(
                embedding: NeverEmbedding(), search: InjectedSearch(mode: .cancel)
            ).run(profile: p)
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
}
private struct NeverEmbedding: PreferenceEmbedding {
    func metadata() async throws -> EmbeddingMetadata {
        throw PreferenceError.invalid("Model unavailable in test")
    }
    func encode(_ text: String, query: Bool) async throws -> [Float] {
        throw PreferenceError.invalid("Model unavailable in test")
    }
}
private struct CancelEmbedding: PreferenceEmbedding {
    func metadata() async throws -> EmbeddingMetadata { throw CancellationError() }
    func encode(_ text: String, query: Bool) async throws -> [Float] { throw CancellationError() }
}
private struct InjectedSearch: PreferencePlaceSearching {
    enum Mode: Sendable { case partial, failure, empty, slow, cancel }
    let mode: Mode
    let provider = "Injected test provider; not live MapKit"
    func lookup(_ query: String) async throws -> [PreferencePlace] {
        switch mode {
        case .failure: throw PreferenceError.invalid("Injected network error")
        case .empty: return []
        case .cancel: throw CancellationError()
        case .slow:
            try await Task.sleep(for: .seconds(1))
            return []
        case .partial:
            if query.contains("bookstore") { throw PreferenceError.invalid("Injected query failure") }
            return try PreferenceCatalog.load("mapkit-snapshot-v1").places
        }
    }
}
