import Foundation
import Testing
import C67Data
import C67Domain
import PocketEngine

/// Opt-in tests use actual HTTP/Luna; they never substitute venue facts or ETA.
@MainActor struct PocketLiveAcceptanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["C67_LIVE_ACCEPTANCE"] == "1"))
    func selectedPlacesAreResearchedBeforeNativeScheduling() async throws {
        let env = ProcessInfo.processInfo.environment
        let connection = LiveAcceptanceConnection(url: try #require(env["C67_LIVE_URL"]), token: try #require(env["C67_LIVE_READ_TOKEN"]))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try #require(env["C67_LIVE_INPUT"]?.data(using: .utf8))
        var input = try decoder.decode(PlanningInput.self, from: data)
        var options = PlanningPreferences(); options.allowsAIProcessing = true
        input.enginePreferences = options
        let repository = try PocketPlanningRepository(services: .live(connection: connection), connection: connection, storageURL: nil)
        let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
        let proposal = try #require(job.result?.proposal)
        #expect(job.originalInput == input)
        #expect(!proposal.synthetic)
        #expect(!proposal.stops.isEmpty)
        #expect(proposal.evidence.contains { $0.url != nil && !$0.synthetic })
        #expect(!(proposal.unscheduledPlaces ?? []).contains { $0.contains("Outside the areas") })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["C67_LIVE_ADVICE"] != nil))
    func nativeLunaAdviceTransport() async throws {
        let env = ProcessInfo.processInfo.environment
        let connection = LiveAcceptanceConnection(url: try #require(env["C67_LIVE_URL"]), token: try #require(env["C67_LIVE_READ_TOKEN"]))
        let data = try #require(env["C67_LIVE_ADVICE"]?.data(using: .utf8))
        let menu = try JSONDecoder().decode(VisitAdviceRequest.self, from: data)
        let answer = try await PocketResearchClient(connection: connection).advise(menu)
        #expect(menu.options.contains { $0.slotID == answer.slotID })
        #expect(answer.requestedModel == "cx/gpt-6-luna(max)")
        #expect(answer.reportedModel == "gpt-6-luna")
        #expect(answer.reportedReasoningEffort == "max")
        #expect(answer.providerProtocol == "responses")
        #expect(answer.explanation?.isEmpty == false)
        print("LIVE_LUNA_REASON \(answer.explanation ?? "")")
        print("LIVE_LUNA requested=\(answer.requestedModel) reported=\(answer.reportedModel) effort=\(answer.reportedReasoningEffort ?? "not reported") protocol=\(answer.providerProtocol ?? "not reported")")
    }
}

private struct LiveAcceptanceConnection: PocketConnectionProviding {
    let url: String
    let token: String
    func credentials() async -> PocketCredentials { .init(serverURL: url, token: token) }
    func update(serverURL: String, token: String) async throws { throw PlanningError.unavailable }
}
