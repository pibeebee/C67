import Foundation
import Observation
import C67Domain

@MainActor @Observable
final class PlanningPresenter {
    func openingHours(placeID: String) async -> PlanningHoursLookup {
        await interactor.repository.openingHours(placeID: placeID)
    }
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
    private(set) var activity: PlanningActivity?
    private(set) var issues: [PresentationIssue.Scope: PresentationIssue] = [:]
    private var latestIssueScope: PresentationIssue.Scope?
    var error: String? { latestIssueScope.flatMap { issues[$0]?.message } }
    var tripListError: String? { issues[.tripList]?.message }
    var reviewIssue: PresentationIssue? { issues[.review] }
    var creationIssue: PresentationIssue? { issues[.planning(nil)] }

    private func clearIssue(_ scope: PresentationIssue.Scope) {
        issues[scope] = nil
        latestIssueScope = scope
    }

    private func record(_ issue: PresentationIssue) {
        guard !Task.isCancelled else { return }
        issues[issue.scope] = issue
        latestIssueScope = issue.scope
    }
    private(set) var pocketConnection: PlanningConnection?
    private(set) var connectionError: String?
    private(set) var isSavingConnection = false
    var openTripID: UUID?
    private var tripToStartID: UUID?
    private let interactor: PlanningInteractor
    private var generation = 0
    private var ignoresPreviousPendingJob = false
    private(set) var sessionGeneration = 0
    private var sessionID: UUID?
    private var pendingRequest: PlanningRequest?
    private var jobScope: PresentationIssue.Scope?
    private var pendingApply: (UUID, UUID)?
    private var pendingEvent: (UUID, PlanningEvent)?
    private struct ArrivalAttempt: Hashable {
        let tripID: UUID
        let stopID: UUID
        let revision: Int
    }
    private var automaticArrivalAttempts: Set<ArrivalAttempt> = []
    private var reportedPosition: (PlanningPoint, Date)?

    init(interactor: PlanningInteractor, initialInput: PlanningInput? = nil) {
        self.interactor = interactor
        supportsOnDevicePlanning = interactor.repository.supportsOnDevicePlanning
        preferenceLabels = interactor.repository.preferenceLabels
        if supportsOnDevicePlanning {
            enginePreferences = PlanningPreferences(); timeZone = "Asia/Jakarta"
            enginePreferences?.usesAutomaticTripDate = true
            if supportsOnDevicePlanning { enginePreferences?.returnToOrigin = true }
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
    var requiresExternalAIConsent: Bool { interactor.repository.requiresExternalAIConsent }
    var externalAIAvailable: Bool { interactor.repository.externalAIAvailable }

    func hasExternalAIConsent() async -> Bool {
        await interactor.repository.hasExternalAIConsent(enginePreferences?.externalAIConsentID)
    }

    func grantExternalAIConsent() async throws {
        let session = sessionGeneration
        let id = try await interactor.repository.grantExternalAIConsent()
        guard session == sessionGeneration, !privateAccessBlocked else { throw CancellationError() }
        enginePreferences?.externalAIConsentID = id
    }

    func withdrawExternalAIConsent() async throws {
        try await interactor.repository.withdrawExternalAIConsent()
        enginePreferences?.externalAIConsentID = nil
        if let active = resumableJob, let refreshed = try? await interactor.repository.planningJob(id: active.id),
           job?.id == active.id {
            job = refreshed
            if refreshed.status == .failed { pendingRequest = nil }
        }
    }

    func draftChanged() {
        guard !isBusy else { return }
        if let job, job.tripID == nil, job.input == draftInput || job.command?.input == draftInput { return }
        if job == nil, let pendingRequest, pendingRequest.tripID == nil, pendingRequest.input == draftInput { return }
        generation += 1; job = nil; jobScope = nil; pendingRequest = nil; pendingApply = nil; clearIssue(.planning(nil)); clearIssue(.review)
    }
    /// Start a separate creation session without changing saved trips or the starting point.
    func startNewTrip() {
        guard !isBusy, resumableJob == nil else { return }
        generation += 1
        ignoresPreviousPendingJob = true
        job = nil; jobScope = nil; pendingRequest = nil; pendingApply = nil; needsFreshProposal = false; clearIssue(.planning(nil)); clearIssue(.review)
        title = "My trip"; places = []; preferences = ""; preservesPlaceOrder = false
        enginePreferences = supportsOnDevicePlanning ? PlanningPreferences() : nil
        enginePreferences?.usesAutomaticTripDate = true
        if supportsOnDevicePlanning { enginePreferences?.returnToOrigin = true }
        startsAt = Date().addingTimeInterval(600); finishBy = startsAt.addingTimeInterval(4 * 3600)
        timeZone = supportsOnDevicePlanning ? "Asia/Jakarta" : TimeZone.current.identifier
        if supportsOnDevicePlanning { (startsAt, finishBy) = Self.defaultPocketWindow(after: .now) }
        mode = .walking
    }
    func recoverPendingCreation() async -> PlanningJob? {
        guard !isBusy, !privateAccessBlocked else { return nil }
        if let current = resumableJob, current.purpose == .firstItinerary { return current }
        let ticket = generation
        isBusy = true
        defer { if ticket == generation { isBusy = false } }
        do {
            guard let pending = try await interactor.resume(), ticket == generation,
                  pending.purpose == .firstItinerary, pending.status == .running || pending.status == .queued else { return nil }
            job = pending
            jobScope = .planning(nil)
            pendingRequest = pending.command
            ignoresPreviousPendingJob = false
            setDraft(pending.command?.input ?? pending.input)
            return pending
        } catch {
            guard ticket == generation else { return nil }
            record(.init(error, scope: .planning(nil), operation: .plan(.firstItinerary)))
            return nil
        }
    }
    func sessionDidChange(_ value: AuthenticationSnapshot) {
        let blocked = value.account == nil || value.requiresPasswordReset
        guard sessionID != value.sessionID || privateAccessBlocked != blocked else { return }
        needsFreshProposal = false; ignoresPreviousPendingJob = false
        sessionGeneration += 1
        privateAccessBlocked = blocked
        sessionID = value.sessionID; generation += 1; isBusy = false; progress = nil; activity = nil
        trips = []; job = nil; jobScope = nil; pendingRequest = nil; pendingApply = nil; pendingEvent = nil; automaticArrivalAttempts = []
        openTripID = nil; tripToStartID = nil; title = "My trip"; origin = nil; originLabel = "Choose a starting point"
        places = []; preferences = ""; preservesPlaceOrder = false; reportedPosition = nil; issues = [:]; latestIssueScope = nil
        enginePreferences = supportsOnDevicePlanning ? PlanningPreferences() : nil
        enginePreferences?.usesAutomaticTripDate = true
        if supportsOnDevicePlanning { enginePreferences?.returnToOrigin = true }
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
    var hasPendingCreationJob: Bool {
        guard jobScope == .planning(nil), let job = resumableJob else { return false }
        return job.purpose == .firstItinerary || job.purpose == .plan
    }
    var firstItineraryJob: PlanningJob? {
        guard job?.purpose == .firstItinerary else { return nil }
        return job
    }

    var supportsTripDeletion: Bool { interactor.repository.supportsTripDeletion }

    func deleteTrip(_ trip: PersonalPlanningTrip) async -> Bool {
        guard !isBusy, !privateAccessBlocked else { return false }
        let ticket = generation
        let scope = PresentationIssue.Scope.savedTrip(trip.id)
        isBusy = true; clearIssue(scope)
        defer { if ticket == generation { isBusy = false } }
        do {
            try await interactor.repository.deleteTrip(id: trip.id, expectedRevision: trip.revision)
            guard ticket == generation, !Task.isCancelled else { return false }
            trips.removeAll { $0.id == trip.id }
            issues[.activity(trip.id)] = nil
            issues[.planning(trip.id)] = nil
            return true
        } catch {
            if ticket == generation { record(.init(error, scope: scope, operation: .delete)) }
            return false
        }
    }

    func load(waitForFirstItinerary: Bool = true, resumesJobs: Bool = true) async {
        guard !privateAccessBlocked else {
            record(.init(PlanningError.authenticationRequired, scope: .tripList, operation: .loadTrips))
            return
        }
        guard !isBusy else { return }
        let ticket = generation; isBusy = true; clearIssue(.tripList)
        var checkedJob: PlanningJob?
        defer { if ticket == generation { isBusy = false; progress = nil } }
        do {
            let saved: [PersonalPlanningTrip]
            do { saved = try await interactor.trips() }
            catch {
                if ticket == generation, !(error is CancellationError) { record(.init(error, scope: .tripList, operation: .loadTrips)) }
                return
            }
            guard ticket == generation, !Task.isCancelled else { return }
            for trip in trips where saved.first(where: { $0.id == trip.id })?.revision != trip.revision {
                issues[.savedTrip(trip.id)] = nil
                issues[.activity(trip.id)] = nil
            }
            trips = saved
            guard resumesJobs else { return }
            if let current = job {
                checkedJob = current
                if let tripID = current.tripID, saved.first(where: { $0.id == tripID })?.revision != current.baseRevision {
                    job = nil; jobScope = nil; pendingRequest = nil; pendingApply = nil
                    record(.init(PlanningError.revisionConflict, scope: .planning(tripID), operation: .plan(current.purpose)))
                    return
                }
                if current.status == .queued || current.status == .running {
                    if current.purpose == .firstItinerary, !waitForFirstItinerary { return }
                    let scope = jobScope ?? .planning(current.tripID)
                    clearIssue(scope)
                    let refreshed = try await interactor.job(current.id)
                    guard ticket == generation, !Task.isCancelled else { return }
                    try await receive(refreshed, ticket: ticket, scope: scope)
                }
                return
            }
            if job == nil, !ignoresPreviousPendingJob, let resumed = try await interactor.resume() {
                checkedJob = resumed
                guard ticket == generation, !Task.isCancelled else { return }
                if let tripID = resumed.tripID {
                    guard saved.first(where: { $0.id == tripID })?.revision == resumed.baseRevision else { return }
                } else if !places.isEmpty, resumed.input != draftInput, resumed.command?.input != draftInput { return }
                if resumed.tripID == nil && places.isEmpty { setDraft(resumed.command?.input ?? resumed.input); originLabel = "Restored starting point" }
                if resumed.status == .running || resumed.status == .queued { pendingRequest = resumed.command }
                if resumed.purpose == .firstItinerary, !waitForFirstItinerary {
                    job = resumed
                    jobScope = .planning(resumed.tripID)
                    if resumed.status == .succeeded, let proposal = resumed.result?.proposal { setDraft(proposal.input) }
                    return
                }
                try await receive(resumed, ticket: ticket, scope: .planning(resumed.tripID))
            }
        } catch is CancellationError { }
        catch {
            guard ticket == generation else { return }
            record(.init(error, scope: jobScope ?? .planning(checkedJob?.tripID), operation: .plan(checkedJob?.purpose ?? .firstItinerary),
                         jobID: resumableJob?.id))
        }
    }
    func request(_ purpose: PlanningPurpose = .plan, trip: PersonalPlanningTrip? = nil, reviewing: Bool = false, replacementDeparture: Date? = nil) async {
        let scope: PresentationIssue.Scope = reviewing ? .review : .planning(trip?.id)
        let operation = PresentationIssue.Operation.plan(purpose)
        guard !privateAccessBlocked else { record(.init(PlanningError.authenticationRequired, scope: scope, operation: operation)); return }
        guard !isBusy else { return }
        let ticket = generation; isBusy = true; clearIssue(scope); needsFreshProposal = false; progress = "Preparing your request…"; activity = nil
        defer { if ticket == generation { isBusy = false; progress = nil; activity = nil } }
        do {
            guard let input = trip?.input ?? draftInput else { throw PlanningError.invalidInput }; try input.validate(purpose: purpose)
            let command: PlanningRequest
            if let pendingRequest, pendingRequest.purpose == purpose, pendingRequest.input == input,
               pendingRequest.tripID == trip?.id, pendingRequest.baseRevision == trip?.revision,
               pendingRequest.replacementDeparture == replacementDeparture { command = pendingRequest }
            else {
                let position = reportedPosition.flatMap { Date().timeIntervalSince($0.1) <= 30 ? $0.0 : nil }
                var draftCommand = PlanningRequest(requestID: UUID(), purpose: purpose, input: input, tripID: trip?.id,
                                                   baseRevision: trip?.revision, currentOrigin: trip == nil ? nil : position)
                draftCommand.replacementDeparture = replacementDeparture
                command = draftCommand
                pendingRequest = command
            }
            let value = try await interactor.request(command)
            guard ticket == generation, !Task.isCancelled else { return }
            try await receive(value, ticket: ticket, scope: scope)
        } catch is CancellationError { }
        catch {
            guard ticket == generation else { return }
            let active = resumableJob
            let jobID = jobScope == scope && active?.purpose == purpose ? active?.id : nil
            let issue = PresentationIssue(error, scope: scope, operation: operation, jobID: jobID)
            record(issue)
            if issue.certainty == .final { pendingRequest = nil }
        }
    }

    private var resumableJob: PlanningJob? {
        guard let job, job.status == .queued || job.status == .running else { return nil }
        return job
    }

    var canCancelPlanning: Bool {
        interactor.repository.supportsPlanningCancellation && resumableJob != nil
    }

    func cancelPlanning() async -> Bool {
        guard canCancelPlanning, let current = resumableJob else { return false }
        let scope = jobScope ?? .planning(current.tripID)
        generation += 1
        let ticket = generation
        isBusy = true; activity = nil
        defer { if ticket == generation { isBusy = false; progress = nil } }
        do {
            try await interactor.repository.cancelPlanning(id: current.id)
            guard ticket == generation else { return false }
            var cancelled = current
            cancelled.status = .failed
            cancelled.errorCode = "PLANNING_CANCELLED"
            job = cancelled
            pendingRequest = nil
            clearIssue(scope)
            return true
        } catch {
            if ticket == generation { record(.init(error, scope: scope, operation: .plan(current.purpose), jobID: current.id)) }
            return false
        }
    }

    func checkStatus(scope: PresentationIssue.Scope = .planning(nil)) async {
        guard !isBusy, !privateAccessBlocked, jobScope == scope, let current = resumableJob else { return }
        let ticket = generation
        isBusy = true; clearIssue(scope); progress = "Checking request status…"; activity = nil
        defer { if ticket == generation { isBusy = false; progress = nil; activity = nil } }
        do {
            let refreshed = try await interactor.repository.checkPlanningJob(id: current.id)
            try await receive(refreshed, ticket: ticket, scope: scope)
        } catch is CancellationError { }
        catch {
            guard ticket == generation else { return }
            if (error as? PlanningError) == .notFound || (error as? PlanningError) == .expired {
                var missing = current
                missing.status = .failed
                missing.errorCode = "ORDER_JOB_MISSING"
                job = missing
                pendingRequest = nil
            }
            record(.init(error, scope: scope, operation: .plan(current.purpose), jobID: resumableJob?.id))
        }
    }

    private func receive(_ value: PlanningJob, ticket: Int, scope: PresentationIssue.Scope) async throws {
        var latest = value
        let deadline = ContinuousClock.now.advanced(by: .seconds(360))
        while true {
            try Task.checkCancellation(); guard ticket == generation else { return }
            job = latest
            activity = latest.status == .running ? latest.activity : nil
            jobScope = scope
            switch latest.status {
            case .succeeded:
                if latest.purpose == .plan, let requested = draftInput, requested.preservesPlaceOrder,
                   latest.input != requested {
                    job = nil; jobScope = nil; pendingRequest = nil; needsFreshProposal = true
                    throw PlanningError.invalidResponse
                }
                if latest.purpose != .suggest, latest.input.preservesPlaceOrder {
                    guard latest.result?.proposal?.stops.map(\.id) == latest.input.places.map(\.id),
                          latest.result?.proposal?.input == latest.input else {
                        job = nil; jobScope = nil; pendingRequest = nil; needsFreshProposal = true
                        throw PlanningError.invalidResponse
                    }
                }
                if latest.purpose == .firstItinerary || latest.result?.proposal?.usesExperienceFlow == true, let proposal = latest.result?.proposal {
                    setDraft(proposal.input)
                }
                pendingRequest = nil; progress = nil; return
            case .failed:
                pendingRequest = nil
                if latest.errorCode == "PLANNING_AUTH_REQUIRED" { throw PlanningError.authenticationRequired }
                if latest.errorCode == "PLANNING_REVISION_CONFLICT" { throw PlanningError.revisionConflict }
                throw PlanningError.failed(latest.errorCode ?? "PROVIDER_UNAVAILABLE")
            case .unknown: throw PlanningError.invalidResponse
            case .queued: progress = "Your planning request is queued…"
            case .running: progress = latest.input.enginePreferences?.orderingMethod?.usesFlexibleSchedule == true
                ? "Checking candidate schedules…" : "Preparing your itinerary…"
            }
            if ContinuousClock.now >= deadline {
                record(.init(pending: scope, purpose: latest.purpose, jobID: latest.id))
                return
            }
            try await Task.sleep(for: .seconds(2))
            latest = try await interactor.job(latest.id)
        }
    }
    func retryReviewIssue() async {
        guard !isBusy, let issue = reviewIssue,
              issue.jobID == nil || issue.jobID == job?.id else { return }
        if issue.recovery == .checkStatus {
            await checkStatus(scope: .review)
            return
        }
        guard issue.recovery == .retry || issue.recovery == .wait else { return }
        switch issue.operation {
        case .changeRoute(let order, let departure):
            await updateExperienceRoute(orderedIDs: order, departure: departure)
        case .save(let name, let startImmediately):
            if let name { await saveReviewedProposal(named: name, startImmediately: startImmediately) }
            else { await apply(startImmediately: startImmediately) }
        case .plan(let purpose):
            await request(purpose, reviewing: true)
        default: break
        }
    }

    func setExperienceDeparture(_ departure: Date) async {
        await updateExperienceRoute(departure: departure)
    }

    func updateTimedReviewOrder(_ places: [PlanningPlace]) async {
        guard !isBusy, let previous = job, previous.result?.proposal != nil,
              previous.input == draftInput else { return }
        let previousScope = jobScope
        self.places = places
        preservesPlaceOrder = true
        draftChanged()
        let ticket = generation
        await request(reviewing: true)
        guard ticket == generation, job?.result?.proposal?.feasible == false else { return }
        job = previous
        jobScope = previousScope
        setDraft(previous.input)
        record(.init(rejectedOrder: places.map(\.id), jobID: previous.id))
    }

    func updateExperienceRoute(orderedIDs: [UUID]? = nil, departure: Date? = nil) async {
        guard !isBusy, !needsFreshProposal, let job, job.input == draftInput else { return }
        let ticket = generation; isBusy = true; clearIssue(.review); progress = "Checking driving times…"
        defer { if ticket == generation { isBusy = false; progress = nil } }
        do {
            let changed = try await interactor.updateExperienceRoute(jobID: job.id, orderedIDs: orderedIDs, departure: departure)
            guard ticket == generation, !Task.isCancelled else { return }
            self.job = changed
            setDraft(changed.input)
        } catch is CancellationError { }
        catch {
            if ticket == generation {
                let cause = (error as? PlanningScheduleFailure).map { PlanningError.failed($0.code) } ?? error
                record(.init(cause, scope: .review, operation: .changeRoute(order: orderedIDs, departure: departure), jobID: job.id))
            }
        }
    }

    func refreshSavedExperienceRoute(tripID: UUID) async {
        guard !isBusy, !privateAccessBlocked else { return }
        let scope = PresentationIssue.Scope.savedTrip(tripID)
        let ticket = generation; isBusy = true; clearIssue(scope)
        defer { if ticket == generation { isBusy = false } }
        do {
            let trip = try await interactor.refreshExperienceRoute(tripID: tripID)
            guard ticket == generation, !Task.isCancelled else { return }
            upsert(trip)
        } catch is CancellationError { }
        catch { if ticket == generation { record(.init(error, scope: scope, operation: .refreshSavedRoute)) } }
    }

    func consumeStartRequest(for id: UUID) -> Bool {
        guard tripToStartID == id else { return false }
        tripToStartID = nil
        return true
    }

    /// Untimed proposals can be renamed locally; legacy timed drafts retain regeneration.
    func saveReviewedProposal(named name: String, startImmediately: Bool = false) async {
        let operation = PresentationIssue.Operation.save(name: name, startImmediately: startImmediately)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !trimmed.isEmpty, trimmed.count <= 120,
              let proposal = job?.result?.proposal, job?.input == draftInput else {
            if !isBusy { record(.init(PlanningError.invalidInput, scope: .review, operation: operation, jobID: job?.id)) }
            return
        }
        if trimmed != proposal.input.title {
            if proposal.usesExperienceFlow, let current = job {
                let ticket = generation
                isBusy = true; clearIssue(.review)
                defer { if ticket == generation { isBusy = false } }
                do {
                    let renamed = try await interactor.rename(jobID: current.id, title: trimmed)
                    guard ticket == generation, !Task.isCancelled, job?.id == current.id else { return }
                    job = renamed; setDraft(renamed.input)
                    await applyCurrentProposal(ticket: ticket, startImmediately: startImmediately)
                } catch is CancellationError { }
                catch { if ticket == generation, !Task.isCancelled { record(.init(error, scope: .review, operation: operation, jobID: current.id)) } }
                return
            }
            title = trimmed
            draftChanged()
            await request(reviewing: true)
        } else {
            await apply(startImmediately: startImmediately)
        }
    }

    func apply(startImmediately: Bool = false, scope: PresentationIssue.Scope = .review) async {
        guard !isBusy, !privateAccessBlocked, job?.result?.proposal?.feasible == true else { return }
        let ticket = generation; isBusy = true; clearIssue(scope)
        defer { if ticket == generation { isBusy = false } }
        await applyCurrentProposal(ticket: ticket, startImmediately: startImmediately, scope: scope)
    }

    private func applyCurrentProposal(ticket: Int, startImmediately: Bool, scope: PresentationIssue.Scope = .review) async {
        guard ticket == generation, !Task.isCancelled, let job, job.result?.proposal?.feasible == true else { return }
        let id = pendingApply.flatMap { $0.0 == job.id ? $0.1 : nil } ?? UUID()
        pendingApply = (job.id, id)
        do {
            let trip = try await interactor.apply(job: job, requestID: id)
            guard ticket == generation, !Task.isCancelled else { return }
            upsert(trip); self.job = nil; jobScope = nil; pendingApply = nil; pendingRequest = nil
            if job.tripID == nil {
                tripToStartID = startImmediately ? trip.id : nil
                openTripID = trip.id
            }
        } catch is CancellationError { }
        catch {
            if ticket == generation {
                let issue = PresentationIssue(error, scope: scope, operation: .save(name: nil, startImmediately: startImmediately), jobID: job.id)
                record(issue)
                if issue.certainty == .final { pendingApply = nil }
                needsFreshProposal = (error as? PlanningError) == .expired || (error as? PlanningError) == .revisionConflict
            }
        }
    }
    func prepareStart(_ trip: PersonalPlanningTrip) async throws -> PlanningStartPreparation? {
        guard !isBusy, !privateAccessBlocked else { throw CancellationError() }
        let ticket = generation
        let scope = PresentationIssue.Scope.activity(trip.id)
        clearIssue(scope)
        isBusy = true
        defer { if ticket == generation { isBusy = false } }
        do {
            let value = try await interactor.repository.prepareStart(tripID: trip.id, expectedRevision: trip.revision)
            guard ticket == generation else { throw CancellationError() }
            return value
        } catch {
            if ticket == generation {
                let cause = (error as? PlanningScheduleFailure).map { PlanningError.failed($0.code) } ?? error
                record(.init(cause, scope: scope, operation: .event(.start, extraSeconds: nil)))
            }
            throw error
        }
    }

    func event(_ kind: PlanningEventKind, trip: PersonalPlanningTrip, extraSeconds: Int? = nil, preparationID: UUID? = nil) async {
        guard !isBusy, !privateAccessBlocked,
              trips.first(where: { $0.id == trip.id })?.revision == trip.revision else { return }
        let scope = PresentationIssue.Scope.activity(trip.id)
        let ticket = generation; isBusy = true; clearIssue(scope)
        defer { if ticket == generation { isBusy = false } }
        let command: PlanningEvent
        let stopID = kind == .start || kind == .arriveAtEndpoint ? nil : trip.nextStop?.id
        if let prior = pendingEvent, prior.0 == trip.id, prior.1.kind == kind,
           prior.1.expectedRevision == trip.revision, prior.1.stopID == stopID, prior.1.extraSeconds == extraSeconds,
           prior.1.preparationID == preparationID { command = prior.1 }
        else {
            var event = PlanningEvent(requestID: UUID(), expectedRevision: trip.revision, kind: kind, stopID: stopID, extraSeconds: extraSeconds)
            event.preparationID = preparationID
            command = event
            pendingEvent = (trip.id, command)
        }
        do {
            let updated = try await interactor.event(tripID: trip.id, event: command)
            guard ticket == generation, !Task.isCancelled else { return }
            upsert(updated); pendingEvent = nil; job = nil; jobScope = nil; pendingRequest = nil; pendingApply = nil
        } catch is CancellationError { }
        catch {
            guard ticket == generation else { return }
            let issue = PresentationIssue(error, scope: scope, operation: .event(kind, extraSeconds: extraSeconds), stopID: stopID)
            record(issue)
            if issue.certainty == .final { pendingEvent = nil }
        }
    }
    func claimAutomaticArrival(for trip: PersonalPlanningTrip) -> Bool {
        guard trip.status == .active, trip.currentStopID == nil, let stopID = trip.nextStop?.id else { return false }
        return automaticArrivalAttempts.insert(.init(tripID: trip.id, stopID: stopID, revision: trip.revision)).inserted
    }
    private func upsert(_ trip: PersonalPlanningTrip) {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index] = trip }
        else { trips.insert(trip, at: 0) }
    }
}
