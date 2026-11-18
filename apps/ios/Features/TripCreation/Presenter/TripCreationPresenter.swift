import Foundation
import OSLog
import Observation
import C67Domain

@MainActor @Observable final class TripCreationPresenter {
    let planning: PlanningPresenter
    let mode: String
    let root: TripCreationRoute
    var path: [TripCreationRoute] = []
    var answers = PreferenceAnswers()
    var selected: [RecommendedPlace]
    var mainSpot = MainSpotChoice.automatic
    var stay: StayDuration?
    private var availabilityIDs: Set<UUID> = []
    var availabilityPlaces: [RecommendedPlace] { selected.filter { availabilityIDs.contains($0.id) } }
    var query = ""
    private(set) var results: [RecommendedPlace] = []
    private(set) var isSearching = false
    private var submittedQuery: String?
    private var searchFailure: String?
    var searchError: String? { submittedQuery == normalizedQuery ? searchFailure : nil }
    var hasSearchedCurrentQuery: Bool { submittedQuery == normalizedQuery && !normalizedQuery.isEmpty }
    var showsPreviousResults: Bool { !results.isEmpty && !normalizedQuery.isEmpty && (!hasSearchedCurrentQuery || isSearching || searchError != nil) }
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private(set) var isProcessing = false
    private(set) var isShowingCompletion = false
    private(set) var isSuggesting = false
    private(set) var recommendationError: String?
    private(set) var batch = RecommendationsBatch(places: [], warnings: [], synthetic: false)
    private(set) var reviewProposal: PlanProposal?
    var error: String?
    private var recommendationAnswers: PreferenceAnswers?
    private var recommendationOrigin: PlanningPoint?
    private var recommendationPage = 0
    private var recommendationGeneration = 0
    private var recommendationTask: Task<RecommendationsBatch, any Error>?
    private let interactor: TripCreationInteractor
    private let basePreferences: String
    private let orderingMethod: () -> PlanningOrderingMethod
    private let clock: () -> Date
    private var searchGeneration = 0
    private var restoredJobID: UUID?
    private var reviewTiming: (started: ContinuousClock.Instant, requestID: UUID, method: PlanningOrderingMethod)?
    private static let timingLogger = Logger(subsystem: "io.pibeebee.c67", category: "PlanningTiming")

    init(planning: PlanningPresenter, mode: String, specificPlace: Bool, interactor: TripCreationInteractor,
         orderingMethod: @escaping () -> PlanningOrderingMethod = { .hybridV42 }, clock: @escaping () -> Date = { .now }) {
        self.planning = planning
        self.mode = mode
        root = specificPlace ? .places : .question(.interests)
        self.interactor = interactor
        self.orderingMethod = orderingMethod
        self.clock = clock
        selected = planning.places.map { .init(place: $0) }
        basePreferences = planning.preferences
        answers.timing = planning.enginePreferences?.tripTiming.flatMap { TripTiming(rawValue: $0.rawValue) }
        answers.dayPart = planning.enginePreferences?.preferredDayPart.flatMap { DayPart(rawValue: $0.rawValue) }
    }

    var route: TripCreationRoute { path.last ?? root }
    var usesV41: Bool { orderingMethod().usesFlexibleSchedule }
    var usesFoundationModels: Bool { orderingMethod() == .hybridV42FoundationModels }
    var hasSixPlaceLimit: Bool { !planning.supportsOnDevicePlanning || orderingMethod().isSchedule }
    var scheduleAssessment: PlanningScheduleAssessment? { planning.firstItineraryJob?.scheduleAssessment }
    var scheduleSummary: String {
        guard let input = planning.draftInput else { return "Choose a trip date" }
        let dates = (try? PlanningDayWindow.v41Inputs(input, at: clock())) ?? [input]
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: input.timeZone)
        formatter.dateStyle = .medium
        if dates.count > 1, let first = dates.first, let last = dates.last {
            return "Compare \(formatter.string(from: first.startsAt)) – \(formatter.string(from: last.startsAt))"
        }
        return formatter.string(from: dates.first?.startsAt ?? input.startsAt)
    }
    var needsPocketSettings: Bool {
        guard let code = planning.firstItineraryJob?.errorCode else { return false }
        return ["POCKET_CONNECTION_REQUIRED", "POCKET_CONNECTION_REJECTED", "POCKET_ORDER_ENDPOINT_MISSING", "POCKET_ORDER_METHOD_UNSUPPORTED"].contains(code)
    }
    var checksExistingRequest: Bool { planning.hasPendingCreationJob }
    enum ConnectionNotice { case loadFailed, takingLonger }
    var connectionNotice: ConnectionNotice? {
        guard let issue = planning.creationIssue, case .plan = issue.operation else { return nil }
        switch issue.cause {
        case .pending: return .takingLonger
        case .planning(.timedOut): return checksExistingRequest ? .takingLonger : .loadFailed
        case .planning(.unavailable), .planning(.invalidResponse), .planning(.failed("ORDER_GENERATION_FAILED")),
             .planning(.failed("ORDER_RESPONSE_INVALID")): return .loadFailed
        default: return nil
        }
    }

    func selectMainSpot(_ value: MainSpotChoice) {
        guard value != mainSpot else { return }
        mainSpot = value
        stay = nil
        error = nil
        planning.enginePreferences?.mainSpotID = value.placeID
        planning.draftChanged()
    }
    var canTryTomorrow: Bool {
        canTryTomorrow(at: clock())
    }

    private func canTryTomorrow(at now: Date) -> Bool {
        guard let job = planning.firstItineraryJob, job.errorCode == "V4_TODAY_TOO_SHORT" else { return false }
        return PlanningDayWindow.isSameDay(job.createdAt, now, timeZone: job.input.timeZone)
    }

    func tryTomorrow() async {
        let now = clock()
        guard canTryTomorrow(at: now), !isProcessing, !planning.isBusy,
              let window = PlanningDayWindow.tomorrow(after: now, timeZone: planning.timeZone) else { return }
        planning.startsAt = window.start
        planning.finishBy = window.end
        planning.enginePreferences?.usesAutomaticTripDate = false
        planning.enginePreferences?.scheduleSource = .manual
        planning.draftChanged()
        await plan()
    }

    func prepareScheduleOptions() {
        if usesV41 {
            syncEnginePreferences()
            if let input = planning.draftInput, let resolved = try? PlanningDayWindow.v41Inputs(input, at: clock()).first {
                planning.startsAt = resolved.startsAt
                planning.finishBy = resolved.finishBy
            }
            return
        }
        guard planning.enginePreferences?.usesAutomaticTripDate == true,
              orderingMethod() == .hybridV4 else { return }
        let now = planning.firstItineraryJob?.createdAt ?? clock()
        let today = PlanningDayWindow.remainingToday(at: now, timeZone: planning.timeZone)
        guard let window = today.flatMap({ $0.duration > 0 ? $0 : nil }) ??
            PlanningDayWindow.tomorrow(after: now, timeZone: planning.timeZone) else { return }
        planning.startsAt = window.start
        planning.finishBy = window.end
    }
    var canPlan: Bool {
        guard let input = planning.draftInput else { return false }
        return (try? input.validate(purpose: .plan)) != nil
    }

    var planningHandoffMessage: String? {
        let method = orderingMethod()
        guard selected.count > 6, !planning.supportsOnDevicePlanning || method.isSchedule else { return nil }
        return "All \(selected.count) places are kept for this session. This itinerary method supports up to six places."
    }

    func advance(_ step: PreferenceStep, skip: Bool = false) {
        guard route == .question(step) else { return }
        if skip { answers.clear(step) }
        error = nil
        if step == .interests {
            if recommendationAnswers != answers {
                recommendationGeneration += 1
                recommendationAnswers = nil
                recommendationPage = 0
                batch = .init(places: [])
                recommendationError = nil
            }
            push(.recommendations)
        } else {
            push(step.next.map { .question($0) } ?? .recommendations)
        }
    }

    func push(_ route: TripCreationRoute) {
        guard self.route != route else { return }
        path.append(route)
    }

    func toggle(_ item: RecommendedPlace) {
        error = nil
        if let index = selected.firstIndex(where: { $0.id == item.id }) { selected.remove(at: index) }
        else { selected.append(item) }
        if let id = mainSpot.placeID, !selected.contains(where: { $0.id == id }) { mainSpot = .automatic; stay = nil }
        syncPlaces()
    }

    func search() async {
        searchGeneration += 1
        let ticket = searchGeneration
        let text = normalizedQuery
        let session = planning.sessionGeneration
        submittedQuery = text
        searchFailure = nil
        guard !text.isEmpty else { results = []; isSearching = false; return }
        isSearching = true
        defer { if ticket == searchGeneration { isSearching = false } }
        do {
            let found = try await interactor.search(text, near: planning.origin)
            guard ticket == searchGeneration, session == planning.sessionGeneration, !Task.isCancelled, normalizedQuery == text else { return }
            results = found.map { item in
                selected.first(where: { $0.place.name == item.place.name && $0.place.location == item.place.location }) ?? item
            }
        } catch is CancellationError { }
        catch {
            guard ticket == searchGeneration, session == planning.sessionGeneration, !Task.isCancelled, normalizedQuery == text else { return }
            searchFailure = "Check your connection or try a different query."
        }
    }

    func syncPlaces() {
        planning.places = selected.map { item in
            var place = item.place
            if item.id == mainSpot.placeID, let seconds = stay?.visitSeconds { place.visitSeconds = seconds }
            return place
        }
        planning.draftChanged()
    }

    func loadRecommendationsIfNeeded() async {
        guard planning.origin != nil, recommendationAnswers != answers || recommendationOrigin != planning.origin else { return }
        _ = await suggest()
    }

    func suggest() async -> RecommendationsBatch? {
        guard !Task.isCancelled, route == .recommendations, !isSuggesting, !planning.isBusy else { return nil }
        let snapshot = answers
        guard let origin = planning.origin, TripDiscoveryArea.contains(origin) else {
            batch = .init(places: [])
            return nil
        }
        recommendationGeneration += 1
        let generation = recommendationGeneration
        let session = planning.sessionGeneration
        let queries = snapshot.discoveryQueries
        // Rotate a bounded batch of queries on refresh; this never limits selected places.
        let count = min(4, queries.count)
        let offset = recommendationPage * count % queries.count
        let window = (0 ..< count).map { queries[(offset + $0) % queries.count] }
        isSuggesting = true
        recommendationError = nil
        let request = Task {
            try await interactor.recommend(queries: window, near: origin, synthetic: mode.hasPrefix("Mock"))
        }
        recommendationTask = request
        defer {
            if generation == recommendationGeneration { isSuggesting = false; recommendationTask = nil }
        }
        do {
            let updated = try await withTaskCancellationHandler {
                try await request.value
            } onCancel: { request.cancel() }
            guard !Task.isCancelled, generation == recommendationGeneration, snapshot == answers, planning.origin == origin,
                  session == planning.sessionGeneration, route == .recommendations else { return nil }
            batch = updated
            recommendationAnswers = snapshot
            recommendationOrigin = origin
            recommendationPage += 1
            return updated
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), generation == recommendationGeneration,
                  snapshot == answers, session == planning.sessionGeneration, route == .recommendations else { return nil }
            recommendationError = "Recommendations are unavailable. Refresh to try again. Your selected places are kept."
            return nil
        }
    }

    func cancelRecommendations() {
        recommendationGeneration += 1
        recommendationTask?.cancel()
        recommendationTask = nil
        isSuggesting = false
    }

    func finishChoosingPlaces() {
        guard !selected.isEmpty else { return }
        error = nil
        syncPlaces()
        syncEnginePreferences()
        push(.mainSpot)
    }

    func finishMainSpot() async {
        guard route == .mainSpot else { return }
        if !planning.supportsOnDevicePlanning, mainSpot.asksForStay { push(.stay) }
        else { await finishSurvey() }
    }

    func finishSurvey() async {
        guard route == .mainSpot || route == .stay, !selected.isEmpty else { return }
        await plan()
    }

    func plan() async {
        guard !Task.isCancelled, !isProcessing, !planning.isBusy else { return }
        if let job = planning.firstItineraryJob, job.id == restoredJobID {
            let input = job.command?.input ?? job.input
            if selected.map(\.id) == input.places.map(\.id) {
                planning.enginePreferences?.mainSpotID = mainSpot.placeID
                planning.draftChanged()
                await planFirstItinerary()
                restoredJobID = planning.firstItineraryJob?.id
                return
            }
        }
        syncPlaces()
        planning.preferences = preferenceText
        syncEnginePreferences()
        planning.draftChanged()
        if let message = planningHandoffMessage { error = message; return }
        if planning.supportsOnDevicePlanning {
            await planFirstItinerary()
            return
        }
        guard selected.allSatisfy({ TripDiscoveryArea.contains($0.place.location) }) else {
            error = "Some selected places have invalid coordinates. Choose their locations again."
            return
        }
        guard planning.origin != nil else { error = "Choose a starting point to prepare your itinerary."; return }
        guard canPlan else { error = PlanningError.invalidInput.localizedDescription; return }
        isProcessing = true; error = nil
        defer { isProcessing = false }
        if checksExistingRequest { await planning.checkStatus() }
        else { await planning.request() }
        guard !Task.isCancelled, !planning.privateAccessBlocked,
              let job = planning.job, job.status == .succeeded, job.purpose == .plan,
              job.input == planning.draftInput, job.result?.proposal != nil, planning.creationIssue == nil else {
            error = planning.creationIssue?.message ?? "Your itinerary could not be prepared. Try again."
            return
        }
        guard await showCompletion() else { return }
        reviewProposal = job.result?.proposal
        push(.review)
    }

    func openFirstItinerary(_ job: PlanningJob) {
        restoredJobID = job.id
        let input = job.command?.input ?? job.input
        answers.timing = input.enginePreferences?.tripTiming.flatMap { TripTiming(rawValue: $0.rawValue) }
        answers.dayPart = input.enginePreferences?.preferredDayPart.flatMap { DayPart(rawValue: $0.rawValue) }
        if let id = input.enginePreferences?.mainSpotID { mainSpot = .place(id) }
        if let proposal = job.result?.proposal, job.status == .succeeded {
            reviewProposal = proposal
            push(.review)
        } else {
            if let code = job.errorCode { error = PlanningError.failed(code).localizedDescription }
            push(.mainSpot)
        }
    }

    private func planFirstItinerary() async {
        let started = ContinuousClock.now
        reviewTiming = nil
        guard planning.origin != nil else { error = "Choose a starting point to prepare your itinerary."; return }
        planning.mode = .automobile
        planning.preservesPlaceOrder = false
        planning.enginePreferences?.mainSpotID = mainSpot.placeID
        planning.draftChanged()
        isProcessing = true; error = nil
        defer { isProcessing = false }
        let routeBeforeRequest = route
        if checksExistingRequest { await planning.checkStatus() }
        else { await planning.request(.firstItinerary) }
        guard !Task.isCancelled, !planning.privateAccessBlocked, route == routeBeforeRequest else { return }
        if planning.creationIssue == nil, let job = planning.job, job.purpose == .firstItinerary,
           job.status == .succeeded, let proposal = job.result?.proposal {
            guard await showCompletion(), route == routeBeforeRequest else { return }
            availabilityIDs = []
            reviewProposal = proposal
            if proposal.effectiveOrderingMethod.usesFlexibleSchedule, let requestID = job.command?.requestID {
                reviewTiming = (started, requestID, proposal.effectiveOrderingMethod)
            }
            push(.review)
        } else {
            let result = planning.job?.result
            let incomplete = Set(result?.candidates.map(\.id) ?? [])
            if route == .availability { availabilityIDs.formUnion(incomplete) }
            else { availabilityIDs = incomplete }
            if !availabilityPlaces.isEmpty, route != .availability { push(.availability) }
            error = planning.creationIssue?.message ?? result?.warnings.prefix(3).joined(separator: "\n") ?? "Your itinerary could not be prepared. Try again."
        }
    }

    func recordReviewAppearance() {
        guard let timing = reviewTiming else { return }
        reviewTiming = nil
        let elapsed = String(describing: timing.started.duration(to: .now))
        Self.timingLogger.info("itinerary_visible request_id=\(timing.requestID.uuidString.lowercased(), privacy: .public) method=\(timing.method.rawValue, privacy: .public) elapsed=\(elapsed, privacy: .public)")
    }

    private func showCompletion() async -> Bool {
        let session = planning.sessionGeneration
        isShowingCompletion = true
        defer { isShowingCompletion = false }
        do {
            try await Task.sleep(for: .seconds(1.5))
        } catch {
            return false
        }
        return !Task.isCancelled && session == planning.sessionGeneration && !planning.privateAccessBlocked
    }

    var preferenceText: String {
        var lines: [String] = basePreferences.isEmpty ? [] : [basePreferences]
        let interests = TripInterest.allCases.filter { answers.interests.contains($0) }.map { String(localized: $0.title) }
        if !interests.isEmpty { lines.append("Interests: " + interests.joined(separator: ", ")) }
        let refinements = TripPreferenceCatalog.groups.flatMap(\.options)
            .filter { answers.refinements.contains($0.id) }.map { String(localized: $0.title) }
        if !refinements.isEmpty { lines.append("Detailed preferences: " + refinements.joined(separator: ", ")) }
        if let value = answers.popularity { lines.append("Place preference: " + String(localized: value.title)) }
        if let value = answers.pace { lines.append("Preferred pace: " + String(localized: value.title)) }
        if !usesV41, let value = answers.timing { lines.append("Timing wish: " + String(localized: value.title)) }
        if let value = answers.dayPart { lines.append("Preferred time of day: " + String(localized: value.title)) }
        if let value = answers.budget { lines.append("Budget wish: " + value.formatted(BudgetScale.currency)) }
        if let value = answers.transport { lines.append("Transport wish: " + String(localized: value.title) + ". Use the confirmed routing mode.") }
        if let id = mainSpot.placeID, let item = selected.first(where: { $0.id == id }) {
            lines.append("Main spot preference: " + item.place.name + ". This does not pin the first stop.")
        }
        return lines.joined(separator: "\n")
    }

    func setVisitDuration(_ id: UUID, minutes: Int?) {
        guard let index = selected.firstIndex(where: { $0.id == id }) else { return }
        if let minutes {
            selected[index].place.visitSeconds = minutes * 60
            selected[index].place.durationOverridden = true
            if let minimum = selected[index].place.minimumAcceptedVisitSeconds, minimum > minutes * 60 {
                selected[index].place.minimumAcceptedVisitSeconds = minutes * 60
            }
        } else { selected[index].place.durationOverridden = false }
        syncPlaces()
    }

    func confirmVisit(_ id: UUID, opens: Date, closes: Date, publicAccess: Bool) {
        guard let index = selected.firstIndex(where: { $0.id == id }) else { return }
        let cutoff = selected[index].place.visitConfirmation?.lastEntryAt
        selected[index].place.visitConfirmation = .init(opensAt: opens, closesAt: closes, publicAccessConfirmed: publicAccess)
        selected[index].place.visitConfirmation?.lastEntryAt = cutoff
        syncPlaces()
    }
    func clearVisitConfirmation(_ id: UUID) {
        guard let index = selected.firstIndex(where: { $0.id == id }), selected[index].place.visitConfirmation != nil else { return }
        selected[index].place.visitConfirmation = nil; syncPlaces()
    }
    func setActivitySession(_ id: UUID, session: PlanningActivitySession?) {
        guard let index = selected.firstIndex(where: { $0.id == id }) else { return }
        selected[index].place.activitySession = session
        syncPlaces()
    }
    func setEntryCutoff(_ id: UUID, date: Date?) {
        guard let index = selected.firstIndex(where: { $0.id == id }) else { return }
        selected[index].place.visitConfirmation?.lastEntryAt = date
        syncPlaces()
    }
    func setMinimumDuration(_ id: UUID, minutes: Int?) {
        guard let index = selected.firstIndex(where: { $0.id == id }) else { return }
        selected[index].place.minimumAcceptedVisitSeconds = minutes.map { $0 * 60 }
        syncPlaces()
    }
    func chooseTripTiming(_ timing: PlanningTripTiming?) {
        answers.timing = timing.flatMap { TripTiming(rawValue: $0.rawValue) }
        planning.enginePreferences?.scheduleSource = timing == nil ? .automatic : .timingAnswer
        planning.enginePreferences?.timingAnchor = clock()
        syncEnginePreferences()
        prepareScheduleOptions()
        planning.draftChanged()
    }
    func changeTripDate(_ date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: planning.timeZone) ?? .current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: planning.startsAt), to: calendar.startOfDay(for: date)).day ?? 0
        guard let start = calendar.date(byAdding: .day, value: days, to: planning.startsAt),
              let finish = calendar.date(byAdding: .day, value: days, to: planning.finishBy) else { return }
        planning.startsAt = start
        planning.finishBy = finish
        planning.enginePreferences?.usesAutomaticTripDate = false
        planning.enginePreferences?.scheduleSource = .manual
        planning.draftChanged()
    }
    func reviewVisitAvailability() {
        let issues = (scheduleAssessment?.conflicts ?? []) + (scheduleAssessment?.regularConflicts ?? []) + (scheduleAssessment?.unresolved ?? [])
        availabilityIDs = Set(issues.compactMap(\.placeID))
        if availabilityIDs.isEmpty { availabilityIDs = Set(selected.map(\.id)) }
        push(.availability)
    }
    func acceptDurationAlternative(_ alternative: PlanningDurationAlternative) async {
        guard !isProcessing, !planning.isBusy else { return }
        let input = planning.firstItineraryJob?.input
        setVisitDuration(alternative.placeID, minutes: alternative.proposedSeconds / 60)
        if let start = alternative.startsAt ?? input?.startsAt { planning.startsAt = start }
        if let finish = alternative.finishBy ?? input?.finishBy { planning.finishBy = finish }
        planning.enginePreferences?.usesAutomaticTripDate = false
        planning.enginePreferences?.scheduleSource = .manual
        planning.draftChanged()
        await plan()
    }
    private func syncEnginePreferences() {
        guard planning.supportsOnDevicePlanning else { return }
        var preferences = planning.enginePreferences ?? PlanningPreferences()
        let selectedMethod = orderingMethod()
        preferences.orderingMethod = selectedMethod == .hybridLegacy ? .hybridWeather : selectedMethod
        preferences.themes = Set(answers.interests.map(\.rawValue))
        let supportedLabels = Set(planning.preferenceLabels.map(\.id))
        preferences.labels = answers.refinements.intersection(supportedLabels)
        if selectedMethod.usesFlexibleSchedule {
            if preferences.scheduleSource == nil { preferences.flexibleDeparture = true }
            let timing = answers.timing.flatMap { PlanningTripTiming(rawValue: $0.rawValue) }
            preferences.preferredDayPart = answers.dayPart.flatMap { PlanningDayPart(rawValue: $0.rawValue) }
            if preferences.scheduleSource != .manual, preferences.scheduleSource != .resolved {
                if preferences.tripTiming != timing || preferences.timingAnchor == nil { preferences.timingAnchor = clock() }
                preferences.tripTiming = timing
                preferences.scheduleSource = timing == nil ? .automatic : .timingAnswer
                preferences.usesAutomaticTripDate = timing == nil
            }
            preferences.allowsAIProcessing = (usesFoundationModels || preferences.usesLuna) && preferences.semanticAssistance != .disabled
        }
        planning.enginePreferences = preferences
    }
}
