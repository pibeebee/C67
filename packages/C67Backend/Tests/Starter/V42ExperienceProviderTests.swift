import Foundation
import Testing
import C67Domain
@testable import C67Data

@Suite("Hybrid v4.2 experience providers")
struct V42ExperienceProviderTests {
    @Test func sameAdviceProducesSameVerifiedSchedule() async throws {
        let probe = ProviderProbe()
        let luna = try input(method: .hybridV42)
        var onDevice = luna
        onDevice.enginePreferences?.orderingMethod = .hybridV42FoundationModels
        onDevice.enginePreferences?.usesLuna = false
        let planner = makePlanner(probe)

        let remote = try #require(try await planner.plan(job(luna)).proposal)
        let local = try #require(try await planner.plan(job(onDevice)).proposal)

        #expect(await probe.methods == [.hybridV42, .hybridV42FoundationModels])
        #expect(remote.feasible && local.feasible)
        #expect(remote.input.startsAt == local.input.startsAt)
        #expect(remote.departureAt == local.departureAt)
        #expect(remote.finishesAt == local.finishesAt)
        #expect(remote.stops.map(\.id) == local.stops.map(\.id))
        #expect(remote.stops.map(\.arrivalAt) == local.stops.map(\.arrivalAt))
        #expect(remote.stops.map(\.visitSeconds) == local.stops.map(\.visitSeconds))
        #expect(local.stops.first?.visitSeconds == 45 * 60)
        #expect(local.stops.last?.visitSeconds == 60 * 60)
        #expect(remote.scheduleAssessment?.routeCalls == local.scheduleAssessment?.routeCalls)
        #expect(local.experiencePlan?.providerProtocol == "on_device")
        #expect(local.effectiveOrderingMethod == .hybridV42FoundationModels)
        #expect(local.scheduleAssessment?.modelCalls == 1)
        #expect(local.scheduleAssessment?.needsAccessConfirmation == true)
    }

    @Test func snapshotsStayWithTheirOwnProvider() async throws {
        let probe = ProviderProbe()
        let planner = makePlanner(probe)
        let retained = SnapshotProbe()
        var request = job(try input(method: .hybridV42))
        _ = try await planner.plan(request, retainBatch: { await retained.save($0) })
        let lunaSnapshots = await retained.values
        request.input.enginePreferences?.orderingMethod = .hybridV42FoundationModels
        _ = try await planner.plan(request, snapshots: lunaSnapshots, retainBatch: { await retained.save($0) })
        let foundationSnapshots = await retained.values
        let resumed = try await planner.plan(request, snapshots: foundationSnapshots)

        #expect(await probe.methods == [.hybridV42, .hybridV42FoundationModels])
        #expect(lunaSnapshots.first?.contextKey != foundationSnapshots.first?.contextKey)
        #expect(resumed.proposal?.experiencePlan?.providerProtocol == "on_device")
        #expect(resumed.proposal?.scheduleAssessment?.modelCalls == 0)
    }

    @Test func unavailableFoundationModelsNeverSwitchesToLuna() async throws {
        let probe = ProviderProbe(failOnDevice: true)
        let planner = makePlanner(probe)
        let request = try input(method: .hybridV42FoundationModels)
        await #expect(throws: PlanningError.failed("FOUNDATION_MODELS_UNAVAILABLE")) {
            try await planner.plan(job(request))
        }

        var manual = request
        manual.places[0].durationOverridden = true
        manual.enginePreferences?.semanticAssistance = .requested
        let proposal = try #require(try await planner.plan(job(manual)).proposal)
        #expect(await probe.methods == [.hybridV42FoundationModels, .hybridV42FoundationModels])
        #expect(proposal.experiencePlan == nil)
        #expect(proposal.stops.map(\.visitSeconds) == [3600, 3600])
        #expect(proposal.scheduleAssessment?.unresolved.contains { $0.code == "semantic_unavailable" } == true)
    }

    @Test func manualDurationsCanSkipBothProviders() async throws {
        let probe = ProviderProbe()
        let planner = makePlanner(probe)
        for method in [PlanningOrderingMethod.hybridV42, .hybridV42FoundationModels] {
            var manual = try input(method: method)
            manual.places[0].durationOverridden = true
            manual.enginePreferences?.semanticAssistance = .disabled
            let proposal = try #require(try await planner.plan(job(manual)).proposal)
            #expect(proposal.scheduleAssessment?.modelCalls == 0)
            #expect(proposal.experiencePlan == nil)
        }
        #expect(await probe.methods.isEmpty)
    }

    private func input(method: PlanningOrderingMethod) throws -> PlanningInput {
        var input = try v41Input()
        input.preservesPlaceOrder = true
        input.enginePreferences?.orderingMethod = method
        input.enginePreferences?.allowsAIProcessing = true
        input.enginePreferences?.usesLuna = method == .hybridV42
        input.enginePreferences?.semanticAssistance = .whenNeeded
        input.places[0].durationOverridden = false
        return input
    }

    private func makePlanner(_ probe: ProviderProbe) -> V41ItineraryPlanner {
        var services = v41Services(V41Calls(), model: false)
        services.experience = { inputs, _ in try await probe.respond(.hybridV42, to: inputs) }
        services.foundationExperience = { inputs, _ in try await probe.respond(.hybridV42FoundationModels, to: inputs) }
        return .init(services: services, hours: { _ in .init(status: "unavailable") }, synthetic: true)
    }

    private func job(_ input: PlanningInput) -> PlanningJob {
        .init(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: input.startsAt)
    }
}

private actor ProviderProbe {
    var methods: [PlanningOrderingMethod] = []
    let failOnDevice: Bool

    init(failOnDevice: Bool = false) { self.failOnDevice = failOnDevice }

    func respond(_ method: PlanningOrderingMethod, to inputs: [PlanningInput]) throws -> [PlanningExperiencePlan] {
        methods.append(method)
        if method == .hybridV42FoundationModels, failOnDevice { throw PlanningError.failed("FOUNDATION_MODELS_UNAVAILABLE") }
        return try inputs.map { input in
            var plan = try PocketIntegrationFixture.experience(input)
            if method == .hybridV42FoundationModels {
                plan.requestedModel = V42FoundationExperience.modelID
                plan.reportedModel = V42FoundationExperience.modelID
                plan.providerProtocol = "on_device"
            }
            return plan
        }
    }
}

private actor SnapshotProbe {
    var values: [PlanningSemanticSnapshot] = []
    func save(_ snapshots: [PlanningSemanticSnapshot]) { values = snapshots }
}

#if canImport(FoundationModels)
    @Suite("Foundation Models guided response mapping")
    struct V42FoundationResponseTests {
        @available(iOS 26, macOS 26, *)
        @Test func overridesBindOnlyToTheirDateAndPlace() throws {
            var today = try v41Input()
            today.enginePreferences?.orderingMethod = .hybridV42FoundationModels
            today.firstPlaceID = today.places.last?.id
            today.enginePreferences?.mainSpotID = today.places.first?.id
            var tomorrow = today
            tomorrow.startsAt = today.startsAt.addingTimeInterval(86400)
            tomorrow.finishBy = today.finishBy.addingTimeInterval(86400)
            let response = V42FoundationExperience.Batch(
                estimates: [.init(placeNumber: 2, estimate: estimate(nil)), .init(placeNumber: 1, estimate: estimate(30))],
                dateOverrides: [.init(dayNumber: 2, placeNumber: 1, estimate: estimate(60))]
            )
            let plans = try V42FoundationExperience.plans(for: [today, tomorrow], from: response)
            let first = try #require(today.places.first?.id)
            let second = try #require(today.places.last?.id)
            #expect(plans.map(\.candidateDate) == ["2026-11-30", "2026-12-01"])
            #expect(plans.map { $0.stop(first)?.duration?.suggestedSeconds } == [1800, 3600])
            #expect(plans.allSatisfy { $0.orderedIDs == [second, first] && $0.stop(first)?.role == "main" })
            #expect(plans.allSatisfy { $0.stop(second)?.duration == nil && $0.stop(second)?.durationUnknownReason != nil })
            #expect(plans.allSatisfy { $0.weatherSources.isEmpty && $0.solarWindows.isEmpty })
        }

        @available(iOS 26, macOS 26, *)
        @Test func duplicatePlacesForeignDaysAndInvertedDurationsAreRejected() throws {
            var input = try v41Input(count: 1)
            input.enginePreferences?.orderingMethod = .hybridV42FoundationModels
            let row = V42FoundationExperience.PlaceEstimate(placeNumber: 1, estimate: estimate(30))
            let unknownDay = V42FoundationExperience.DateOverride(dayNumber: 2, placeNumber: 1, estimate: estimate(60))
            var inverted = row
            inverted.estimate.duration?.maximumMinutes = 20
            for response: V42FoundationExperience.Batch in [
                .init(estimates: [row, row], dateOverrides: []),
                .init(estimates: [row], dateOverrides: [unknownDay]),
                .init(estimates: [inverted], dateOverrides: [])
            ] {
                #expect(throws: PlanningError.invalidResponse) {
                    try V42FoundationExperience.plans(for: [input], from: response)
                }
            }
        }

        @available(iOS 26, macOS 26, *)
        private func estimate(_ minutes: Int?) -> V42FoundationExperience.Estimate {
            .init(activity: "Consider a short visit", basis: .nameInference,
                  duration: minutes.map { .init(minimumMinutes: $0, maximumMinutes: $0) },
                  preferredDayPart: .afternoon, reason: "A synthetic activity suggestion")
        }
    }
#endif
