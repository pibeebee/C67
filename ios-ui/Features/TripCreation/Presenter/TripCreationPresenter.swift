import Foundation
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
    var query = ""
    private(set) var results: [RecommendedPlace] = []
    private(set) var isSearching = false
    private(set) var searchError: String?
    private(set) var isProcessing = false
    private(set) var isSuggesting = false
    private(set) var recommendationError: String?
    private(set) var batch = RecommendationsBatch(places: [], warnings: [], synthetic: false)
    private(set) var reviewProposal: PlanProposal?
    var error: String?
    private var recommendationAnswers: PreferenceAnswers?
    private var recommendationPage = 0
    private var recommendationGeneration = 0
    private var recommendationTask: Task<RecommendationsBatch, any Error>?
    private let interactor: TripCreationInteractor
    private let basePreferences: String
    private var searchGeneration = 0
    var missingVisitAvailability: Bool {
        planning.supportsOnDevicePlanning && selected.contains { !$0.place.availabilityVerified && $0.place.visitConfirmation == nil }
    }

    init(planning: PlanningPresenter, mode: String, specificPlace: Bool, interactor: TripCreationInteractor) {
        self.planning = planning
        self.mode = mode
        root = specificPlace ? .places : .question(.interests)
        self.interactor = interactor
        selected = planning.places.map { .init(place: $0) }
        basePreferences = planning.preferences
    }

    var route: TripCreationRoute { path.last ?? root }
    var canConfirm: Bool {
        guard let input = planning.draftInput else { return false }
        return (try? input.validate(purpose: .plan)) != nil
    }

    var planningHandoffMessage: String? {
        guard selected.count > 6 else { return nil }
        return "All \(selected.count) places are kept for this session. Itinerary creation supports up to six places for now."
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
        if let index = selected.firstIndex(where: { $0.id == item.id }) { selected.remove(at: index) }
        else { selected.append(item) }
        if let id = mainSpot.placeID, !selected.contains(where: { $0.id == id }) { mainSpot = .automatic; stay = nil }
        syncPlaces()
    }

    func search() async {
        searchGeneration += 1
        let ticket = searchGeneration
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchError = nil
        guard !text.isEmpty else { results = []; isSearching = false; return }
        isSearching = true
        defer { if ticket == searchGeneration { isSearching = false } }
        do {
            let found = try await interactor.search(text, near: planning.origin)
            guard ticket == searchGeneration, !Task.isCancelled else { return }
            results = found.map { item in
                selected.first(where: { $0.place.name == item.place.name && $0.place.location == item.place.location }) ?? item
            }
        } catch is CancellationError { }
        catch {
            guard ticket == searchGeneration, !Task.isCancelled else { return }
            searchError = "Place search is unavailable. Try another query."
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

    func confirm() async {
        syncPlaces()
        planning.preferences = preferenceText
        syncEnginePreferences()
        planning.draftChanged()
        guard canConfirm else { error = planningHandoffMessage ?? PlanningError.invalidInput.localizedDescription; return }
        await plan()
    }

    func loadRecommendationsIfNeeded() async {
        guard recommendationAnswers != answers else { return }
        _ = await suggest()
    }

    func suggest() async -> RecommendationsBatch? {
        guard !Task.isCancelled, route == .recommendations, !isSuggesting, !planning.isBusy else { return nil }
        let snapshot = answers
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
            try await interactor.recommend(queries: window, near: planning.origin, synthetic: mode.hasPrefix("Mock"))
        }
        recommendationTask = request
        defer {
            if generation == recommendationGeneration { isSuggesting = false; recommendationTask = nil }
        }
        do {
            let updated = try await withTaskCancellationHandler {
                try await request.value
            } onCancel: { request.cancel() }
            guard !Task.isCancelled, generation == recommendationGeneration, snapshot == answers,
                  session == planning.sessionGeneration, route == .recommendations else { return nil }
            batch = updated
            recommendationAnswers = snapshot
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
        push(.mainSpot)
    }

    func finishMainSpot() async {
        guard route == .mainSpot else { return }
        if mainSpot.asksForStay { push(.stay) }
        else { finishSurvey() }
    }

    func finishSurvey() {
        guard !selected.isEmpty else { return }
        error = nil
        syncPlaces()
        planning.preferences = preferenceText
        syncEnginePreferences()
        planning.draftChanged()
        if let index = path.firstIndex(of: .confirmation) {
            path.removeSubrange((index + 1) ..< path.endIndex)
        } else { push(.confirmation) }
    }

    func plan() async {
        guard !Task.isCancelled, !isProcessing, !planning.isBusy else { return }
        syncPlaces()
        guard canConfirm else { error = planningHandoffMessage ?? PlanningError.invalidInput.localizedDescription; return }
        if missingVisitAvailability || planning.enginePreferences.map({ $0.usesLuna && !$0.allowsAIProcessing }) == true {
            error = "Review visit availability and schedule advice consent. Unknown hours are not treated as open."
            push(.availability)
            return
        }
        syncPlaces()
        planning.preferences = preferenceText
        syncEnginePreferences()
        planning.draftChanged()
        isProcessing = true; error = nil
        defer { isProcessing = false }
        await planning.request()
        guard !Task.isCancelled, !planning.privateAccessBlocked,
              let job = planning.job, job.status == .succeeded, job.purpose == .plan,
              job.input == planning.draftInput, job.result?.proposal != nil, planning.error == nil else {
            error = planning.error ?? "Your itinerary could not be prepared. Try again."
            return
        }
        reviewProposal = job.result?.proposal
        push(.review)
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
        if let value = answers.timing { lines.append("Timing wish: " + String(localized: value.title)) }
        if let value = answers.dayPart { lines.append("Preferred time of day: " + String(localized: value.title)) }
        if let value = answers.budget { lines.append("Budget wish: " + value.formatted(BudgetScale.currency)) }
        if let value = answers.transport { lines.append("Transport wish: " + String(localized: value.title) + ". Use the confirmed routing mode.") }
        if let id = mainSpot.placeID, let item = selected.first(where: { $0.id == id }) {
            lines.append("Main spot preference: " + item.place.name + ". This does not pin the first stop.")
        }
        return lines.joined(separator: "\n")
    }

    func confirmVisit(_ id: UUID, opens: Date, closes: Date, publicAccess: Bool) {
        guard let index = selected.firstIndex(where: { $0.id == id }) else { return }
        selected[index].place.visitConfirmation = .init(opensAt: opens, closesAt: closes, publicAccessConfirmed: publicAccess)
        syncPlaces()
    }
    func clearVisitConfirmation(_ id: UUID) {
        guard let index = selected.firstIndex(where: { $0.id == id }), selected[index].place.visitConfirmation != nil else { return }
        selected[index].place.visitConfirmation = nil; syncPlaces()
    }
    func setVisitTiming(_ id: UUID, date: Date, timing: PlanningVisitTiming?) {
        guard let index = selected.firstIndex(where: { $0.id == id }) else { return }
        selected[index].place.preferredAfter = timing == nil ? nil : date
        selected[index].place.visitTiming = timing
        syncPlaces()
    }

    private func syncEnginePreferences() {
        guard planning.supportsOnDevicePlanning else { return }
        var preferences = planning.enginePreferences ?? PlanningPreferences()
        preferences.themes = Set(answers.interests.map(\.rawValue))
        let supportedLabels = Set(planning.preferenceLabels.map(\.id))
        preferences.labels = answers.refinements.intersection(supportedLabels)
        planning.enginePreferences = preferences
    }
}
