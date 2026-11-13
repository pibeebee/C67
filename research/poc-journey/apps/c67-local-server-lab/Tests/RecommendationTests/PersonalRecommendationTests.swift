import Foundation
import XCTest
import PlaceContextEngine
import PlannerEngine
import DynamicTripEngine
import DynamicTripContracts
import RecommendationContracts
@testable import RecommendationEngine

@MainActor final class PersonalRecommendationTests: XCTestCase {
    private func profile() -> PersonalProfile { var p = PersonalProfile(); p.interests = [.coffee, .culture, .outdoors]; return p }
    private func context() -> PersonalTripContext {
        let day = ContextClock.calendar.startOfDay(for: Date()).addingTimeInterval(2 * 86400)
        return .init(area: "Gambir Jakarta", day: ContextClock.label(day))
    }
    private func service(_ llm: any RecommendationLLM)throws -> RecommendationService {
        let env = Dictionary(uniqueKeysWithValues: ["APPLE_TEAM_ID", "MAPS_KEY_ID", "MAPS_KEY_PATH", "WEATHER_KEY_ID", "WEATHER_KEY_PATH", "WEATHER_SERVICE_ID"].map{($0, "synthetic-only")})
        return RecommendationService(google: GooglePlacesClient(configuration: try PlacesConfiguration(apiKey: "synthetic-only")),
                                     apple: LabAppleREST(config: try .init(environment: env)), llm: llm)
    }
    private func prepared()throws -> PreparedRecommendation {
        try service(StubLLM()).startFixture(.init(profile: profile(), context: context()), scenario: "balanced")
    }
    private func decision(_ candidates: [PersonalCandidate]) -> LLMRecommendation {
        .init(items: candidates.map{.init(id: $0.id, reasonCodes: ["interest_match", $0.hoursState == "available" ? "hours_overlap" : "hours_unknown"], evidenceIDs: $0.evidence.map(\.id))})
    }
    func testCategoryPriorityCannotBeLearnedAcrossExplicitInterests()throws {
        var state = PersonalLearningState(); state.setExplicit(interests: [.coffee], pace: .balanced)
        let c = try prepared().candidates.first{$0.categories == [.culture]}!
        state.record(.init(recommendationID: UUID(), candidate: c, kind: .selected, context: context()))
        XCTAssertEqual(state.profile.interests, [.coffee]); XCTAssertTrue(state.profile.facetAffinity.isEmpty)
        var illegal = state.profile; illegal.facetAffinity["culture:museum"] = 0.5
        XCTAssertThrowsError(try illegal.validate())
    }
    func testPositiveEventsLearnSourcedFacetButSkipsDoNotMeanDislike()throws {
        var state = PersonalLearningState(); state.setExplicit(interests: [.coffee], pace: .relaxed)
        let c = try prepared().candidates.first{$0.categories == [.coffee]}!
        let event = PersonalInteraction(recommendationID: UUID(), candidate: c, kind: .selected, context: context())
        state.record(event); let previous = state.profile
        state.record(event); XCTAssertEqual(state.profile, previous)
        state.record(.init(recommendationID: UUID(), candidate: c, kind: .skipped, context: context()))
        XCTAssertEqual(state.profile, previous); XCTAssertGreaterThan(state.profile.facetAffinity.values.first ?? 0, 0)
        try state.profile.validate()
    }
    func testExplicitRemovalPurgesOnlyThatInterestFacets()throws {
        var s = PersonalLearningState(); s.profile = profile(); s.profile.facetAffinity = ["coffee:cafe": 0.5, "culture:museum": 0.5]
        s.setExplicit(interests: [.coffee], pace: .balanced)
        XCTAssertEqual(s.profile.facetAffinity, ["coffee:cafe": 0.5]); try s.profile.validate()
    }
    func testEvidenceValidatorRejectsHoursHallucinationAndForeignIDs()throws {
        let p = try prepared(); var d = decision(p.candidates)
        d.items[0].reasonCodes = ["hours_unknown"]
        XCTAssertThrowsError(try CandidatePolicy.validateAndDiversify(d, candidates: p.candidates, profile: profile()))
        d = decision(p.candidates); d.items[0].evidenceIDs = ["foreign:hours"]
        XCTAssertThrowsError(try CandidatePolicy.validateAndDiversify(d, candidates: p.candidates, profile: profile()))
        d = decision(p.candidates); d.items[0].id = "foreign"
        XCTAssertThrowsError(try CandidatePolicy.validateAndDiversify(d, candidates: p.candidates, profile: profile()))
    }
    func testDiversityDoesNotRequireInventingCandidates()throws {
        let p = try prepared(), rows = try CandidatePolicy.validateAndDiversify(decision(p.candidates), candidates: p.candidates, profile: profile(), limit: 3)
        XCTAssertEqual(rows.count, 3); XCTAssertEqual(Set(rows.flatMap{$0.candidate.categories}), Set(profile().interests))
        XCTAssertTrue(Set(rows.map(\.id)).isSubset(of: Set(p.candidates.map(\.id))))
    }
    func testUnknownHoursStayConditional()throws {
        let p = try service(StubLLM()).startFixture(.init(profile: profile(), context: context()), scenario: "unknown_hours")
        let rows = try CandidatePolicy.validateAndDiversify(decision(p.candidates), candidates: p.candidates, profile: profile())
        XCTAssertTrue(rows.contains{$0.candidate.hoursState == "unknown" && $0.candidate.hours.isEmpty && !$0.candidate.unknowns.isEmpty})
    }
    func testWithinInterestLearningCannotTakeOtherInterestsSlots()throws {
        let p = try prepared(), a = decision(p.candidates), b = LLMRecommendation(items: Array(a.items.reversed()))
        let left = try CandidatePolicy.validateAndDiversify(a, candidates: p.candidates, profile: profile(), limit: 4)
        let right = try CandidatePolicy.validateAndDiversify(b, candidates: p.candidates, profile: profile(), limit: 4)
        func counts(_ rows: [PersonalRecommendedPlace]) -> [PersonalInterest: Int] {
            Dictionary(grouping: rows.flatMap{$0.candidate.categories}, by: {$0}).mapValues(\.count)
        }
        XCTAssertEqual(counts(left), counts(right)); XCTAssertEqual(counts(left)[.coffee], 2)
        XCTAssertEqual(counts(left)[.culture], 1); XCTAssertEqual(counts(left)[.outdoors], 1)
    }
    func testEmptyProfileDoesNotInventAnExplicitInterest()throws {
        let c = try prepared().candidates, p = PersonalProfile()
        let d = LLMRecommendation(items: c.map{.init(id: $0.id, reasonCodes: ["hours_overlap"], evidenceIDs: [$0.id + ":hours"])})
        XCTAssertFalse(CandidatePolicy.allowedReasons(c[0], profile: p).contains("interest_match"))
        XCTAssertEqual(try CandidatePolicy.validateAndDiversify(d, candidates: c, profile: p).count, 6)
    }
    func testMissingAndRepeatedLLMJudgmentsRejected()throws {
        let p = try prepared(); var d = decision(p.candidates); d.items.removeLast()
        XCTAssertThrowsError(try CandidatePolicy.validateAndDiversify(d, candidates: p.candidates, profile: profile()))
        d = decision(p.candidates); d.items[1] = d.items[0]
        XCTAssertThrowsError(try CandidatePolicy.validateAndDiversify(d, candidates: p.candidates, profile: profile()))
    }
    func testLLMFailureCannotReturnCategoryFallback() async throws {
        let llm = StubLLM(); llm.fail = true; let s = try service(llm)
        let p = try s.startFixture(.init(profile: profile(), context: context()), scenario: "balanced")
        do { _ = try await s.complete(.init(id: p.id, profileRevision: p.profileRevision, scores: p.candidates.map{.init(id: $0.id, semanticScore: nil)}, embeddingStatus: "not_run", embeddingSeconds: 0)); XCTFail("Unexpected fallback") }
        catch { XCTAssertEqual(llm.calls, 1) }
    }
    func testStaleProfileAndForgedScoresRejectedBeforeLLM()async throws {
        let llm = StubLLM(), s = try service(llm), p = try s.startFixture(.init(profile: profile(), context: context()), scenario: "balanced")
        do { _ = try await s.complete(.init(id: p.id, profileRevision: p.profileRevision + 1, scores: [], embeddingStatus: "not_run", embeddingSeconds: 0)); XCTFail("Stale accepted") } catch {}
        do { _ = try await s.complete(.init(id: p.id, profileRevision: p.profileRevision, scores: [.init(id: "foreign", semanticScore: 0.5)], embeddingStatus: "not_run", embeddingSeconds: 0)); XCTFail("Foreign accepted") } catch {}
        XCTAssertEqual(llm.calls, 0)
    }
    func testBrowseKeepsIssuedStopsAndExhaustsOverlappingPages() async throws {
        let transport = PagedPlaces(), llm = StubLLM()
        let env = Dictionary(uniqueKeysWithValues: ["APPLE_TEAM_ID", "MAPS_KEY_ID", "MAPS_KEY_PATH", "WEATHER_KEY_ID", "WEATHER_KEY_PATH", "WEATHER_SERVICE_ID"].map{($0, "synthetic-only")})
        let service = RecommendationService(google: GooglePlacesClient(configuration: try .init(apiKey: "synthetic-only"), transport: transport),
                                            apple: LabAppleREST(config: try .init(environment: env)), llm: llm)
        let context = context()
        var profile = PersonalProfile(); profile.interests = [.coffee]
        func finish(_ prepared: PreparedRecommendation) async throws -> PersonalRecommendationResult {
            try await service.complete(.init(id: prepared.id, profileRevision: prepared.profileRevision,
                                             scores: prepared.candidates.map{.init(id: $0.id, semanticScore: nil)}, embeddingStatus: "controlled", embeddingSeconds: 0))
        }
        let first = try await finish(service.start(.init(profile: profile, context: context)))
        XCTAssertEqual(Set(first.places.map(\.id)), ["first-a", "first-b", "first-c"])
        XCTAssertEqual(first.hasMore, true)
        profile.revision += 1  // Learning signals can change while explicit preferences stay put.
        let next = try await finish(service.start(.init(profile: profile, context: context, continuationID: first.id)))
        XCTAssertEqual(Set(next.places.map(\.id)), ["next-a", "next-b"])
        XCTAssertEqual(transport.detailIDs.sorted(), ["first-a", "first-b", "first-c", "next-a", "next-b"])
        let page = try XCTUnwrap(transport.searches.last), initial = try XCTUnwrap(transport.searches.first)
        XCTAssertEqual(page["pageToken"] as? String, "page-2")
        XCTAssertEqual(page.filter{$0.key != "pageToken"} as NSDictionary, initial as NSDictionary)
        XCTAssertNoThrow(try service.authorize(recommendationID: next.id, profileRevision: next.profileRevision,
                                               placeIDs: ["first-a", "next-a"], context: context))
        XCTAssertThrowsError(try service.authorize(recommendationID: next.id, profileRevision: next.profileRevision,
                                                   placeIDs: ["first-a", "never-shown"], context: context))
        var changed = profile; changed.interests = [.reading]
        do {
            _ = try await service.start(.init(profile: changed, context: context, continuationID: next.id))
            XCTFail("A new interest must not reuse the old query cursor")
        } catch {}
        let empty = try await service.start(.init(profile: profile, context: context, continuationID: next.id))
        XCTAssertTrue(empty.candidates.isEmpty); XCTAssertEqual(empty.hasMore, false); XCTAssertEqual(llm.calls, 2)
        XCTAssertNoThrow(try service.authorize(recommendationID: next.id, profileRevision: next.profileRevision, placeIDs: ["first-a"], context: context))
    }
    func testFixtureProofCannotAuthorizeLivePlan()async throws {
        let s = try service(StubLLM()), p = try s.startFixture(.init(profile: profile(), context: context()), scenario: "balanced")
        let result = try await s.complete(.init(id: p.id, profileRevision: p.profileRevision, scores: p.candidates.map{.init(id: $0.id, semanticScore: nil)}, embeddingStatus: "not_run", embeddingSeconds: 0))
        XCTAssertThrowsError(try s.authorize(recommendationID: result.id, profileRevision: result.profileRevision, placeIDs: [result.places[0].id], context: result.context))
    }
    func testCroutonFallbackForUnavailableOrInvalidResults() async throws {
        let fixture = try prepared()
        for behavior in [ModelProbe.Primary.unavailable, .wrongEvidence, .valid] {
            let probe = ModelProbe(primary: behavior, candidates: fixture.candidates)
            let client = try OpenRouterClient(key: "synthetic-key", model: OpenRouterClient.defaultModel,
                                              fallbackModel: OpenRouterClient.defaultFallbackModel, transport: { try await probe.send($0) })
            let result = try await client.review(profile: profile(), context: context(), candidates: fixture.candidates,
                                                 scores: [], weather: "Synthetic weather unavailable", timeout: 5)
            let attempts = await probe.attempts
            XCTAssertEqual(attempts.map(\.model), behavior == .valid
                ? [OpenRouterClient.defaultModel] : [OpenRouterClient.defaultModel, OpenRouterClient.defaultFallbackModel])
            XCTAssertEqual(attempts.map(\.reasoningDisabled), behavior == .valid ? [false] : [false, true])
            XCTAssertTrue(attempts.allSatisfy(\.zeroPrice))
            XCTAssertEqual(client.calls, attempts.count)
            XCTAssertEqual(result.model, attempts.last?.model)
            XCTAssertEqual(result.costUSD, 0)
        }
    }

    func testPaidModelConfigurationRejected() {
        XCTAssertThrowsError(try OpenRouterClient(key: "synthetic-key", model: "paid/model"))
    }
    func testDistantOrNonfiniteAppleIdentityCannotBeConfirmed() {
        XCTAssertTrue(DynamicAppleCandidate.canConfirm(separation: 500))
        for distance in [501.0, 4720, Double.nan, Double.infinity, -1] { XCTAssertFalse(DynamicAppleCandidate.canConfirm(separation: distance)) }
    }
    func testNearbyDifferentBusinessIsNotSameVenue() {
        XCTAssertFalse(DynamicAppleCandidate.compatibleNames(google: "TOMORO COFFEE - STASIUN GAMBIR", apple: "Kompormie Gambir", address: "Stasiun Gambir, Jalan Medan Merdeka Timur, Gambir Jakarta"))
        XCTAssertTrue(DynamicAppleCandidate.compatibleNames(google: "Museum Prasasti Jakarta", apple: "Taman Prasasti Museum", address: "Jalan Tanah Abang I Gambir Jakarta"))
        XCTAssertTrue(DynamicAppleCandidate.compatibleNames(google: "Museum Nasional Indonesia", apple: "National Museum of Indonesia", address: "Jalan Medan Merdeka Barat Jakarta"))
        XCTAssertTrue(DynamicAppleCandidate.compatibleNames(google: "Kopi Kenangan - Stasiun Gambir Selatan", apple: "Kopi Kenangan Gambir", address: "Stasiun Gambir Jalan Medan Merdeka Timur Jakarta"))
    }
    func testOptionalPlacesCanBeOmittedWithoutLosingRequiredPlace()async throws {
        let fixture = try await ContextExperiments.run("dry")
        var input = fixture.input; input.deadline = input.departure.addingTimeInterval(3 * 3600); input.maxTravelCalls = 48
        let provider = FixedTravel(seconds: 900), required = Set(["museum"])
        let result = try await OptionalItineraryPlanner.plan(input, requiredIDs: required, provider: provider, now: fixture.now)
        XCTAssertTrue(required.isSubset(of: Set(result.visits.map(\.placeID))))
        XCTAssertLessThan(result.visits.count, 3); XCTAssertGreaterThanOrEqual(result.visits.count, 1)
        XCTAssertLessThanOrEqual(result.finish ?? .distantFuture, input.deadline)
        XCTAssertEqual(result.travelCalls, provider.calls); XCTAssertLessThanOrEqual(provider.calls, 48)
    }
    func testRequiredClosedPlaceNotSilentlyDropped()async throws {
        let fixture = try await ContextExperiments.run("closed"), provider = FixedTravel(seconds: 900)
        let result = try await OptionalItineraryPlanner.plan(fixture.input, requiredIDs: ["museum"], provider: provider, now: fixture.now)
        XCTAssertTrue(result.visits.isEmpty); XCTAssertEqual(provider.calls, 0)
    }
    func testOptionalSearchSharesActualETACap()async throws {
        let f = try await ContextExperiments.run("dry"), provider = FixedTravel(seconds: 900)
        var input = f.input; input.maxTravelCalls = 5
        let result = try await OptionalItineraryPlanner.plan(input, requiredIDs: ["museum"], provider: provider, now: f.now)
        XCTAssertLessThanOrEqual(provider.calls, 5); XCTAssertEqual(result.travelCalls, provider.calls)
        XCTAssertTrue(result.searchTruncated)
    }
}
private actor ModelProbe {
    enum Primary { case unavailable, wrongEvidence, valid }
    struct Attempt: Sendable {
        let model: String
        let reasoningDisabled: Bool
        let zeroPrice: Bool
    }

    private let primary: Primary
    private let candidates: [PersonalCandidate]
    private(set) var attempts: [Attempt] = []

    init(primary: Primary, candidates: [PersonalCandidate]) {
        self.primary = primary
        self.candidates = candidates
    }

    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let model = try XCTUnwrap(body["model"] as? String)
        let prices = (body["provider"] as? [String: Any])?["max_price"] as? [String: Int]
        attempts.append(.init(model: model,
                              reasoningDisabled: (body["reasoning"] as? [String: Bool])?["enabled"] == false,
                              zeroPrice: prices == ["prompt": 0, "completion": 0, "request": 0]))
        let first = attempts.count == 1
        let status = first && primary == .unavailable ? 429 : 200
        let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status,
                                                     httpVersion: nil, headerFields: nil))
        let decision = LLMRecommendation(items: candidates.map {
            .init(id: $0.id, reasonCodes: ["interest_match"],
                  evidenceIDs: first && primary == .wrongEvidence ? ["foreign:category"] : [$0.id + ":category"])
        })
        let content = String(decoding: try JSONEncoder().encode(decision), as: UTF8.self)
        let data = try JSONSerialization.data(withJSONObject: [
            "model": model, "choices": [["finish_reason": "stop", "message": ["content": content]]],
            "usage": ["cost": 0]
        ])
        return (data, response)
    }
}

@MainActor private final class PagedPlaces: PlacesHTTPTransport {
    var searches: [[String: Any]] = []
    var detailIDs: [String] = []
    func send(_ request: URLRequest) async throws -> PlacesHTTPResponse {
        let body: [String: Any]
        if request.httpMethod == "POST" {
            let input = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            searches.append(input)
            switch input["pageToken"] as? String {
            case nil: body = ["places": [["id": "first-a"], ["id": "first-b"], ["id": "first-c"]], "nextPageToken": "page-2"]
            case "page-2": body = ["places": [["id": "first-a"], ["id": "next-a"], ["id": "next-b"]], "nextPageToken": "page-3"]
            case "page-3": body = ["places": [["id": "first-b"], ["id": "next-b"]]]
            default: throw ContextError.response
            }
        } else {
            let id = try XCTUnwrap(request.url?.lastPathComponent)
            detailIDs.append(id)
            body = ["id": id, "displayName": ["text": "Synthetic café " + id], "location": ["latitude": -6.17, "longitude": 106.82],
                    "businessStatus": "OPERATIONAL", "types": ["cafe"], "utcOffsetMinutes": 420]
        }
        return .init(status: 200, data: try JSONSerialization.data(withJSONObject: body))
    }
}
@MainActor private final class StubLLM: RecommendationLLM {
    var fail = false; var calls = 0
    func review(profile: PersonalProfile, context: PersonalTripContext, candidates: [PersonalCandidate], scores: [LocalCandidateScore], weather: String, timeout: Double) async throws -> LLMReviewResult {
        calls += 1; if fail { throw ContextError.invalid("Synthetic provider failure") }
        return .init(decision: .init(items: candidates.map{.init(id: $0.id, reasonCodes: ["interest_match"], evidenceIDs: [$0.id + ":category"])}), seconds: 0, model: "synthetic:free", provider: "stub")
    }
}
@MainActor private final class FixedTravel: ContextTravelProvider {
    var calls = 0; let seconds: Double
    init(seconds: Double) { self.seconds = seconds }
    func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
        calls += 1; return .init(seconds: seconds, departure: departure, source: "synthetic-test")
    }
}
