import Foundation
import C67Data
import C67Domain

actor TripFlowRepositoryStub: PlanningRepository {
    nonisolated let supportsOnDevicePlanning: Bool
    private let base: any PlanningRepository
    private var renameContinuation: CheckedContinuation<Void, Never>?
    private var holdsRename = false
    private(set) var renameCalls = 0
    private(set) var applyCalls = 0
    private(set) var renameStarted = false
    private var failing = false
    private var applyError: PlanningError?
    private var renameError: PlanningError?
    private var tripsError: PlanningError?
    private var eventError: PlanningError?
    private var deleteError: PlanningError?
    private var hours = PlanningHoursLookup(status: "unavailable")
    private(set) var lookedUpHoursIDs: [String] = []
    private var routeError: PlanningError?
    private var interruptsStatusRead = false
    private(set) var requests: [PlanningRequest] = []
    private(set) var statusReadIDs: [UUID] = []
    private(set) var routeJobIDs: [UUID] = []
    private(set) var appliedRequestIDs: [UUID] = []
    private(set) var recordedEvents: [PlanningEvent] = []
    private var delay: Duration?
    private var ignoresManualOrder = false
    private var dropsManualOrderFlag = false
    private(set) var started = false

    init(supportsOnDevicePlanning: Bool = false, base: any PlanningRepository = MockPlanningRepository()) {
        self.supportsOnDevicePlanning = supportsOnDevicePlanning
        self.base = base
    }

    func holdRename() { holdsRename = true }
    func releaseRename() { holdsRename = false; renameContinuation?.resume(); renameContinuation = nil }
    func renameProposal(jobID: UUID, title: String) async throws -> PlanningJob {
        renameCalls += 1; renameStarted = true
        if holdsRename { await withCheckedContinuation { renameContinuation = $0 } }
        if let renameError { throw renameError }
        return try await base.renameProposal(jobID: jobID, title: title)
    }

    func setApplyError(_ error: PlanningError?) { applyError = error }
    func setRenameError(_ error: PlanningError?) { renameError = error }
    func setTripsError(_ error: PlanningError?) { tripsError = error }
    func setDeleteError(_ error: PlanningError?) { deleteError = error }
    func deleteTrip(id: UUID, expectedRevision: Int) async throws {
        if let deleteError { throw deleteError }
        try await base.deleteTrip(id: id, expectedRevision: expectedRevision)
    }
    func setHours(_ result: PlanningHoursLookup) { hours = result }
    func openingHours(placeID: String) async -> PlanningHoursLookup {
        lookedUpHoursIDs.append(placeID)
        return hours
    }

    func setRouteError(_ error: PlanningError?) { routeError = error }
    func setInterruptsStatusRead(_ enabled: Bool) { interruptsStatusRead = enabled }
    func updateExperienceRoute(jobID: UUID, orderedIDs: [UUID]?, departure: Date?) async throws -> PlanningJob {
        routeJobIDs.append(jobID)
        if let routeError { throw routeError }
        return try await base.planningJob(id: jobID)
    }

    func setEventError(_ error: PlanningError?) { eventError = error }
    func setIgnoresManualOrder() { ignoresManualOrder = true }
    func setDropsManualOrderFlag() { dropsManualOrderFlag = true }
    func configure(failing: Bool, delay: Duration? = nil) { self.failing = failing; self.delay = delay }
    func requestPlan(_ request: PlanningRequest) async throws -> PlanningJob {
        requests.append(request)
        started = true
        if let delay { try await Task.sleep(for: delay) }
        if failing { throw PlanningError.unavailable }
        var job = try await base.requestPlan(request)
        if ignoresManualOrder, request.input.preservesPlaceOrder { job.result?.proposal?.stops.reverse() }
        if dropsManualOrderFlag {
            job.input.preservesPlaceOrder = false
            job.result?.proposal?.input.preservesPlaceOrder = false
        }
        if interruptsStatusRead { job.status = .running; job.result = nil }
        return job
    }
    func planningJob(id: UUID) async throws -> PlanningJob {
        statusReadIDs.append(id)
        if interruptsStatusRead { throw PlanningError.unavailable }
        return try await base.planningJob(id: id)
    }
    func resumePlanning() async throws -> PlanningJob? { try await base.resumePlanning() }
    func applyProposal(jobID: UUID, expectedRevision: Int?, requestID: UUID) async throws -> PersonalPlanningTrip {
        applyCalls += 1
        appliedRequestIDs.append(requestID)
        if let applyError { throw applyError }
        return try await base.applyProposal(jobID: jobID, expectedRevision: expectedRevision, requestID: requestID)
    }
    func personalTrips() async throws -> [PersonalPlanningTrip] {
        if let tripsError { throw tripsError }
        return try await base.personalTrips()
    }
    func recordEvent(tripID: UUID, event: PlanningEvent) async throws -> PersonalPlanningTrip {
        recordedEvents.append(event)
        if let eventError { throw eventError }
        return try await base.recordEvent(tripID: tripID, event: event)
    }
}
