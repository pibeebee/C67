import Foundation
import PreferenceLearning
import PreferenceQuality
import Testing
@testable import TripIntegration

@Suite("Blok M sourced recommendation and replay", .serialized)
@MainActor struct BlokMTests {
    func setup() throws -> (IntegrationCatalog, Date, TripRequest) {
        let catalog = try IntegrationCatalog.load(blokM: true)
        let now = BlokMExperiment.snapshotClock(catalog)
        return (catalog, now, BlokMExperiment.request(now: now))
    }

    @Test func historicalDefaultAndNewCatalogRemainSeparate() throws {
        let historical = try IntegrationCatalog.load()
        let (catalog, _, _) = try setup()
        #expect(historical.region == nil)
        #expect(historical.candidate("bm01") == nil)
        #expect(catalog.quality.candidates.count == 13)
        #expect(catalog.region?.anchors.count == 13)
        #expect(catalog.quality.sources.allSatisfy { $0.checkedAt <= BlokMExperiment.snapshotClock(catalog) })
    }

    @Test func parkHoursCannotTransferToLibraryOrBookStall() throws {
        let (catalog, now, request) = try setup()
        let park = try #require(try catalog.timingRun(candidateID: "bm01", request: request, now: now))
        #expect(!park.validStartRanges.isEmpty)
        for id in ["bm11", "bm12"] {
            let run = try #require(try catalog.timingRun(candidateID: id, request: request, now: now))
            #expect(run.validStartRanges.isEmpty)
        }
        #expect(catalog.candidate("bm10")?.value(.quietPolicy) == .unknown)
        #expect(catalog.candidate("bm11")?.value(.reading) == .unknown)
    }

    @Test func coffeeProfileChangesDisplayedRankingAgainstSameEligiblePool() async throws {
        let (catalog, now, base) = try setup()
        let pipeline = IntegrationPipeline(catalog: catalog)
        let general = try await pipeline.recommend(base, now: now)
        var request = base
        request.profile = BlokMExperiment.personas[1].profile
        let target = try await pipeline.recommend(request, now: now)
        let ids = target.suggestions.filter(\.recommended).map(\.id)
        #expect(ids.first == "bm08")
        #expect(ids.allSatisfy { catalog.candidate($0)?.value(.coffee) == .yes })
        #expect(BlokMExperiment.generalIDs(general: general, target: target) != ids)
        #expect(general.quality.status == "general_not_personalized")
    }

    @Test func unknownNoSmokingAndQuietPoliciesNeverBecomeVerifiedMatches() async throws {
        let (catalog, now, base) = try setup()
        let pipeline = IntegrationPipeline(catalog: catalog)
        var request = base
        request.profile = BlokMExperiment.personas[5].profile
        let avoid = try await pipeline.recommend(request, now: now)
        #expect(avoid.suggestions.filter(\.recommended).isEmpty)
        #expect(avoid.quality.status == "no_verified_match")
        request.profile = .init()
        request.profile.must = [.quietPolicy]
        let quiet = try await pipeline.recommend(request, now: now)
        #expect(quiet.suggestions.filter(\.recommended).isEmpty)
    }

    @Test func addingOnlyWifiChangesPreferenceOrderAndConfirmedParaphrasesKeepCategoryGates() async throws {
        let (catalog, now, base) = try setup()
        let pipeline = IntegrationPipeline(catalog: catalog)
        var request = base
        request.profile.prefer = [.coffee]
        let coffee = try await pipeline.recommend(request, now: now)
        request.profile.prefer.insert(.wifi)
        let wifi = try await pipeline.recommend(request, now: now)
        #expect(coffee.suggestions.filter(\.recommended).first?.id == "bm06")
        #expect(wifi.suggestions.filter(\.recommended).first?.id == "bm08")
        request.profile.direction = "Coffee and a place with Wi-Fi."
        request.profile.directionConfirmed = true
        let literal = try await pipeline.recommend(request, now: now)
        request.profile.direction = "I would like a coffee stop where internet access is listed."
        let paraphrase = try await pipeline.recommend(request, now: now)
        #expect(literal.suggestions.filter(\.recommended).map(\.id) == paraphrase.suggestions.filter(\.recommended).map(\.id))
        #expect(literal.quality.decisions.map(\.state) == paraphrase.quality.decisions.map(\.state))
    }

    @Test func generalComparatorRespectsTargetHardGatesAndExclusions() async throws {
        let (catalog, now, base) = try setup()
        let pipeline = IntegrationPipeline(catalog: catalog)
        let general = try await pipeline.recommend(base, now: now)
        var request = base
        request.profile.must = [.wifi]
        let target = try await pipeline.recommend(request, now: now)
        #expect(BlokMExperiment.generalIDs(general: general, target: target) == ["bm08"])
        request.profile.excludedIDs = ["bm08"]
        let excluded = try await pipeline.recommend(request, now: now)
        #expect(BlokMExperiment.generalIDs(general: general, target: excluded).isEmpty)
    }

    @Test func regionRejectsWrongBranchAndOutsideCatchment() throws {
        let (catalog, _, _) = try setup()
        let region = try #require(catalog.region)
        let pin = try #require(region.anchors.first { $0.candidateID == "bm08" }?.pin)
        #expect(region.contains(pin, candidateID: "bm08"))
        var wrong = pin
        wrong.latitude += 0.004
        #expect(!region.contains(wrong, candidateID: "bm08"))
        let review = PlaceIdentityPolicy.review(id: "bm08", query: "Titik Temu M Bloc", words: ["temu"], branch: nil,
                                                results: [wrong], region: region)
        #expect(review.candidates.isEmpty)
        wrong.latitude += 0.1
        #expect(!region.contains(wrong, candidateID: "bm08"))
    }

    @Test func realEnglishParkNameAndAmbiguityAreHandled() throws {
        let (catalog, _, _) = try setup()
        let candidate = try #require(catalog.candidate("bm01"))
        let pin = try #require(catalog.region?.anchors.first { $0.candidateID == "bm01" }?.pin)
        let review = PlaceIdentityPolicy.review(id: candidate.id, query: candidate.mapQuery,
                                                words: candidate.matchWords, branch: nil,
                                                results: [pin], region: catalog.region)
        #expect(review.selected?.id == pin.id)
        var duplicateName = pin
        duplicateName.id = "other-entrance"
        duplicateName.latitude += 0.0005
        let ambiguous = PlaceIdentityPolicy.review(id: candidate.id, query: candidate.mapQuery,
                                                   words: candidate.matchWords, branch: nil,
                                                   results: [pin, duplicateName], region: catalog.region)
        #expect(ambiguous.selected == nil)
    }

    @Test func freshSourceRequiredAndUnconfirmedDirectionBlocks() async throws {
        let (catalog, now, base) = try setup()
        let decisions = try QualityPipeline.decisions(profile: base.profile, catalog: catalog.quality,
                                                      now: now.addingTimeInterval(8 * 86400))
        #expect(decisions.allSatisfy { $0.state == "needs_check" })
        var request = base
        request.profile.direction = "Coffee without a smoking area."
        let review = try await IntegrationPipeline(catalog: catalog).recommend(request, now: now)
        #expect(review.quality.status == "preference_review_required")
        #expect(review.suggestions.filter(\.recommended).isEmpty)
    }

    @Test func embeddingFailureUsesExplicitCategoryFallbackWithIdenticalGates() async throws {
        let (catalog, now, base) = try setup()
        var request = base
        request.profile = BlokMExperiment.personas[1].profile
        request.useEmbedding = true
        let pipeline = IntegrationPipeline(catalog: catalog, quality: .init(embedding: UnavailableBlokMEmbedding()))
        let review = try await pipeline.recommend(request, now: now)
        #expect(review.quality.status == "category_fallback")
        #expect(review.quality.embedding == nil)
        #expect(review.suggestions.filter(\.recommended).map(\.id) == ["bm08", "bm06", "bm13"])
    }

    @Test func replayScalesFromOneToSixAndPreservesSelectedSet() async throws {
        let (_, now, base) = try setup()
        for ids in [["bm01"], ["bm01", "bm04", "bm08"], ["bm01", "bm02", "bm03", "bm05", "bm08", "bm13"]] {
            let pipeline = try BlokMReplay.pipeline()
            var request = base
            request.requiredCandidateIDs = ids
            request.desiredCount = ids.count
            let review = try await pipeline.recommend(request, now: now)
            let prepared = try await pipeline.prepare(review, selectedIDs: ids, now: now)
            let plan = try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: now)
            #expect(plan.feasible)
            #expect(plan.evidenceMode == "synthetic_replay")
            #expect(Set(plan.stops.map(\.id)) == Set(ids))
            #expect(prepared.searchRequests == ids.count + 1)
            #expect(plan.travelMinutes == Double((ids.count + 1) * 20))
            try PlanAudit.validate(plan)
        }
    }

    @Test func revisionRejectKeepsAcceptedVersionAndShortDeadlineCannotApply() async throws {
        let (_, now, base) = try setup()
        let pipeline = try BlokMReplay.pipeline()
        func plan(_ request: TripRequest, baseID: UUID? = nil) async throws -> IntegratedPlan {
            let review = try await pipeline.recommend(request, now: now)
            let prepared = try await pipeline.prepare(review, selectedIDs: request.requiredCandidateIDs, now: now)
            return try await pipeline.plan(prepared, review: review, baseAcceptedID: baseID, now: now)
        }
        var request = base
        request.requiredCandidateIDs = ["bm01"]
        var session = IntegrationSession()
        session.proposal = try await plan(request)
        try session.apply(now: now)
        let accepted = try #require(session.accepted)
        request.id = UUID()
        request.revision += 1
        request.durationByVenue["bm01"] = 90
        session.proposal = try await plan(request, baseID: accepted.id)
        #expect(session.proposal?.finish == accepted.finish?.addingTimeInterval(1800))
        session.proposal = nil
        #expect(session.accepted?.id == accepted.id)
        request.durationByVenue["bm01"] = 60
        request.deadline = request.departure.addingTimeInterval(5400)
        session.proposal = try await plan(request, baseID: accepted.id)
        #expect(session.proposal?.feasible == false)
        #expect(throws: (any Error).self) { try session.apply(now: now) }
        #expect(session.accepted?.id == accepted.id)
    }
}

private struct UnavailableBlokMEmbedding: PreferenceEmbedding {
    func metadata() async throws -> EmbeddingMetadata { throw IntegrationError.invalid("Injected missing model") }
    func encode(_ text: String, query: Bool) async throws -> [Float] { throw IntegrationError.invalid("Injected missing model") }
}
