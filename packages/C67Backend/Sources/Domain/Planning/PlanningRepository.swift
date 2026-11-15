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
    func renameProposal(jobID: UUID, title: String) async throws -> PlanningJob
    func updateExperienceRoute(jobID: UUID, orderedIDs: [UUID]?, departure: Date?) async throws -> PlanningJob
    func refreshExperienceRoute(tripID: UUID) async throws -> PersonalPlanningTrip
}

public extension PlanningRepository {
    var supportsOnDevicePlanning: Bool { false }
    var preferenceLabels: [PlanningPreferenceLabel] { [] }
    func engineConnection() async -> PlanningConnection? { nil }
    func updateEngineConnection(serverURL: String, token: String) async throws { throw PlanningError.unavailable }
    func renameProposal(jobID: UUID, title: String) async throws -> PlanningJob { throw PlanningError.unavailable }
    func updateExperienceRoute(jobID: UUID, orderedIDs: [UUID]?, departure: Date?) async throws -> PlanningJob { throw PlanningError.unavailable }
    func refreshExperienceRoute(tripID: UUID) async throws -> PersonalPlanningTrip { throw PlanningError.unavailable }
    func setExperienceDeparture(jobID: UUID, departure: Date) async throws -> PlanningJob {
        try await updateExperienceRoute(jobID: jobID, orderedIDs: nil, departure: departure)
    }
}
