import Foundation
import DynamicTripContracts
import PlaceContextEngine
import RecommendationContracts

struct MomentJudgeOption {
    let id: String
    let plan: DynamicPlanResponse
    var momentID: String? { plan.moment?.id }

    var payload: [String: Any] {
        let itinerary = plan.itinerary
        let day = itinerary.visits.first.map { ContextClock.calendar.startOfDay(for: $0.visit.start) }
        func minutesWIB(_ date: Date) -> Int {
            guard let day else { return 0 }
            return Int(date.timeIntervalSince(day) / 60)
        }
        var value: [String: Any] = [
            "planID": id, "momentID": momentID ?? "none",
            "visitOrder": itinerary.visits.map(\.placeID),
            "travelMinutes": itinerary.travelSeconds / 60, "waitingMinutes": itinerary.waitingSeconds / 60
        ]
        if let finish = itinerary.finish { value["finishMinuteWIB"] = minutesWIB(finish) }
        if let moment = plan.moment {
            value["moment"] = [
                "kind": "pre-sunset outdoor visit", "placeID": moment.placeID,
                "startMinuteWIB": minutesWIB(moment.start), "endMinuteWIB": minutesWIB(moment.end),
                "minimumMinutesCovered": moment.minimumMinutes, "source": moment.sourceURL.absoluteString
            ] as [String: Any]
        }
        return value
    }
}

struct MomentJudgeDecision: Decodable {
    let planID: String
    let evidenceID: String
    let reasonCode: String
}

struct MomentJudgeResult {
    let decision: MomentJudgeDecision
    let model: String
    let costUSD: Double
}

@MainActor enum PersonalMomentReview {
    static func select(_ choices: DynamicPlanChoices, profile: PersonalProfile,
                       llm: OpenRouterClient?) async throws -> (DynamicPlanResponse, MomentPlanReview?) {
        let baseline = choices.baseline
        guard let alternate = choices.alternative, let moment = alternate.moment,
              moment.matches(alternate.itinerary) else { return (baseline, nil) }
        let travelDelta = alternate.itinerary.travelSeconds - baseline.itinerary.travelSeconds
        let waitingDelta = alternate.itinerary.waitingSeconds - baseline.itinerary.waitingSeconds
        let began = ContinuousClock.now
        func report(_ outcome: String, _ id: String, result: MomentJudgeResult? = nil) -> MomentPlanReview {
            let elapsed = began.duration(to: .now).components
            return .init(outcome: outcome, selectedPlanID: id, model: result?.model,
                         seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                         extraTravelSeconds: travelDelta, extraWaitingSeconds: waitingDelta, costUSD: result?.costUSD,
                         reasonCode: result?.decision.reasonCode)
        }

        if travelDelta <= 0, waitingDelta <= 0 {
            return (alternate, report("same_or_lower_effort", "moment"))
        }
        guard let llm else { return (baseline, report("review_unavailable", "regular")) }
        do {
            let candidates = [MomentJudgeOption(id: "regular", plan: baseline), MomentJudgeOption(id: "moment", plan: alternate)]
            let result = try await llm.choosePlan(candidates, profile: profile, timeout: 10)
            let chosen = result.decision.planID == "moment" ? alternate : baseline
            return (chosen, report("llm_selected", result.decision.planID, result: result))
        } catch {
            try Task.checkCancellation()
            return (baseline, report("review_unavailable", "regular"))
        }
    }
}
