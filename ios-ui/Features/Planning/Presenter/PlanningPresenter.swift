import Foundation
import Observation
import C67Domain

@MainActor @Observable
final class PlanningPresenter {
    var title = "My trip"
    var origin: PlanningPoint?
    var originLabel = "Choose a starting point"
    var places: [PlanningPlace] = []
    var preferences = ""
    var startsAt = Date().addingTimeInterval(600)
    var finishBy = Date().addingTimeInterval(4 * 3600 + 600)
    var timeZone = TimeZone.current.identifier
    var mode: PlanningMode = .walking
    private(set) var trips: [PersonalPlanningTrip] = []
    private(set) var job: PlanningJob?
    private(set) var isBusy = false
    private(set) var privateAccessBlocked = false
    private(set) var progress: String?
    var error: String?
    var openTripID: UUID?
    private let interactor: PlanningInteractor
    private var generation = 0
    private var sessionID: UUID?
    private var pendingRequest: PlanningRequest?
    private var pendingApply: (UUID, UUID)?
    private var pendingEvent: (UUID, PlanningEvent)?
    private var reportedPosition: (PlanningPoint, Date)?

    init(interactor: PlanningInteractor, initialInput: PlanningInput? = nil) {
        self.interactor = interactor
        if let initialInput { setDraft(initialInput); originLabel = "Synthetic starting point" }
    }
    private func setDraft(_ value: PlanningInput) {
        title = value.title; origin = value.origin; places = value.places; preferences = value.preferences
        startsAt = value.startsAt; finishBy = value.finishBy; timeZone = value.timeZone; mode = value.mode
    }
    var draftInput: PlanningInput? {
        guard let origin else { return nil }
        return .init(title: title, origin: origin, places: places, preferences: preferences,
                     startsAt: startsAt, finishBy: finishBy, timeZone: timeZone, mode: mode)
    }
    func draftChanged() {
        guard !isBusy else { return }
        if let job, job.tripID == nil, job.input == draftInput { return }
        generation += 1; job = nil; pendingRequest = nil; pendingApply = nil; error = nil
    }
    func sessionDidChange(_ value: AuthenticationSnapshot) {
        let blocked = value.account == nil || value.requiresPasswordReset
        guard sessionID != value.sessionID || privateAccessBlocked != blocked else { return }
        privateAccessBlocked = blocked
        sessionID = value.sessionID; generation += 1; isBusy = false; progress = nil
        trips = []; job = nil; pendingRequest = nil; pendingApply = nil; pendingEvent = nil
        openTripID = nil; title = "My trip"; origin = nil; originLabel = "Choose a starting point"
        places = []; preferences = ""; reportedPosition = nil; error = nil
        startsAt = Date().addingTimeInterval(600); finishBy = startsAt.addingTimeInterval(4 * 3600)
        timeZone = TimeZone.current.identifier; mode = .walking
    }
    func receivedLocation(_ point: PlanningPoint) {
        origin = point; originLabel = "Current device position"; reportedPosition = (point, Date())
    }
    func receivedReplanningLocation(_ point: PlanningPoint) { reportedPosition = (point, Date()) }
    func load() async {
        guard !privateAccessBlocked else { error = PlanningError.authenticationRequired.localizedDescription; return }
        guard !isBusy else { return }
        let ticket = generation; isBusy = true
        defer { if ticket == generation { isBusy = false; progress = nil } }
        do {
            let saved = try await interactor.trips()
            guard ticket == generation, !Task.isCancelled else { return }; trips = saved
            if let current = job {
                if let tripID = current.tripID, saved.first(where: { $0.id == tripID })?.revision != current.baseRevision {
                    job = nil; pendingRequest = nil; pendingApply = nil
                    error = PlanningError.revisionConflict.localizedDescription
                    return
                }
                if current.status == .queued || current.status == .running {
                    let refreshed = try await interactor.job(current.id)
                    guard ticket == generation, !Task.isCancelled else { return }
                    try await receive(refreshed, ticket: ticket)
                }
                return
            }
            if job == nil, let resumed = try await interactor.resume() {
                guard ticket == generation, !Task.isCancelled else { return }
                if let tripID = resumed.tripID {
                    guard saved.first(where: { $0.id == tripID })?.revision == resumed.baseRevision else { return }
                } else if !places.isEmpty, resumed.input != draftInput { return }
                if resumed.tripID == nil && places.isEmpty { setDraft(resumed.input); originLabel = "Restored starting point" }
                try await receive(resumed, ticket: ticket)
            }
        } catch is CancellationError { }
        catch { if ticket == generation { self.error = error.localizedDescription } }
    }
    func request(_ purpose: PlanningPurpose = .plan, trip: PersonalPlanningTrip? = nil) async {
        guard !privateAccessBlocked else { error = PlanningError.authenticationRequired.localizedDescription; return }
        guard !isBusy else { return }
        let ticket = generation; isBusy = true; error = nil; progress = "Preparing your request…"
        defer { if ticket == generation { isBusy = false; progress = nil } }
        do {
            guard let input = trip?.input ?? draftInput else { throw PlanningError.invalidInput }; try input.validate()
            let command: PlanningRequest
            if let pendingRequest, pendingRequest.purpose == purpose, pendingRequest.input == input,
               pendingRequest.tripID == trip?.id, pendingRequest.baseRevision == trip?.revision { command = pendingRequest }
            else {
                let position = reportedPosition.flatMap { Date().timeIntervalSince($0.1) <= 30 ? $0.0 : nil }
                command = .init(requestID: UUID(), purpose: purpose, input: input, tripID: trip?.id,
                                baseRevision: trip?.revision, currentOrigin: trip == nil ? nil : position)
                pendingRequest = command
            }
            let value = try await interactor.request(command)
            guard ticket == generation, !Task.isCancelled else { return }
            try await receive(value, ticket: ticket)
        } catch is CancellationError { }
        catch { if ticket == generation { self.error = error.localizedDescription } }
    }
    private func receive(_ value: PlanningJob, ticket: Int) async throws {
        var latest = value
        for _ in 0 ..< 90 {
            try Task.checkCancellation(); guard ticket == generation else { return }
            job = latest
            switch latest.status {
            case .succeeded: pendingRequest = nil; progress = nil; return
            case .failed: pendingRequest = nil; throw PlanningError.failed(latest.errorCode ?? "PROVIDER_UNAVAILABLE")
            case .unknown: throw PlanningError.invalidResponse
            case .queued: progress = "Your planning request is queued…"
            case .running: progress = "Checking places, routes, weather and visit times…"
            }
            try await Task.sleep(for: .seconds(2))
            latest = try await interactor.job(latest.id)
        }
        error = "Planning is still running. Refresh to read its status; your request has been preserved."
    }
    func apply() async {
        guard !isBusy, let job, job.result?.proposal?.feasible == true else { return }
        let ticket = generation; isBusy = true; error = nil
        defer { if ticket == generation { isBusy = false } }
        let id = pendingApply?.0 == job.id ? pendingApply!.1 : UUID(); pendingApply = (job.id, id)
        do {
            let trip = try await interactor.apply(job: job, requestID: id)
            guard ticket == generation, !Task.isCancelled else { return }
            upsert(trip); self.job = nil; pendingApply = nil; pendingRequest = nil
            if job.tripID == nil { openTripID = trip.id }
        } catch is CancellationError { }
        catch { if ticket == generation { self.error = error.localizedDescription } }
    }
    func event(_ kind: PlanningEventKind, trip: PersonalPlanningTrip, extraSeconds: Int? = nil) async {
        guard !isBusy else { return }
        let ticket = generation; isBusy = true; error = nil
        defer { if ticket == generation { isBusy = false } }
        let command: PlanningEvent
        let stopID = kind == .start ? nil : trip.nextStop?.id
        if let prior = pendingEvent, prior.0 == trip.id, prior.1.kind == kind,
           prior.1.expectedRevision == trip.revision, prior.1.stopID == stopID, prior.1.extraSeconds == extraSeconds { command = prior.1 }
        else { command = .init(requestID: UUID(), expectedRevision: trip.revision, kind: kind, stopID: stopID, extraSeconds: extraSeconds); pendingEvent = (trip.id, command) }
        do {
            let updated = try await interactor.event(tripID: trip.id, event: command)
            guard ticket == generation, !Task.isCancelled else { return }
            upsert(updated); pendingEvent = nil; job = nil; pendingRequest = nil; pendingApply = nil
        } catch is CancellationError { }
        catch { if ticket == generation { self.error = error.localizedDescription } }
    }
    private func upsert(_ trip: PersonalPlanningTrip) {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index] = trip }
        else { trips.insert(trip, at: 0) }
    }
}
