import Foundation

public protocol PlanningRepository: Sendable {
    var supportsOnDevicePlanning: Bool { get }
    var preferenceLabels: [PlanningPreferenceLabel] { get }
    func engineConnection() async -> PlanningConnection?
    func updateEngineConnection(serverURL: String, token: String) async throws
    func requestPlan(_ request: PlanningRequest) async throws -> PlanningJob
    func planningJob(id: UUID) async throws -> PlanningJob
    func resumePlanning() async throws -> PlanningJob?
    func applyProposal(jobID: UUID, expectedRevision: Int?, requestID: UUID) async throws -> PersonalPlanningTrip
    func personalTrips() async throws -> [PersonalPlanningTrip]
    func recordEvent(tripID: UUID, event: PlanningEvent) async throws -> PersonalPlanningTrip
}

public extension PlanningRepository {
    var supportsOnDevicePlanning: Bool { false }
    var preferenceLabels: [PlanningPreferenceLabel] { [] }
    func engineConnection() async -> PlanningConnection? { nil }
    func updateEngineConnection(serverURL: String, token: String) async throws { throw PlanningError.unavailable }
}
