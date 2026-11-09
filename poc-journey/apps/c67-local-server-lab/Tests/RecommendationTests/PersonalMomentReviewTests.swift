import XCTest
import DynamicTripContracts
import DynamicTripEngine
import PlaceContextEngine
import RecommendationContracts
@testable import RecommendationEngine

@MainActor final class PersonalMomentReviewTests: XCTestCase {
    func testReviewChoosesOnlyOfferedPlanWithMatchingEvidence() async throws {
        let choices = try await fixture()
        var profile = PersonalProfile()
        profile.interests = [.outdoors]
        let valid = try client(evidenceID: "fixture-sunset")
        let (selected, review) = try await PersonalMomentReview.select(choices, profile: profile, llm: valid)
        XCTAssertEqual(selected.moment?.id, "fixture-sunset")
        XCTAssertEqual(review?.reasonCode, "sourced_sunset")
        XCTAssertEqual(review?.outcome, "llm_selected")
        XCTAssertEqual(valid.calls, 1)

        let invalid = try client(evidenceID: "unknown-source")
        let (safe, failedReview) = try await PersonalMomentReview.select(choices, profile: profile, llm: invalid)
        XCTAssertNil(safe.moment)
        XCTAssertEqual(failedReview?.selectedPlanID, "regular")
        XCTAssertEqual(failedReview?.outcome, "review_unavailable")

        let (unchanged, skipped) = try await PersonalMomentReview.select(
            .init(baseline: choices.baseline), profile: profile, llm: valid)
        XCTAssertNil(unchanged.moment)
        XCTAssertNil(skipped)
        XCTAssertEqual(valid.calls, 1, "A lone valid plan does not call the judge")
    }

    private func client(evidenceID: String) throws -> OpenRouterClient {
        try OpenRouterClient(key: "synthetic", model: OpenRouterClient.defaultModel, transport: { request in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            let input = try XCTUnwrap(messages.last?["content"])
            let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            let offered = try XCTUnwrap(decoded["plans"] as? [[String: Any]])
            XCTAssertEqual(offered.compactMap { $0["planID"] as? String }, ["regular", "moment"])
            XCTAssertEqual(offered.compactMap { $0["momentID"] as? String }, ["none", "fixture-sunset"])
            let model = try XCTUnwrap(body["model"] as? String)
            let decision = try JSONSerialization.data(withJSONObject: [
                "planID": "moment", "evidenceID": evidenceID, "reasonCode": "sourced_sunset"
            ])
            let data = try JSONSerialization.data(withJSONObject: [
                "model": model, "choices": [["finish_reason": "stop", "message": ["content": String(decoding: decision, as: UTF8.self)]]],
                "usage": ["cost": 0]
            ])
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (data, response)
        })
    }

    private func fixture() async throws -> DynamicPlanChoices {
        let experiment = try await ContextExperiments.run("dry")
        var alternate = experiment.output
        let first = try XCTUnwrap(alternate.itinerary.visits.first)
        alternate.itinerary.waitingSeconds += 300
        alternate.moment = .init(id: "fixture-sunset", placeID: first.placeID, start: first.visit.start,
                                 end: first.visit.end, minimumMinutes: 20, sourceName: "SYNTHETIC",
                                 sourceURL: URL(string: "https://example.invalid")!, forecastCheckedAt: experiment.now)
        return .init(baseline: experiment.output, alternative: alternate)
    }
}
