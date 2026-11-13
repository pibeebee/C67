import Foundation
import PreferenceLearning
import Testing

@testable import PreferenceQuality

struct BenefitTests {
    let dataset = try! BenefitDataset.load()
    func item(_ id: String = "currency-paraphrase") -> BenefitCase {
        dataset.cases.first { $0.id == id }!
    }
    func run(_ id: String = "currency-paraphrase") async throws -> BenefitRun {
        try await BenefitPipeline(embedding: TestEmbedding()).run(
            item: item(id), dataset: dataset, now: dataset.snapshotClock)
    }
    @Test func datasetContainsProspectivePairedIntentsAndSafetyCases() throws {
        try dataset.validate()
        #expect(dataset.catalog.candidates.count == 19)
        #expect(Set(dataset.catalog.candidates.map(\.venueID)).count == 16)
        #expect(dataset.cases.count == 30)
        #expect(dataset.cases.filter { $0.family == "safety" }.count == 6)
        let pairs = Dictionary(grouping: dataset.cases.filter { $0.family != "safety" }, by: \.group)
        #expect(pairs.count == 12)
        #expect(pairs.values.allSatisfy { Set($0.map(\.family)) == Set(["literal", "paraphrase"]) })
    }
    @Test func allAuthoredGatesAndStatesAreIndependentOfMockSimilarity() async throws {
        for item in dataset.cases {
            let result = try await BenefitPipeline(embedding: TestEmbedding()).run(
                item: item, dataset: dataset, now: dataset.snapshotClock)
            #expect(result.gatePassed, "\(item.id)")
            #expect(result.status == item.expectedStatus, "\(item.id)")
            try BenefitPipeline.validate(result)
            #expect(result.rankings.allSatisfy { Set($0.rows.map(\.id)) == Set(item.expectedEligible) })
        }
    }
    @Test func bm25RewardsMatchedTermsAndNormalizesLength() {
        let values = BenefitScoring.bm25(
            query: "coffee",
            documents: ["coffee", "coffee " + String(repeating: "other ", count: 100), "books"])
        #expect(values[0] > values[1])
        #expect(values[1] > values[2])
        #expect(values[2] == 0)
    }
    @Test func lexicalNormalizationIsFixedAndNoSynonymExpansion() {
        #expect(BenefitScoring.tokens("THE café, and COFFEE!") == ["cafe", "coffee"])
        #expect(BenefitScoring.bm25(query: "seafarers", documents: ["maritime heritage"])[0] == 0)
        #expect(BenefitScoring.bm25(query: "", documents: ["coffee", "book"]) == [0, 0])
        #expect(BenefitScoring.bm25(query: "coffee", documents: []).isEmpty)
    }
    @Test func tieExpectationMatchesExhaustivePermutations() {
        let judgment: [String: BenefitJudgment] = [
            "a": .init(grade: 2, sourceIDs: [], reason: "test"),
            "b": .init(grade: 1, sourceIDs: [], reason: "test"),
        ]
        let permutations = [
            ["a", "b", "c"], ["a", "c", "b"], ["b", "a", "c"],
            ["b", "c", "a"], ["c", "a", "b"], ["c", "b", "a"],
        ]
        let mean = permutations.reduce(0.0) { total, ids in
            total + BenefitScoring.metrics(
                rows: ids.enumerated().map {
                    .init(id: $0.element, primary: Double(3 - $0.offset))
                }, judgments: judgment
            ).ndcgAt3 / 6
        }
        let actual = BenefitScoring.metrics(
            rows: ["a", "b", "c"].map {
                .init(id: $0, primary: 0)
            }, judgments: judgment)
        #expect(abs(actual.ndcgAt3 - mean) < 1e-12)
        #expect(abs(actual.precisionAt3 - 2.0 / 3) < 1e-12)
        #expect(abs(actual.topOneRelevance - 1) < 1e-12)
    }
    @Test func cutoffTiesIncludeCandidatesBeyondDisplayedTopThree() {
        let rows = ["a", "b", "c", "d"].map { BenefitRow(id: $0, primary: 0) }
        let qrel = ["d": BenefitJudgment(grade: 2, sourceIDs: [], reason: "test")]
        let expected: Double = (1 + 1 / log2(3.0) + 1 / log2(4.0)) / 4
        let result = BenefitScoring.metrics(rows: rows, judgments: qrel)
        #expect(abs(result.ndcgAt3 - expected) < 1e-12)
        #expect(abs(result.precisionAt3 - 0.25) < 1e-12)
        #expect(result.topOneRelevance == 0.5)
    }
    @Test func identityOrderingCannotChangeExpectedTieMetric() {
        let rows = ["a", "b", "c", "d"].map { BenefitRow(id: $0, primary: 0) }
        let a = BenefitScoring.metrics(
            rows: rows, judgments: ["a": .init(grade: 2, sourceIDs: [], reason: "test")])
        let d = BenefitScoring.metrics(
            rows: rows.reversed(), judgments: ["d": .init(grade: 2, sourceIDs: [], reason: "test")])
        #expect(a.ndcgAt3 == d.ndcgAt3)
    }
    @Test func namesAndAddressesAreAbsentFromPrimaryPassages() {
        for candidate in dataset.catalog.candidates {
            let masked = dataset.passage(candidate.id, maskNames: true)
            #expect(!masked.contains(candidate.name))
            #expect(!masked.contains(candidate.address))
            #expect(dataset.passage(candidate.id, maskNames: false).contains(candidate.name))
        }
    }
    @Test func missingOrForeignDescriptionProvenanceRejected() throws {
        var copy = dataset
        copy.documents[0].sourceIDs = ["benefit-bi-museum"]
        #expect(throws: (any Error).self) { try copy.validate() }
        copy = dataset
        copy.documents.removeLast()
        #expect(throws: (any Error).self) { try copy.validate() }
    }
    @Test func judgmentsMustCiteTheRelevantVenueSource() throws {
        var copy = dataset
        copy.cases[0].judgments["bi"]?.sourceIDs = ["benefit-bdt-faq"]
        #expect(throws: (any Error).self) { try copy.validate() }
    }
    @Test func categoryAndLexicalDoNotRequireEmbedding() async throws {
        let result = try await BenefitPipeline(embedding: TestEmbedding(fails: true)).run(
            item: item(), dataset: dataset, useEmbedding: false, now: dataset.snapshotClock)
        #expect(result.status == "lexical_only")
        #expect(result.queryEncodes == 0 && result.documentEncodes == 0)
        #expect(result.embedding == nil && result.rankings.count == 2)
        try BenefitPipeline.validate(result)
    }
    @Test func failedModelKeepsCompetentLexicalFallback() async throws {
        let result = try await BenefitPipeline(embedding: TestEmbedding(fails: true)).run(
            item: item(), dataset: dataset, now: dataset.snapshotClock)
        #expect(result.status == "lexical_fallback")
        #expect(!result.error.isEmpty)
        #expect(Set(result.rankings.map(\.id)) == Set(["category", "lexical"]))
    }
    @Test func cancellationDoesNotBecomeModelFailure() async throws {
        let task = Task {
            try await BenefitPipeline(embedding: TestEmbedding(slow: true)).run(
                item: item(), dataset: dataset, now: dataset.snapshotClock)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func unconfirmedNegationNeverCallsEmbedding() async throws {
        let result = try await BenefitPipeline(embedding: TestEmbedding(fails: true)).run(
            item: item("safety-negation"), dataset: dataset, now: dataset.snapshotClock)
        #expect(result.status == "preference_review_required")
        #expect(result.rankings.isEmpty && result.queryEncodes == 0)
    }
    @Test func closuresExpiredProgramsAndUnknownsCannotBeRescuedByText() async throws {
        for id in ["safety-closure", "safety-expired", "safety-unknown", "safety-combination"] {
            let result = try await run(id)
            for ranking in result.rankings {
                #expect(
                    !ranking.rows.contains {
                        ["macan-gallery", "macan-cafe", "ashta-reading"].contains($0.id)
                    })
            }
            #expect(result.gatePassed)
        }
    }
    @Test func categorySignalIsRetainedByCategoryFirstTextMethods() async throws {
        let result = try await run("focused-study-paraphrase")
        for id in ["category", "lexical", "e5"] {
            #expect(result.rankings.first { $0.id == id }?.rows.first?.id == "bdt-silent")
        }
    }
    @Test func staleDataProducesNoFreshVerifiedMatches() async throws {
        let result = try await BenefitPipeline(embedding: TestEmbedding()).run(
            item: item(), dataset: dataset, now: dataset.snapshotClock.addingTimeInterval(8 * 86400))
        #expect(result.status == "no_verified_match")
        #expect(result.rankings.isEmpty && !result.gatePassed)
    }
    @Test func persistedRankingsCannotSmuggleUnverifiedIdentity() async throws {
        var result = try await run()
        result.rankings[0].rows[0].id = "macan-gallery"
        #expect(throws: (any Error).self) { try BenefitPipeline.validate(result) }
    }
    @Test func persistedMetricsAndStatesMustMatchActualRun() async throws {
        var result = try await run()
        result.rankings[0].metrics?.ndcgAt3 = 42
        #expect(throws: (any Error).self) { try BenefitPipeline.validate(result) }
        result = try await run()
        result.status = "general_not_personalized"
        #expect(throws: (any Error).self) { try BenefitPipeline.validate(result) }
    }
    @Test func historyRecoversAndConflictingIDsCannotOverwrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BenefitStore(directory: directory)
        let result = try await run()
        try await store.save(result)
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let restored = try await store.history()
        #expect(restored.runs.count == 1 && restored.unreadable == 1)
        var changed = result
        changed.createdAt = changed.createdAt.addingTimeInterval(1)
        await #expect(throws: (any Error).self) { try await store.save(changed) }
        #expect(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("broken.json").path))
        let exported = try await store.export(result)
        #expect(
            FileManager.default.fileExists(atPath: exported.appendingPathComponent("REPORT.md").path))
        let decoded = try BenefitCodec.decode(
            BenefitRun.self,
            data: Data(contentsOf: exported.appendingPathComponent("run.json")))
        #expect(decoded.id == result.id)
    }
}
