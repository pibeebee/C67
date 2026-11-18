import Foundation
import Testing
import C67Domain
@testable import C67Data

@Suite("Hybrid v4.2 dated experience")
struct V42PlanningTests {
    @Test func automaticRolloverUsesOneModelCallAndTheWinningDatesDuration() async throws {
        let anchor = ISO8601DateFormatter().date(from: "2026-11-30T23:55:00+07:00")!
        var input = try assistedInput(at: anchor)
        input.enginePreferences?.scheduleSource = .automatic
        input.enginePreferences?.usesAutomaticTripDate = true
        let probe = ExperienceProbe()
        let transport = makeServices(probe)
        let planner = V41ItineraryPlanner(services: transport, hours: { _ in .init(status: "unavailable") }, synthetic: true)

        let result = try await planner.plan(job(input, at: anchor))
        let proposal = try #require(result.proposal)
        #expect(await probe.batches == [["2026-11-30", "2026-12-01"]])
        #expect(proposal.scheduleAssessment?.modelCalls == 1)
        #expect(proposal.rescheduledFromDate != nil)
        #expect(proposal.experiencePlan?.candidateDate == "2026-12-01")
        #expect(proposal.stops.first?.visitSeconds == 50 * 60)
    }

    @Test func invalidBatchUsesIndependentlyValidatedDatedResults() async throws {
        let anchor = ISO8601DateFormatter().date(from: "2026-11-30T12:00:00+07:00")!
        var input = try assistedInput(at: anchor)
        input.enginePreferences?.scheduleSource = .timingAnswer
        input.enginePreferences?.tripTiming = .inAFewDays
        let probe = ExperienceProbe(rejectBatch: true)
        let planner = V41ItineraryPlanner(services: makeServices(probe), hours: { _ in .init(status: "unavailable") }, synthetic: true)

        let result = try await planner.plan(job(input, at: anchor))
        let proposal = try #require(result.proposal)
        #expect(await probe.batches == [["2026-12-02", "2026-12-03"], ["2026-12-02"], ["2026-12-03"]])
        #expect(proposal.scheduleAssessment?.modelCalls == 3)
        #expect(proposal.scheduleAssessment?.dates.allSatisfy { $0.completeCandidates > 0 } == true)
    }

    private func assistedInput(at anchor: Date) throws -> PlanningInput {
        var input = try v41Input(count: 1)
        input.enginePreferences?.orderingMethod = .hybridV42
        input.enginePreferences?.allowsAIProcessing = true
        input.enginePreferences?.usesLuna = true
        input.enginePreferences?.semanticAssistance = .whenNeeded
        input.enginePreferences?.timingAnchor = anchor
        input.places[0].durationOverridden = false
        return input
    }

    private func job(_ input: PlanningInput, at anchor: Date) -> PlanningJob {
        .init(id: UUID(), status: .running, purpose: .firstItinerary, input: input, tripID: nil,
              baseRevision: nil, result: nil, errorCode: nil, createdAt: anchor)
    }

    private func makeServices(_ probe: ExperienceProbe) -> PocketPlanningServices {
        var services = v41Services(V41Calls(), model: false)
        services.experience = { inputs, _ in try await probe.order(inputs) }
        return services
    }
}

private actor ExperienceProbe {
    let rejectBatch: Bool
    var batches: [[String]] = []

    init(rejectBatch: Bool = false) { self.rejectBatch = rejectBatch }

    func order(_ inputs: [PlanningInput]) throws -> [PlanningExperiencePlan] {
        batches.append(inputs.map(PocketOrderCodec.candidateDay))
        if rejectBatch, inputs.count > 1 { throw PlanningError.invalidResponse }
        return try inputs.map {
            var plan = try PocketIntegrationFixture.experience($0)
            let minutes = plan.candidateDate == "2026-12-01" ? 50 : 30
            plan.stops[0].duration?.minMinutes = minutes
            plan.stops[0].duration?.maxMinutes = minutes
            return plan
        }
    }
}
