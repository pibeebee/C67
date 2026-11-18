import Foundation
import Testing
import C67Domain
@testable import C67Data

@Suite("Hybrid v4.1 and v4.2 synthetic comparison", .serialized)
struct V42ComparisonTests {
    @Test func matchedScenarios() async throws {
        let anchor = ISO8601DateFormatter().date(from: "2026-11-30T12:00:00+07:00")!
        for scenario in ["tomorrow", "bestDay", "rollover"] {
            var input = try v41Input(count: 3)
            input.enginePreferences?.allowsAIProcessing = true
            input.enginePreferences?.usesLuna = true
            input.enginePreferences?.semanticAssistance = .whenNeeded
            input.enginePreferences?.timingAnchor = anchor
            if scenario == "rollover" {
                input.enginePreferences?.scheduleSource = .automatic
                input.enginePreferences?.usesAutomaticTripDate = true
                input.enginePreferences?.timingAnchor = ISO8601DateFormatter().date(from: "2026-11-30T23:55:00+07:00")!
            } else {
                input.enginePreferences?.scheduleSource = .timingAnswer
                input.enginePreferences?.tripTiming = scenario == "tomorrow" ? .tomorrow : .bestDay
            }
            for index in input.places.indices {
                input.places[index].name = "Synthetic place \(index + 1)"
                input.places[index].durationOverridden = false
                input.places[index].sourceID = "apple:comparison-\(index)"
            }
            for repetition in 0 ..< 5 {
                let methods: [PlanningOrderingMethod] = repetition.isMultiple(of: 2) ? [.hybridV41, .hybridV42] : [.hybridV42, .hybridV41]
                var observations: [PlanningOrderingMethod: ComparisonObservation] = [:]
                for method in methods {
                    var request = input
                    request.enginePreferences?.orderingMethod = method
                    let calls = V41Calls()
                    var services = v41Services(calls)
                    services.order = { input, _ in
                        try await Task.sleep(for: .milliseconds(40))
                        return try PocketIntegrationFixture.experience(input)
                    }
                    services.experience = { inputs, _ in
                        try await Task.sleep(for: .milliseconds(40))
                        return try inputs.map { try PocketIntegrationFixture.experience($0) }
                    }
                    let planner = V41ItineraryPlanner(services: services, hours: { _ in
                        try? await Task.sleep(for: .milliseconds(15))
                        return .init(status: "unavailable")
                    }, synthetic: true)
                    let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary,
                                          input: request, createdAt: request.enginePreferences?.timingAnchor ?? anchor)
                    let start = ContinuousClock.now
                    let result = try await planner.plan(job)
                    let elapsed = start.duration(to: .now)
                    let proposal = try #require(result.proposal)
                    observations[method] = .init(proposal: proposal, elapsed: elapsed)
                    print("COMPARISON scenario=\(scenario) repetition=\(repetition + 1) method=\(method.rawValue) elapsed=\(elapsed) model_calls=\(proposal.scheduleAssessment?.modelCalls ?? -1) route_calls=\(proposal.scheduleAssessment?.routeCalls ?? -1)")
                }
                let baseline = try #require(observations[.hybridV41]?.proposal)
                let updated = try #require(observations[.hybridV42]?.proposal)
                #expect(baseline.feasible == updated.feasible)
                #expect(baseline.input.startsAt == updated.input.startsAt)
                #expect(baseline.departureAt == updated.departureAt)
                #expect(baseline.finishesAt == updated.finishesAt)
                #expect(baseline.stops == updated.stops)
                #expect(baseline.rescheduledFromDate == updated.rescheduledFromDate)
                #expect(baseline.scheduleAssessment?.routeCalls == updated.scheduleAssessment?.routeCalls)
            }
        }
    }
}

private struct ComparisonObservation {
    let proposal: PlanProposal
    let elapsed: Duration
}
