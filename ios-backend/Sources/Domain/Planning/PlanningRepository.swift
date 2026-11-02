import Foundation

public protocol PlanningRepository: Sendable {
    func requestPlan(_ request: PlanningRequest) async throws -> PlanningJob
    func planningJob(id: UUID) async throws -> PlanningJob
    func resumePlanning() async throws -> PlanningJob?
    func applyProposal(jobID: UUID, expectedRevision: Int?, requestID: UUID) async throws -> PersonalPlanningTrip
    func personalTrips() async throws -> [PersonalPlanningTrip]
    func recordEvent(tripID: UUID, event: PlanningEvent) async throws -> PersonalPlanningTrip
}
