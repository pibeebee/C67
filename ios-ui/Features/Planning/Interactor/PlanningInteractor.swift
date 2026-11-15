import Foundation
import C67Domain

struct PlanningInteractor: Sendable {
    let repository: any PlanningRepository
    func request(_ value: PlanningRequest) async throws -> PlanningJob { try await repository.requestPlan(value) }
    func job(_ id: UUID) async throws -> PlanningJob { try await repository.planningJob(id: id) }
    func resume() async throws -> PlanningJob? { try await repository.resumePlanning() }
    func trips() async throws -> [PersonalPlanningTrip] { try await repository.personalTrips() }
    func rename(jobID: UUID, title: String) async throws -> PlanningJob { try await repository.renameProposal(jobID: jobID, title: title) }
    func updateExperienceRoute(jobID: UUID, orderedIDs: [UUID]?, departure: Date?) async throws -> PlanningJob {
        try await repository.updateExperienceRoute(jobID: jobID, orderedIDs: orderedIDs, departure: departure)
    }
    func refreshExperienceRoute(tripID: UUID) async throws -> PersonalPlanningTrip {
        try await repository.refreshExperienceRoute(tripID: tripID)
    }
    func apply(job: PlanningJob, requestID: UUID) async throws -> PersonalPlanningTrip {
        try await repository.applyProposal(jobID: job.id, expectedRevision: job.baseRevision, requestID: requestID)
    }
    func event(tripID: UUID, event: PlanningEvent) async throws -> PersonalPlanningTrip {
        try await repository.recordEvent(tripID: tripID, event: event)
    }
}
