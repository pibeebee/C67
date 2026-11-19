import Foundation

public protocol PlanningRepository: Sendable {
    var requiresExternalAIConsent: Bool { get }
    var externalAIAvailable: Bool { get }
    func grantExternalAIConsent() async throws -> UUID
    func hasExternalAIConsent(_ id: UUID?) async -> Bool
    func withdrawExternalAIConsent() async throws
    var supportsOnDevicePlanning: Bool { get }
    var supportsPlanningCancellation: Bool { get }
    func cancelPlanning(id: UUID) async throws
    var supportsTripDeletion: Bool { get }
    var preferenceLabels: [PlanningPreferenceLabel] { get }
    func engineConnection() async -> PlanningConnection?
    func updateEngineConnection(serverURL: String, token: String) async throws
    func requestPlan(_ request: PlanningRequest) async throws -> PlanningJob
    func planningJob(id: UUID) async throws -> PlanningJob
    func checkPlanningJob(id: UUID) async throws -> PlanningJob
    func resumePlanning() async throws -> PlanningJob?
    func applyProposal(jobID: UUID, expectedRevision: Int?, requestID: UUID) async throws -> PersonalPlanningTrip
    func personalTrips() async throws -> [PersonalPlanningTrip]
    func deleteTrip(id: UUID, expectedRevision: Int) async throws
    func prepareStart(tripID: UUID, expectedRevision: Int) async throws -> PlanningStartPreparation?
    func recordEvent(tripID: UUID, event: PlanningEvent) async throws -> PersonalPlanningTrip
    func renameProposal(jobID: UUID, title: String) async throws -> PlanningJob
    func updateExperienceRoute(jobID: UUID, orderedIDs: [UUID]?, departure: Date?) async throws -> PlanningJob
    func refreshExperienceRoute(tripID: UUID) async throws -> PersonalPlanningTrip
    func openingHours(placeID: String) async -> PlanningHoursLookup
}

public extension PlanningRepository {
    var requiresExternalAIConsent: Bool { false }
    var externalAIAvailable: Bool { false }
    func grantExternalAIConsent() async throws -> UUID { throw PlanningError.unavailable }
    func hasExternalAIConsent(_ id: UUID?) async -> Bool { false }
    func withdrawExternalAIConsent() async throws { throw PlanningError.unavailable }
    func prepareStart(tripID _: UUID, expectedRevision _: Int) async throws -> PlanningStartPreparation? { nil }
    func checkPlanningJob(id: UUID) async throws -> PlanningJob { try await planningJob(id: id) }
    func openingHours(placeID _: String) async -> PlanningHoursLookup { .init(status: "unavailable") }
    var supportsOnDevicePlanning: Bool { false }
    var supportsTripDeletion: Bool { false }
    var supportsPlanningCancellation: Bool { false }
    func cancelPlanning(id _: UUID) async throws { throw PlanningError.unavailable }
    func deleteTrip(id: UUID, expectedRevision: Int) async throws { throw PlanningError.unavailable }
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
