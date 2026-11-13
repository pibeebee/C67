import Foundation
import XCTest

@testable import PreferenceLearning

final class PreferenceTests: XCTestCase {
    func testSemanticRankingUsesTheSameHardFilters() async throws {
        var p = LocalPreferenceProfile()
        p.interests = [.reading]
        p.avoids = [.lively]
        p.feedback = ["A": .liked, "C": .disliked]
        let r = try await PreferenceRanker(embedding: ConstantEmbedding()).compare(
            profile: p, catalog: .load())
        XCTAssertEqual(r.status, "semantic_completed")
        XCTAssertEqual(Set(r.categoryRanking.map(\.id)), Set(r.semanticRanking.map(\.id)))
        XCTAssertFalse(
            r.semanticRanking.contains { ["A", "C"].contains($0.id) || $0.place.tags.contains(.lively) })
    }
    func testNonFiniteEmbeddingCannotProduceRecommendations() async throws {
        var p = LocalPreferenceProfile()
        p.interests = [.coffee]
        let r = try await PreferenceRanker(embedding: ConstantEmbedding(invalid: true)).compare(
            profile: p, catalog: .load())
        XCTAssertEqual(r.status, "category_fallback")
        XCTAssertTrue(r.semanticRanking.isEmpty)
        XCTAssertFalse(r.error.isEmpty)
    }
    func testInputLimits() throws {
        var p = LocalPreferenceProfile()
        p.text = String(repeating: "a", count: 401)
        XCTAssertThrowsError(try p.validate(catalog: .load()))
        p.text = ""
        p.feedback = Dictionary(
            uniqueKeysWithValues: ["A", "B", "C", "D", "E", "F", "G"].map { ($0, PlaceFeedback.liked) })
        XCTAssertThrowsError(try p.validate(catalog: .load()))
    }
    func testColdStartIsNotClaimedPersonal() async throws {
        let run = try await PreferenceRanker(embedding: UnavailableEmbedding()).compare(
            profile: .init(), catalog: .load())
        XCTAssertEqual(run.status, "general_not_personalized")
        XCTAssertNil(run.embedding)
        XCTAssertTrue(run.semanticRanking.isEmpty)
    }
    func testExplicitAvoidOverridesLike() async throws {
        var profile = LocalPreferenceProfile()
        profile.feedback = ["A": .liked]
        profile.avoids = [.quiet]
        let run = try await PreferenceRanker(embedding: UnavailableEmbedding()).compare(
            profile: profile, catalog: .load())
        XCTAssertFalse(run.categoryRanking.contains { $0.place.tags.contains(.quiet) })
        XCTAssertNil(profile.learnedWeights(catalog: try .load())[.quiet])
    }
    func testFeedbackDoesNotInflateOnRepeatedChoice() throws {
        var p = LocalPreferenceProfile()
        p.feedback["A"] = .liked
        let first = p.learnedWeights(catalog: try .load())
        p.feedback["A"] = .liked
        XCTAssertEqual(first, p.learnedWeights(catalog: try .load()))
        p.feedback.removeValue(forKey: "A")
        XCTAssertTrue(p.learnedWeights(catalog: try .load()).isEmpty)
    }
    func testDislikeIsNotAGlobalCategoryAvoid() throws {
        var p = LocalPreferenceProfile()
        p.feedback["A"] = .disliked
        XCTAssertTrue(p.avoids.isEmpty)
        XCTAssertTrue(p.learnedWeights(catalog: try .load()).isEmpty)
    }
    func testLikedAndDislikedPlacesAreNotRecommendedAgain() async throws {
        var p = LocalPreferenceProfile()
        p.feedback = ["A": .liked, "B": .disliked]
        let r = try await PreferenceRanker(embedding: UnavailableEmbedding()).compare(
            profile: p, catalog: .load())
        XCTAssertFalse(r.categoryRanking.contains { ["A", "B"].contains($0.id) })
    }
    func testUnknownIDAndContradictionRejected() throws {
        var p = LocalPreferenceProfile()
        p.feedback = ["unknown": .liked]
        XCTAssertThrowsError(try p.validate(catalog: .load()))
        p.feedback = [:]
        p.interests = [.coffee]
        p.avoids = [.coffee]
        XCTAssertThrowsError(try p.validate(catalog: .load()))
    }
    func testCosineRejectsInvalidVectors() throws {
        XCTAssertThrowsError(try PreferenceRanker.cosine([.nan], [1]))
        XCTAssertThrowsError(try PreferenceRanker.cosine([0], [1]))
        XCTAssertThrowsError(try PreferenceRanker.cosine([1, 2], [1]))
        XCTAssertEqual(try PreferenceRanker.cosine([1, 0], [1, 0]), 1)
    }
    func testUnavailableModelIsExplicitCategoryFallback() async throws {
        var p = LocalPreferenceProfile()
        p.interests = [.coffee]
        let r = try await PreferenceRanker(embedding: UnavailableEmbedding()).compare(
            profile: p, catalog: .load())
        XCTAssertEqual(r.status, "category_fallback")
        XCTAssertFalse(r.error.isEmpty)
        XCTAssertTrue(r.semanticRanking.isEmpty)
        XCTAssertTrue(r.categoryRanking.first!.place.tags.contains(.coffee))
        XCTAssertFalse(r.routingPerformed)
    }
    func testCancellationDoesNotBecomeFallback() async throws {
        var p = LocalPreferenceProfile()
        p.interests = [.coffee]
        do {
            _ = try await PreferenceRanker(embedding: CancelledEmbedding()).compare(
                profile: p, catalog: .load())
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testTextNegationRequiresExplicitControls() {
        var p = LocalPreferenceProfile()
        p.text = "Saya tidak ingin tempat ramai"
        XCTAssertTrue(p.textNeedsAvoidControls)
        XCTAssertTrue(p.avoids.isEmpty)
    }
    func testSnapshotHasNoInventedQuietness() throws {
        let c = try PreferenceCatalog.load("mapkit-snapshot-v1")
        XCTAssertEqual(c.places.count, 10)
        XCTAssertTrue(
            c.places.allSatisfy {
                !$0.synthetic && !$0.tags.contains(.quiet) && $0.unknowns.contains("quietness")
            })
    }
    func testStorageRestoresAndPreservesMalformedHistory() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PreferenceStore(directory: url)
        var p = LocalPreferenceProfile()
        p.feedback = ["A": .liked]
        try await store.save(p, catalogID: "synthetic-v1")
        let saved = try await store.profile(catalogID: "synthetic-v1")
        XCTAssertEqual(p, saved)
        let run = try await PreferenceRanker(embedding: UnavailableEmbedding()).compare(
            profile: p, catalog: .load())
        try await store.save(run)
        try Data("bad".utf8).write(to: url.appendingPathComponent("run-corrupt.json"))
        let values = try await store.runs()
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.id, run.id)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.appendingPathComponent("run-corrupt.json").path))
    }
}
private struct ConstantEmbedding: PreferenceEmbedding {
    var invalid = false
    func metadata() async throws -> EmbeddingMetadata {
        .init(
            model: "test double", revision: "test", artifactSHA256: "none", runtime: "no inference",
            dimensions: 2)
    }
    func encode(_ text: String, query: Bool) async throws -> [Float] {
        invalid && !query ? [.nan, 0] : [1, 0]
    }
}
private struct UnavailableEmbedding: PreferenceEmbedding {
    func metadata() async throws -> EmbeddingMetadata {
        throw PreferenceError.invalid("Injected unavailable model")
    }
    func encode(_ text: String, query: Bool) async throws -> [Float] {
        throw PreferenceError.invalid("Not expected")
    }
}
private struct CancelledEmbedding: PreferenceEmbedding {
    func metadata() async throws -> EmbeddingMetadata { throw CancellationError() }
    func encode(_ text: String, query: Bool) async throws -> [Float] { throw CancellationError() }
}
