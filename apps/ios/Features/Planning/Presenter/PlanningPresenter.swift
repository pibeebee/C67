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
    var preservesPlaceOrder = false
    var enginePreferences: PlanningPreferences?
    let supportsOnDevicePlanning: Bool
    let preferenceLabels: [PlanningPreferenceLabel]
    private(set) var trips: [PersonalPlanningTrip] = []
    private(set) var job: PlanningJob?
    private(set) var isBusy = false
    private(set) var privateAccessBlocked = false
    private(set) var needsFreshProposal = false
    private(set) var progress: String?
    var error: String?
    private(set) var pocketConnection: PlanningConnection?
    private(set) var connectionError: String?
    private(set) var isSavingConnection = false
    var openTripID: UUID?
    private var tripToStartID: UUID?
    private let interactor: PlanningInteractor
    private var generation = 0
    private(set) var sessionGeneration = 0
    private var sessionID: UUID?
    private var pendingRequest: PlanningRequest?
    private var pendingApply: (UUID, UUID)?
    private var pendingEvent: (UUID, PlanningEvent)?
    private var reportedPosition: (PlanningPoint, Date)?

    init(interactor: PlanningInteractor, initialInput: PlanningInput? = nil) {
        self.interactor = interactor
        supportsOnDevicePlanning = interactor.repository.supportsOnDevicePlanning
        preferenceLabels = interactor.repository.preferenceLabels
        if supportsOnDevicePlanning {
            enginePreferences = PlanningPreferences(); timeZone = "Asia/Jakarta"
            (startsAt, finishBy) = Self.defaultPocketWindow(after: .now)
        }
        if let initialInput { setDraft(initialInput); originLabel = "Synthetic starting point" }
    }
    private static func defaultPocketWindow(after now: Date) -> (Date, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let soon = calendar.dateInterval(of: .minute, for: now.addingTimeInterval(600))?.start ?? now
        let soonEnd = soon.addingTimeInterval(4 * 3600)
        if calendar.isDate(soon, inSameDayAs: soonEnd) { return (soon, soonEnd) }
        let nextMorning = calendar.nextDate(after: soon, matching: DateComponents(hour: 9, minute: 0),
                                            matchingPolicy: .nextTime) ?? soon
        return (nextMorning, nextMorning.addingTimeInterval(4 * 3600))
    }

    private func setDraft(_ value: PlanningInput) {
        title = value.title; origin = value.origin; places = value.places; preferences = value.preferences
        startsAt = value.startsAt; finishBy = value.finishBy; timeZone = value.timeZone; mode = value.mode
        preservesPlaceOrder = value.preservesPlaceOrder
        enginePreferences = value.enginePreferences
    }
    var draftInput: PlanningInput? {
        guard let origin else { return nil }
        var input = PlanningInput(title: title, origin: origin, places: places, preferences: preferences,
                                  startsAt: startsAt, finishBy: finishBy, timeZone: timeZone, mode: mode, preservesPlaceOrder: preservesPlaceOrder)
        input.enginePreferences = enginePreferences
        return input
    }
    func draftChanged() {
        guard !isBusy else { return }
        if let job, job.tripID == nil, job.input == draftInput || (job.command != nil && job.command?.input == draftInput) { return }
        generation += 1; job = nil; pendingRequest = nil; pendingApply = nil; error = nil
    }
    func sessionDidChange(_ value: AuthenticationSnapshot) {
        let blocked = value.account == nil || value.requiresPasswordReset
        guard sessionID != value.sessionID || privateAccessBlocked != blocked else { return }
        needsFreshProposal = false
        sessionGeneration += 1
        privateAccessBlocked = blocked
        sessionID = value.sessionID; generation += 1; isBusy = false; progress = nil
        trips = []; job = nil; pendingRequest = nil; pendingApply = nil; pendingEvent = nil
        openTripID = nil; tripToStartID = nil; title = "My trip"; origin = nil; originLabel = "Choose a starting point"
        places = []; preferences = ""; preservesPlaceOrder = false; reportedPosition = nil; error = nil
        enginePreferences = supportsOnDevicePlanning ? PlanningPreferences() : nil
        startsAt = Date().addingTimeInterval(600); finishBy = startsAt.addingTimeInterval(4 * 3600)
        timeZone = supportsOnDevicePlanning ? "Asia/Jakarta" : TimeZone.current.identifier
        if supportsOnDevicePlanning { (startsAt, finishBy) = Self.defaultPocketWindow(after: .now) }
        mode = .walking
    }
    func receivedLocation(_ point: PlanningPoint) {
        origin = point; originLabel = "Current device position"; reportedPosition = (point, Date())
    }
    func receivedReplanningLocation(_ point: PlanningPoint) { reportedPosition = (point, Date()) }
    func loadPocketConnection() async { pocketConnection = await interactor.repository.engineConnection() }
    func savePocketConnection(serverURL: String, token: String) async -> Bool {
        guard !isSavingConnection, !isBusy else { return false }
        isSavingConnection = true; connectionError = nil
        defer { isSavingConnection = false }
        do {
            try await interactor.repository.updateEngineConnection(serverURL: serverURL, token: token)
            pocketConnection = await interactor.repository.engineConnection()
            draftChanged()
            return true
        } catch { connectionError = error.localizedDescription; return false }
    }
    var firstItineraryJob: PlanningJob? {
        guard job?.purpose == .firstItinerary else { return nil }
        return job
    }

    func load(waitForFirstItinerary: Bool = true) async {
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
                    if current.purpose == .firstItinerary, !waitForFirstItinerary { return }
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
                } else if !places.isEmpty, resumed.input != draftInput, resumed.command?.input != draftInput { return }
                if resumed.tripID == nil && places.isEmpty { setDraft(resumed.command?.input ?? resumed.input); originLabel = "Restored starting point" }
                if resumed.status == .running || resumed.status == .queued { pendingRequest = resumed.command }
                if resumed.purpose == .firstItinerary, !waitForFirstItinerary {
                    job = resumed
                    if resumed.status == .succeeded, let proposal = resumed.result?.proposal { setDraft(proposal.input) }
                    return
                }
                try await receive(resumed, ticket: ticket)
            }
        } catch is CancellationError { }
        catch { if ticket == generation { self.error = error.localizedDescription } }
    }
    func request(_ purpose: PlanningPurpose = .plan, trip: PersonalPlanningTrip? = nil) async {
        guard !privateAccessBlocked else { error = PlanningError.authenticationRequired.localizedDescription; return }
        guard !isBusy else { return }
        let ticket = generation; isBusy = true; error = nil; needsFreshProposal = false; progress = "Preparing your request…"
        defer { if ticket == generation { isBusy = false; progress = nil } }
        do {
            guard let input = trip?.input ?? draftInput else { throw PlanningError.invalidInput }; try input.validate(purpose: purpose)
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
        catch {
            guard ticket == generation else { return }
            let interruptedOrder = job?.input.enginePreferences?.reasonableOrdering == true && (error as? PlanningError) == .unavailable
            self.error = interruptedOrder ? PlanningError.failed("ORDER_CONNECTION_INTERRUPTED").localizedDescription : error.localizedDescription
            if supportsOnDevicePlanning, (error as? PlanningError) != .unavailable { pendingRequest = nil }
        }
    }
    private func receive(_ value: PlanningJob, ticket: Int) async throws {
        var latest = value
        let deadline = value.input.enginePreferences?.reasonableOrdering == true ? nil : ContinuousClock.now.advanced(by: .seconds(600))
        while deadline.map({ ContinuousClock.now < $0 }) ?? true {
            try Task.checkCancellation(); guard ticket == generation else { return }
            job = latest
            switch latest.status {
            case .succeeded:
                if latest.purpose == .plan, let requested = draftInput, requested.preservesPlaceOrder,
                   latest.input != requested {
                    job = nil; pendingRequest = nil; needsFreshProposal = true
                    throw PlanningError.invalidResponse
                }
                if latest.purpose != .suggest, latest.input.preservesPlaceOrder {
                    guard latest.result?.proposal?.stops.map(\.id) == latest.input.places.map(\.id),
                          latest.result?.proposal?.input == latest.input else {
                        job = nil; pendingRequest = nil; needsFreshProposal = true
                        throw PlanningError.invalidResponse
                    }
                }
                if latest.purpose == .firstItinerary || latest.result?.proposal?.experiencePlan != nil, let proposal = latest.result?.proposal {
                    setDraft(proposal.input)
                }
                pendingRequest = nil; progress = nil; return
            case .failed: pendingRequest = nil; throw PlanningError.failed(latest.errorCode ?? "PROVIDER_UNAVAILABLE")
            case .unknown: throw PlanningError.invalidResponse
            case .queued: progress = "Your planning request is queued…"
            case .running: progress = latest.input.enginePreferences?.reasonableOrdering == true
                ? "Luna is arranging your places and suggested activities…" : "Checking places, routes, weather and visit times…"
            }
            try await Task.sleep(for: .seconds(2))
            latest = try await interactor.job(latest.id)
        }
        error = "Planning is still running. Refresh to read its status; your request has been preserved."
    }
    func setExperienceDeparture(_ departure: Date) async {
        await updateExperienceRoute(departure: departure)
    }

    func updateExperienceRoute(orderedIDs: [UUID]? = nil, departure: Date? = nil) async {
        guard !isBusy, !needsFreshProposal, let job, job.input == draftInput else { return }
        let ticket = generation; isBusy = true; error = nil; progress = "Checking driving times…"
        defer { if ticket == generation { isBusy = false; progress = nil } }
        do {
            let changed = try await interactor.updateExperienceRoute(jobID: job.id, orderedIDs: orderedIDs, departure: departure)
            guard ticket == generation, !Task.isCancelled else { return }
            self.job = changed
            setDraft(changed.input)
        } catch is CancellationError { }
        catch { if ticket == generation { self.error = error.localizedDescription } }
    }

    func refreshSavedExperienceRoute(tripID: UUID) async {
        guard !isBusy else { return }
        let ticket = generation; isBusy = true; error = nil
        defer { if ticket == generation { isBusy = false } }
        do {
            let trip = try await interactor.refreshExperienceRoute(tripID: tripID)
            guard ticket == generation, !Task.isCancelled else { return }
            upsert(trip)
        } catch is CancellationError { }
        catch { if ticket == generation { self.error = error.localizedDescription } }
    }

    func consumeStartRequest(for id: UUID) -> Bool {
        guard tripToStartID == id else { return false }
        tripToStartID = nil
        return true
    }

    /// Untimed proposals can be renamed locally; legacy timed drafts retain regeneration.
    func saveReviewedProposal(named name: String, startImmediately: Bool = false) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !trimmed.isEmpty, trimmed.count <= 120,
              let proposal = job?.result?.proposal, job?.input == draftInput else {
            if !isBusy { error = PlanningError.invalidInput.localizedDescription }
            return
        }
        if trimmed != proposal.input.title {
            if proposal.experiencePlan != nil, let current = job {
                let ticket = generation
                isBusy = true; error = nil
                defer { if ticket == generation { isBusy = false } }
                do {
                    let renamed = try await interactor.rename(jobID: current.id, title: trimmed)
                    guard ticket == generation, !Task.isCancelled, job?.id == current.id else { return }
                    job = renamed; setDraft(renamed.input)
                    await applyCurrentProposal(ticket: ticket, startImmediately: startImmediately)
                } catch is CancellationError { }
                catch { if ticket == generation, !Task.isCancelled { self.error = error.localizedDescription } }
                return
            }
            title = trimmed
            draftChanged()
            await request()
        } else {
            await apply(startImmediately: startImmediately)
        }
    }

    func apply(startImmediately: Bool = false) async {
        guard !isBusy, job?.result?.proposal?.feasible == true else { return }
        let ticket = generation; isBusy = true; error = nil
        defer { if ticket == generation { isBusy = false } }
        await applyCurrentProposal(ticket: ticket, startImmediately: startImmediately)
    }

    private func applyCurrentProposal(ticket: Int, startImmediately: Bool) async {
        guard ticket == generation, !Task.isCancelled, let job, job.result?.proposal?.feasible == true else { return }
        let id = pendingApply?.0 == job.id ? pendingApply!.1 : UUID(); pendingApply = (job.id, id)
        do {
            let trip = try await interactor.apply(job: job, requestID: id)
            guard ticket == generation, !Task.isCancelled else { return }
            upsert(trip); self.job = nil; pendingApply = nil; pendingRequest = nil
            if job.tripID == nil {
                tripToStartID = startImmediately ? trip.id : nil
                openTripID = trip.id
            }
        } catch is CancellationError { }
        catch {
            if ticket == generation {
                self.error = error.localizedDescription
                needsFreshProposal = (error as? PlanningError) == .expired || (error as? PlanningError) == .revisionConflict
            }
        }
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
