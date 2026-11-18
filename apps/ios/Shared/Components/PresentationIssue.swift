import Foundation
import C67Domain

struct PresentationIssue {
    enum Scope: Hashable {
        case tripList, planning(UUID?), review, savedTrip(UUID), activity(UUID), account
    }

    enum Operation: Equatable {
        case loadTrips, plan(PlanningPurpose), changeRoute(order: [UUID]?, departure: Date?)
        case refreshSavedRoute, save(name: String?, startImmediately: Bool), delete
        case event(PlanningEventKind, extraSeconds: Int?)
        case account
    }

    enum Recovery: Equatable {
        case retry, checkStatus, regenerate, refreshTrip, signIn
        case editCredentials, requestLink, checkSession, wait
    }

    enum Cause: Equatable {
        case planning(PlanningError), authentication(AuthenticationError), pending, unexpected
    }

    enum Certainty {
        case final, unconfirmed
    }

    let scope: Scope
    let operation: Operation
    let cause: Cause
    let certainty: Certainty
    let message: String
    let recovery: Recovery?
    var jobID: UUID? = nil
    var stopID: UUID? = nil

    init(_ error: any Error, scope: Scope, operation: Operation, jobID: UUID? = nil, stopID: UUID? = nil) {
        self.scope = scope
        self.operation = operation
        self.jobID = jobID
        self.stopID = stopID
        let transportFailure = (error as? URLError).map { $0.code == .timedOut ? PlanningError.timedOut : .unavailable }
        guard let failure = (error as? PlanningError) ?? transportFailure else {
            cause = .unexpected
            certainty = .unconfirmed
            message = "The result couldn’t be confirmed. Try again when you’re connected."
            recovery = .retry
            return
        }
        cause = .planning(failure)
        certainty = [.unavailable, .timedOut, .invalidResponse].contains(failure) ? .unconfirmed : .final
        switch failure {
        case .authenticationRequired: recovery = .signIn
        case .expired: recovery = .regenerate
        case .revisionConflict: recovery = scope == .review ? .regenerate : .refreshTrip
        case .rateLimited, .failed("PROVIDER_RATE_LIMITED"), .failed("V4_ROUTE_THROTTLED"): recovery = .wait
        case .unavailable where jobID != nil, .timedOut where jobID != nil, .invalidResponse where jobID != nil:
            if case .plan = operation { recovery = .checkStatus } else { recovery = .retry }
        default: recovery = .retry
        }
        if failure == .configurationRequired || failure == .failed("PROVIDER_CONFIGURATION_REQUIRED") {
            message = "Planning isn’t available with the current connection."
        } else if recovery == .checkStatus {
            message = failure == .unavailable
                ? "The connection was interrupted. Check the same request when you’re back online."
                : "The request status couldn’t be confirmed. Check the same request again."
        } else {
            message = failure.localizedDescription
        }
    }

    init(rejectedOrder: [UUID], jobID: UUID) {
        scope = .review
        operation = .changeRoute(order: rejectedOrder, departure: nil)
        cause = .planning(.invalidInput)
        certainty = .final
        message = "The visits and travel don’t fit the schedule in this order. Your previous order is kept."
        recovery = nil
        self.jobID = jobID
    }

    init(pending scope: Scope, purpose: PlanningPurpose, jobID: UUID) {
        self.scope = scope
        operation = .plan(purpose)
        cause = .pending
        certainty = .unconfirmed
        message = "Your request is still running. Check its status when you’re ready."
        recovery = .checkStatus
        self.jobID = jobID
    }

    init(account error: any Error, checkingSession: Bool = false) {
        scope = .account
        operation = .account
        let failure = error as? AuthenticationError
        cause = failure.map(Cause.authentication) ?? .unexpected
        certainty = failure == nil || failure == .remoteSignOutFailed ? .unconfirmed : .final
        switch failure {
        case .invalidCredentials, .invalidEmail, .weakPassword, .passwordUnchanged: recovery = .editCredentials
        case .invalidCallback, .emailFlowExpired, .emailFlowUnavailable, .reauthenticationRequired, .emailNotConfirmed: recovery = .requestLink
        case .sessionExpired: recovery = .signIn
        case .rateLimited, .emailDeliveryFailed: recovery = .wait
        case .remoteSignOutFailed: recovery = nil
        default: recovery = checkingSession ? .checkSession : nil
        }
        switch failure {
        case .server, nil: message = "Account service is unavailable. Try again when you’re connected."
        default: message = failure?.localizedDescription ?? "The account action couldn’t be completed."
        }
    }
}
