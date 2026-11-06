import Foundation
import PreferenceLearning
import Testing

@testable import PreferenceQuality

actor TestEmbedding: PreferenceEmbedding {
    let fails: Bool
    let slow: Bool
    init(fails: Bool = false, slow: Bool = false) {
        self.fails = fails
        self.slow = slow
    }
    func metadata() async throws -> EmbeddingMetadata {
        if slow { try await Task.sleep(for: .milliseconds(100)) }
        if fails { throw PreferenceError.invalid("FAULT INJECTION: unavailable model") }
        return try JSONDecoder().decode(
            EmbeddingMetadata.self,
            from: Data(
                """
                {"model":"ENGINEERING_FIXTURE","revision":"fixture","artifactSHA256":"fixture","runtime":"fixture","dimensions":3}
                """.utf8))
    }
    func encode(_ text: String, query: Bool) async throws -> [Float] {
        try Task.checkCancellation()
        return [1, text.contains("reading") ? 1 : 0, text.contains("coffee") ? 1 : 0]
    }
}

struct QualityTests {
    let catalog = try! QualityCatalog.load()
    var now: Date { catalog.sources.map(\.checkedAt).max()!.addingTimeInterval(1) }
    @Test func allTwentyFourAuthoredGatesMatchExpectedIDs() throws {
        let cases = try QualityCase.load()
        #expect(cases.count == 24)
        for item in cases {
            let decisions = try QualityPipeline.decisions(
                profile: item.profile, catalog: catalog, now: now)
            #expect(
                Set(decisions.filter { $0.state == "eligible" }.map(\.id)) == Set(item.expectedEligible),
                "\(item.id)")
        }
    }
    @Test func allMethodsUseExactlyTheSameEligibleCandidateSet() async throws {
        let item = try #require(QualityCase.load().first { $0.id == "coffee-soft-reading" })
        let run = try await QualityPipeline(embedding: TestEmbedding()).run(
            profile: item.profile, catalog: catalog, now: now)
        #expect(run.status == "comparison_completed")
        #expect(Set(run.category.map(\.id)) == Set(run.semantic.map(\.id)))
        #expect(Set(run.category.map(\.id)) == Set(run.combined.map(\.id)))
        #expect(run.category.first?.id == "bdt-rbbj")
        #expect(run.combined.first?.id == "bdt-rbbj")
    }
    @Test func coffeeAndReadingNeverMergeSeparateRooms() throws {
        let item = try #require(QualityCase.load().first { $0.id == "coffee-reading" })
        let decisions = try QualityPipeline.decisions(profile: item.profile, catalog: catalog, now: now)
        #expect(decisions.first { $0.id == "bdt-silent" }?.state == "excluded")
        #expect(decisions.first { $0.id == "bdt-cafe" }?.state == "needs_check")
        #expect(decisions.first { $0.id == "newsroom" }?.state == "needs_check")
        #expect(decisions.first { $0.id == "bdt-rbbj" }?.state == "eligible")
    }
    @Test func expiredProgramAndSuspendedVenueCannotReenterViaEmbedding() async throws {
        var profile = QualityProfile()
        profile.prefer = [.art, .reading]
        let run = try await QualityPipeline(embedding: TestEmbedding()).run(
            profile: profile,
            catalog: catalog, now: now)
        for id in ["ashta-reading", "macan-cafe", "macan-gallery"] {
            #expect(!run.combined.contains { $0.id == id })
            #expect(run.decisions.first { $0.id == id }?.state == "blocked")
        }
    }
    @Test func unavailableModelRetainsExplicitCategoryFallback() async throws {
        var profile = QualityProfile()
        profile.must = [.coffee]
        let run = try await QualityPipeline(embedding: TestEmbedding(fails: true)).run(
            profile: profile, catalog: catalog, now: now)
        #expect(run.status == "category_fallback")
        #expect(!run.category.isEmpty && run.semantic.isEmpty && run.combined.isEmpty)
    }
    @Test func textNegationIsNotSilentlyAccepted() async throws {
        var profile = QualityProfile()
        profile.direction = "Saya mau baca tetapi tidak kopi"
        #expect(DirectionReview.propose(profile.direction, current: profile) == nil)
        let run = try await QualityPipeline(embedding: TestEmbedding()).run(
            profile: profile,
            catalog: catalog, now: now)
        #expect(run.status == "preference_review_required")
        #expect(run.category.isEmpty && run.semantic.isEmpty && run.combined.isEmpty)
    }
    @Test(arguments: ["Saya mau ngopi sambil membaca", "Coffee while reading books"])
    func boundedPositiveProposalRequiresExplicitAcceptance(_ text: String) throws {
        var current = QualityProfile()
        current.direction = text
        let proposed = try #require(DirectionReview.propose(text, current: current))
        #expect(proposed.must == [.coffee, .reading])
        #expect(proposed.directionConfirmed)
        #expect(!current.directionConfirmed && current.must.isEmpty)
    }
    @Test func unknownAvoidCannotBeCalledSatisfied() throws {
        var profile = QualityProfile()
        profile.must = [.coffee]
        profile.avoid = [.smokingArea]
        let decisions = try QualityPipeline.decisions(profile: profile, catalog: catalog, now: now)
        #expect(!decisions.contains { $0.state == "eligible" })
        #expect(decisions.first { $0.id == "newsroom" }?.state == "excluded")
        #expect(decisions.first { $0.id == "bdt-rbbj" }?.state == "needs_check")
    }
    @Test func likingOneFacetDoesNotLearnAllVenueAttributes() throws {
        var profile = QualityProfile()
        profile.likedID = "bdt-rbbj"
        profile.likedFeature = .reading
        #expect(profile.softFeatures == [.reading])
        #expect(!profile.softFeatures.contains(.coffee))
        #expect(!profile.softFeatures.contains(.wifi))
        try profile.validate(catalog: catalog)
    }
    @Test func explicitCorrectionOverridesEarlierLikedFacet() {
        var profile = QualityProfile()
        profile.likedID = "bdt-rbbj"
        profile.likedFeature = .reading
        profile.avoid = [.reading]
        #expect(!profile.softFeatures.contains(.reading))
    }
    @Test func unsupportedLikedFacetIsNotClaimedAsPersonalizedMatch() async throws {
        let item = try #require(QualityCase.load().first { $0.id == "like-art-facet" })
        let run = try await QualityPipeline(embedding: TestEmbedding()).run(
            profile: item.profile, catalog: catalog, now: now)
        #expect(run.status == "no_supported_preference")
        #expect(run.semantic.isEmpty && run.combined.isEmpty && run.embedding == nil)
    }
    @Test func jakartaDoesNotAccidentallyMatchArt() throws {
        let profile = QualityProfile()
        let result = try #require(DirectionReview.propose("ngopi di Jakarta", current: profile))
        #expect(result.must == [.coffee])
    }
    @Test func contradictedControlsAndUnsupportedLikeAreRejected() throws {
        var profile = QualityProfile()
        profile.must = [.coffee]
        profile.avoid = [.coffee]
        #expect(throws: (any Error).self) { try profile.validate(catalog: catalog) }
        profile = .init()
        profile.likedID = "bdt-silent"
        profile.likedFeature = .coffee
        #expect(throws: (any Error).self) { try profile.validate(catalog: catalog) }
    }
    @Test func unknownAndConflictingFactsNeverSatisfyMust() throws {
        var changed = catalog
        let index = changed.candidates.firstIndex { $0.id == "bdt-rbbj" }!
        let fact = changed.candidates[index].claims.firstIndex { $0.feature == .coffee }!
        changed.candidates[index].claims[fact].value = .conflict
        var profile = QualityProfile()
        profile.must = [.coffee, .reading]
        let decisions = try QualityPipeline.decisions(profile: profile, catalog: changed, now: now)
        #expect(decisions.first { $0.id == "bdt-rbbj" }?.state == "needs_check")
    }
    @Test func unlinkedOrDuplicateClaimsRejected() throws {
        var changed = catalog
        changed.candidates[0].claims[0].sourceIDs = ["invented"]
        #expect(throws: (any Error).self) { try changed.validate() }
        changed = catalog
        changed.candidates[0].claims.append(changed.candidates[0].claims[0])
        #expect(throws: (any Error).self) { try changed.validate() }
    }
    @Test func staleFactsLeaveNoVerifiedRanking() throws {
        let decisions = try QualityPipeline.decisions(
            profile: .init(), catalog: catalog,
            now: now.addingTimeInterval(8 * 86400))
        #expect(!decisions.contains { $0.state == "eligible" })
    }
    @Test func emptyProfileIsExplicitlyGeneral() async throws {
        let run = try await QualityPipeline(embedding: TestEmbedding()).run(
            profile: .init(), catalog: catalog, now: now)
        #expect(run.status == "general_not_personalized")
        #expect(run.embedding == nil && run.semantic.isEmpty)
    }
    @Test func permutationDoesNotChangeRankTies() async throws {
        var profile = QualityProfile()
        profile.must = [.coffee]
        var reverse = catalog
        reverse.candidates.reverse()
        let pipeline = QualityPipeline(embedding: TestEmbedding())
        let a = try await pipeline.run(profile: profile, catalog: catalog, now: now)
        let b = try await pipeline.run(profile: profile, catalog: reverse, now: now)
        #expect(a.category.map(\.id) == b.category.map(\.id))
        #expect(a.combined.map(\.id) == b.combined.map(\.id))
    }
    @Test func cancellationPropagatesInsteadOfReturningFallback() async throws {
        var profile = QualityProfile()
        profile.must = [.coffee]
        let fixed = profile
        let task = Task {
            try await QualityPipeline(embedding: TestEmbedding(slow: true)).run(
                profile: fixed, catalog: catalog, now: now)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func storageRecoversNeighborsAndPreservesInvalidFile() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = QualityStore(directory: path)
        let run = try await QualityPipeline(embedding: TestEmbedding()).run(
            profile: .init(), catalog: catalog, now: now)
        try await store.save(run)
        try await store.saveProfile(.init(), catalog: catalog)
        try Data("broken".utf8).write(to: path.appendingPathComponent("broken.json"))
        let saved = try await store.history()
        #expect(saved.runs.count == 1 && saved.unreadable == 1)
        #expect(try await store.profile(catalog: catalog) == QualityProfile())
        #expect(FileManager.default.fileExists(atPath: path.appendingPathComponent("broken.json").path))
        let folder = try await store.export(run)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("REPORT.md").path))
    }
}
