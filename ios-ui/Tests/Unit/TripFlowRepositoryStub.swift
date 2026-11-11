import Foundation
import C67Data
import C67Domain

actor TripFlowRepositoryStub: PlanningRepository {
    private let base = MockPlanningRepository()
    private var failing = false
    private var applyError: PlanningError?
    private var delay: Duration?
    private var ignoresManualOrder = false
    private var dropsManualOrderFlag = false
    private(set) var started = false

    func setApplyError(_ error: PlanningError?) { applyError = error }
    func setIgnoresManualOrder() { ignoresManualOrder = true }
    func setDropsManualOrderFlag() { dropsManualOrderFlag = true }
    func configure(failing: Bool, delay: Duration? = nil) { self.failing = failing; self.delay = delay }
    func requestPlan(_ request: PlanningRequest) async throws -> PlanningJob {
        started = true
        if let delay { try await Task.sleep(for: delay) }
        if failing { throw PlanningError.unavailable }
        var job = try await base.requestPlan(request)
        if ignoresManualOrder, request.input.preservesPlaceOrder { job.result?.proposal?.stops.reverse() }
        if dropsManualOrderFlag {
            job.input.preservesPlaceOrder = false
            job.result?.proposal?.input.preservesPlaceOrder = false
        }
        return job
    }
    func planningJob(id: UUID) async throws -> PlanningJob { try await base.planningJob(id: id) }
    func resumePlanning() async throws -> PlanningJob? { await base.resumePlanning() }
    func applyProposal(jobID: UUID, expectedRevision: Int?, requestID: UUID) async throws -> PersonalPlanningTrip {
        if let applyError { throw applyError }
        return try await base.applyProposal(jobID: jobID, expectedRevision: expectedRevision, requestID: requestID)
    }
    func personalTrips() async throws -> [PersonalPlanningTrip] { await base.personalTrips() }
    func recordEvent(tripID: UUID, event: PlanningEvent) async throws -> PersonalPlanningTrip {
        try await base.recordEvent(tripID: tripID, event: event)
    }
}
