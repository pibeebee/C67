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
    private(set) var batch = RecommendationsBatch(places: [], warnings: [], synthetic: false)
    private(set) var reviewProposal: PlanProposal?
    var error: String?
    private(set) var recommendationBase: [RecommendedPlace] = []
    private(set) var chosenRecommendations: [PlanningPlace] = []
    private var offeredCandidates: [UUID: RecommendedPlace] = [:]
    private var suggestionInput: PlanningInput?
    private let interactor: TripCreationInteractor
    private let basePreferences: String
    private var searchGeneration = 0

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
        return !selected.isEmpty && (try? input.validate()) != nil
    }

    func advance(_ step: PreferenceStep, skip: Bool = false) {
        guard route == .question(step) else { return }
        if skip { answers.clear(step) }
        push(step.next.map { .question($0) } ?? .confirmation)
    }

    func push(_ route: TripCreationRoute) {
        guard self.route != route else { return }
        path.append(route)
    }

    func toggle(_ item: RecommendedPlace) {
        if let index = selected.firstIndex(where: { $0.id == item.id }) { selected.remove(at: index) }
        else if selected.count < 6 { selected.append(item) }
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
        planning.places = selected.map(\.place)
        planning.draftChanged()
    }

    func confirm() async {
        syncPlaces()
        planning.preferences = preferenceText
        planning.draftChanged()
        guard canConfirm else { error = PlanningError.invalidInput.localizedDescription; return }
        error = nil
        if root == .places { push(.mainSpot) }
        else {
            recommendationBase = selected
            chosenRecommendations = []
            _ = await suggest()
            guard !Task.isCancelled, !planning.privateAccessBlocked else { return }
            push(.recommendations)
        }
    }

    func suggest() async -> RecommendationsBatch? {
        guard !Task.isCancelled, !isProcessing, !planning.isBusy else { return nil }
        planning.places = recommendationBase.map(\.place)
        planning.draftChanged()
        if suggestionInput != planning.draftInput {
            offeredCandidates = [:]
            suggestionInput = planning.draftInput
            batch = .init(places: [])
        }
        isProcessing = true; isSuggesting = true
        defer { isProcessing = false; isSuggesting = false }
        await planning.request(.suggest)
        guard !Task.isCancelled, !planning.privateAccessBlocked,
              let job = planning.job, job.purpose == .suggest, job.status == .succeeded,
              job.input == planning.draftInput, let result = job.result, planning.error == nil else {
            error = planning.error
            return nil
        }
        error = nil
        batch = .init(result: result)
        for item in batch.places { offeredCandidates[item.id] = item }
        return batch
    }

    func chooseRecommendations(_ additional: [PlanningPlace]) {
        var known = Set(recommendationBase.map(\.id))
        let accepted = additional.compactMap { place -> RecommendedPlace? in
            guard let item = offeredCandidates[place.id], known.insert(place.id).inserted else { return nil }
            return item
        }.prefix(min(3, max(0, 6 - recommendationBase.count)))
        chosenRecommendations = accepted.map(\.place)
        selected = recommendationBase + accepted
        if let id = mainSpot.placeID, !selected.contains(where: { $0.id == id }) { mainSpot = .automatic; stay = nil }
        syncPlaces()
        push(.mainSpot)
    }

    func finishMainSpot() async {
        guard route == .mainSpot else { return }
        if mainSpot.asksForStay { push(.stay) }
        else { await plan() }
    }

    func plan() async {
        guard !Task.isCancelled, !isProcessing, !planning.isBusy else { return }
        if let id = mainSpot.placeID, let seconds = stay?.visitSeconds,
           let index = selected.firstIndex(where: { $0.id == id }) { selected[index].place.visitSeconds = seconds }
        syncPlaces()
        planning.preferences = preferenceText
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
}
