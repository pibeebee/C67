import Foundation
import Testing
import C67Data
import C67Domain
@testable import C67

@Suite("Connected Hi-Fi trip creation")
@MainActor struct TripCreationTests {
    private func make(specific: Bool = true, repository: any PlanningRepository = MockPlanningRepository(),
                      searcher: (any TripPlaceSearching)? = nil) throws -> TripCreationPresenter {
        let planning = PlanningPresenter(interactor: .init(repository: repository), initialInput: try MockPlanningRepository.sampleInput())
        return TripCreationPresenter(planning: planning, mode: "Mock • memory only", specificPlace: specific,
                                     interactor: .init(searcher: searcher ?? SyntheticTripPlaceSearch()))
    }

    @Test func rejectsPlannerThatIgnoresManualStopOrder() async throws {
        let repository = TripFlowRepositoryStub()
        await repository.setIgnoresManualOrder()
        let model = try make(repository: repository)
        model.planning.preservesPlaceOrder = true
        model.planning.draftChanged()
        await model.planning.request()
        #expect(model.planning.job == nil)
        #expect(model.planning.needsFreshProposal)
        #expect(model.planning.error == PlanningError.invalidResponse.localizedDescription)
    }

    @Test func rejectsPlannerThatDropsManualOrderFlag() async throws {
        let repository = TripFlowRepositoryStub()
        await repository.setDropsManualOrderFlag()
        let model = try make(repository: repository)
        model.planning.preservesPlaceOrder = true
        model.planning.draftChanged()
        await model.planning.request()
        #expect(model.planning.job == nil)
        #expect(model.planning.needsFreshProposal)
        #expect(model.planning.error == PlanningError.invalidResponse.localizedDescription)
    }

    @Test func questionsKeepAnswersWhenGoingBackAndSkipClearsOnlyCurrentAnswer() throws {
        let model = try make(specific: false)
        model.answers.interests = [.art]
        model.advance(.interests)
        model.advance(.interests)
        #expect(model.path == [.recommendations])
        model.path.removeLast()
        #expect(model.answers.interests == [.art])
        model.advance(.interests, skip: true)
        #expect(model.answers.interests.isEmpty)
    }

    @Test func selectionHasNoCountLimitAndRemovingMainSpotClearsStay() throws {
        let model = try make()
        let originalCount = model.selected.count
        for index in 0 ..< 10 {
            model.toggle(.init(place: .init(id: UUID(), name: "Synthetic \(index)",
                                            location: .init(latitude: 0, longitude: 0), visitSeconds: 1800)))
        }
        #expect(model.selected.count == originalCount + 10)
        let chosen = model.selected[0]
        model.mainSpot = .place(chosen.id)
        model.stay = .ninetyMinutes
        model.toggle(chosen)
        #expect(model.selected.count == originalCount + 9)
        #expect(model.mainSpot == .automatic)
        #expect(model.stay == nil)
        #expect(model.planning.places.count == model.selected.count)
    }

    @Test func mainSpotDurationDoesNotPinFirstStop() async throws {
        let model = try make()
        let chosen = try #require(model.selected.last)
        model.path = [.mainSpot]
        model.mainSpot = .place(chosen.id)
        await model.finishMainSpot()
        #expect(model.route == .stay)
        model.stay = .ninetyMinutes
        await model.plan()
        #expect(model.route == .review)
        let input = try #require(model.planning.job?.input)
        #expect(input.places.first(where: { $0.id == chosen.id })?.visitSeconds == 5400)
        #expect(input.firstPlaceID == nil)
    }

    @Test func recommendationFailureKeepsSelectionAndDoesNotRequirePlanning() async throws {
        let search = TripSearchStub()
        search.failing = true
        let planning = PlanningPresenter(interactor: .init(repository: MockPlanningRepository()), initialInput: try MockPlanningRepository.sampleInput())
        let model = TripCreationPresenter(planning: planning, mode: "Mock", specificPlace: false, interactor: .init(searcher: search))
        let original = model.selected.map(\.id)
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        #expect(model.route == .recommendations)
        #expect(model.recommendationError != nil)
        #expect(model.selected.map(\.id) == original)
        #expect(model.planning.job == nil)
        model.finishChoosingPlaces()
        #expect(model.route == .mainSpot)
        await model.finishMainSpot()
        #expect(model.route == .confirmation)
        #expect(model.planning.job == nil)
    }

    @Test func changingNameRequiresReviewAndNeverAppliesOldProposal() async throws {
        let model = try make()
        await model.plan()
        await model.planning.saveReviewedProposal(named: "  Renamed trip  ")
        #expect(model.planning.trips.isEmpty)
        #expect(model.planning.job?.input.title == "Renamed trip")
        await model.planning.saveReviewedProposal(named: "Renamed trip")
        #expect(model.planning.trips.count == 1)
        #expect(model.planning.trips.first?.title == "Renamed trip")
        await model.planning.saveReviewedProposal(named: "Renamed trip")
        #expect(model.planning.trips.count == 1)
    }

    @Test func failedNameRegenerationRetainsDraftAndCannotSaveOldPlan() async throws {
        let repo = TripFlowRepositoryStub()
        let model = try make(repository: repo)
        await model.plan()
        await repo.configure(failing: true)
        await model.planning.saveReviewedProposal(named: "Retained name")
        #expect(model.planning.title == "Retained name")
        #expect(model.planning.job == nil)
        #expect(model.planning.error != nil)
        #expect(model.planning.trips.isEmpty)
        await repo.configure(failing: false)
        await model.planning.request()
        await model.planning.saveReviewedProposal(named: "Retained name")
        #expect(model.planning.trips.first?.title == "Retained name")
    }

    @Test func invalidNameCannotCreateTrip() async throws {
        let model = try make()
        await model.plan()
        await model.planning.saveReviewedProposal(named: " ")
        #expect(model.planning.trips.isEmpty)
        await model.planning.saveReviewedProposal(named: String(repeating: "x", count: 121))
        #expect(model.planning.trips.isEmpty)
    }

    @Test func arrivalIsNotWholeTripCompletion() async throws {
        let model = try make()
        await model.plan()
        await model.planning.apply()
        var trip = try #require(model.planning.trips.first)
        await model.planning.event(.start, trip: trip)
        trip = try #require(model.planning.trips.first)
        await model.planning.event(.arrive, trip: trip)
        trip = try #require(model.planning.trips.first)
        #expect(trip.status == .active)
        #expect(trip.completedStopIDs.isEmpty)
        #expect(trip.currentStopID == trip.nextStop?.id)
        while trip.status == .active {
            if trip.currentStopID == nil {
                await model.planning.event(.arrive, trip: trip)
                trip = try #require(model.planning.trips.first)
            }
            await model.planning.event(.completeStop, trip: trip)
            trip = try #require(model.planning.trips.first)
        }
        #expect(trip.status == .completed)
        #expect(trip.completedStopIDs.count == trip.plan.stops.count)
    }

    @Test func logoutDiscardsLateProposal() async throws {
        let repo = TripFlowRepositoryStub()
        await repo.configure(failing: false, delay: .milliseconds(80))
        let model = try make(repository: repo)
        let operation = Task { await model.plan() }
        while !(await repo.started) { await Task.yield() }
        model.planning.sessionDidChange(.init(account: nil, sessionID: UUID()))
        await operation.value
        #expect(model.planning.job == nil)
        #expect(model.planning.trips.isEmpty)
        #expect(model.route != .review)
    }
}

extension TripCreationTests {
    @Test func expiredProposalRequiresFreshReview() async throws {
        let repo = TripFlowRepositoryStub()
        let model = try make(repository: repo)
        await model.plan()
        await repo.setApplyError(.expired)
        await model.planning.apply()
        #expect(model.planning.needsFreshProposal)
        #expect(model.planning.trips.isEmpty)
        await repo.setApplyError(nil)
        await model.planning.request()
        #expect(!model.planning.needsFreshProposal)
        await model.planning.apply()
        #expect(model.planning.trips.count == 1)
    }

    @Test func lateSearchCannotReplaceNewQueryAndFailureKeepsSelection() async throws {
        let search = TripSearchStub()
        let planning = PlanningPresenter(interactor: .init(repository: MockPlanningRepository()), initialInput: try MockPlanningRepository.sampleInput())
        let model = TripCreationPresenter(planning: planning, mode: "Mock", specificPlace: true, interactor: .init(searcher: search))
        model.query = "old"
        let old = Task { await model.search() }
        while !search.started { await Task.yield() }
        model.query = "new"
        await model.search()
        await old.value
        #expect(model.results.first?.place.name == "new")
        let selected = model.selected.map(\.id)
        search.failing = true
        model.query = "failure"
        await model.search()
        #expect(model.searchError != nil)
        #expect(model.selected.map(\.id) == selected)
        model.query = ""
        await model.search()
        #expect(model.results.isEmpty)
        #expect(!model.isSearching)
    }
    @Test func cancelledRequestKeepsDraftAndCanBeRetried() async throws {
        let repo = TripFlowRepositoryStub()
        await repo.configure(failing: false, delay: .milliseconds(100))
        let model = try make(repository: repo)
        let original = model.selected.map(\.id)
        let operation = Task { await model.plan() }
        while !(await repo.started) { await Task.yield() }
        operation.cancel()
        await operation.value
        #expect(model.route != .review)
        #expect(model.selected.map(\.id) == original)
        #expect(!model.isProcessing)
        #expect(!model.planning.isBusy)
        await repo.configure(failing: false)
        await model.plan()
        #expect(model.route == .review)
    }

    @Test func selectedRecommendationIsAddedOnlyOnce() async throws {
        let model = try make(specific: false)
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        let candidate = try #require(model.batch.places.first)
        let originalCount = model.selected.count
        model.toggle(candidate)
        _ = await model.suggest()
        #expect(model.selected.count == originalCount + 1)
        #expect(Set(model.selected.map(\.id)).count == model.selected.count)
        model.finishChoosingPlaces()
        await model.plan()
        #expect(model.planning.job?.input.places.contains(where: { $0.id == candidate.id }) == true)
    }

    @Test func refreshPreservesEarlierCandidateAndBackAllowsRemovingIt() async throws {
        let model = try make(specific: false)
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        let original = model.selected.map(\.id)
        let first = try #require(model.batch.places.first)
        model.toggle(first)
        _ = await model.suggest()
        #expect(model.selected.contains(where: { $0.id == first.id }))
        model.finishChoosingPlaces()
        model.path.removeLast()
        #expect(model.route == .recommendations)
        #expect(model.selected.first(where: { $0.id == first.id }) == first)
        model.toggle(first)
        #expect(model.selected.map(\.id) == original)
    }

    @Test func discoveryDoesNotNeedTripConfigurationOrAPlanningRequest() async throws {
        let repo = TripFlowRepositoryStub()
        let model = try make(specific: false, repository: repo)
        model.planning.origin = nil
        model.planning.title = ""
        model.planning.finishBy = model.planning.startsAt.addingTimeInterval(-60)
        model.answers.refinements = ["japanese_cuisine", "art_gallery"]
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        #expect(model.route == .recommendations)
        #expect(!model.batch.places.isEmpty)
        #expect(model.recommendationError == nil)
        #expect(model.planning.job == nil)
        #expect(await repo.started == false)
    }

    @Test func surveyDefersPlanningAndEditingItReturnsToExistingConfiguration() async throws {
        let repo = TripFlowRepositoryStub()
        let model = try make(repository: repo)
        let chosen = try #require(model.selected.first)
        model.finishChoosingPlaces()
        await model.finishMainSpot()
        #expect(model.route == .confirmation)
        let originalPath = model.path
        model.push(.mainSpot)
        model.mainSpot = .place(chosen.id)
        await model.finishMainSpot()
        #expect(model.route == .stay)
        model.stay = .ninetyMinutes
        model.finishSurvey()
        #expect(model.path == originalPath)
        #expect(model.planning.places.first(where: { $0.id == chosen.id })?.visitSeconds == 5400)
        #expect(model.selected.first(where: { $0.id == chosen.id })?.place.visitSeconds == chosen.place.visitSeconds)
        model.stay = .flexible
        model.finishSurvey()
        #expect(model.planning.places.first(where: { $0.id == chosen.id })?.visitSeconds == chosen.place.visitSeconds)
        #expect(model.planning.job == nil)
        #expect(await repo.started == false)
    }

    @Test func largerSelectionReachesConfigurationWithoutTruncationOrPlannerRequest() async throws {
        let repo = TripFlowRepositoryStub()
        let model = try make(specific: false, repository: repo)
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        for item in model.batch.places.prefix(10) { model.toggle(item) }
        let ids = model.selected.map(\.id)
        model.finishChoosingPlaces()
        await model.finishMainSpot()
        #expect(model.route == .confirmation)
        #expect(model.selected.count > 6)
        #expect(!model.canConfirm)
        #expect(model.planningHandoffMessage != nil)
        await model.confirm()
        #expect(model.selected.map(\.id) == ids)
        #expect(model.planning.places.map(\.id) == ids)
        #expect(model.error == model.planningHandoffMessage)
        #expect(await repo.started == false)
    }

    @Test func refreshFailurePreservesResultsSelectionAndDisplayMetadata() async throws {
        let search = TripSearchStub()
        let model = try make(specific: false, searcher: search)
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        var chosen = try #require(model.batch.places.first)
        chosen.category = "Synthetic category"
        chosen.address = "Synthetic address"
        model.toggle(chosen)
        let batchIDs = model.batch.places.map(\.id)
        search.failing = true
        _ = await model.suggest()
        #expect(model.recommendationError != nil)
        #expect(model.batch.places.map(\.id) == batchIDs)
        #expect(model.selected.first(where: { $0.id == chosen.id }) == chosen)
        search.failing = false
        _ = await model.suggest()
        #expect(model.recommendationError == nil)
        #expect(model.selected.first(where: { $0.id == chosen.id }) == chosen)
    }

    @Test func partialSearchFailureKeepsSuccessfulResultsAndReportsMissingQuery() async throws {
        let search = TripSearchStub()
        search.failedQueries = ["cafe"]
        let model = try make(specific: false, searcher: search)
        model.answers.interests = [.foodie]
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        #expect(model.batch.places.map(\.place.name) == ["restaurant"])
        #expect(model.batch.warnings.count == 1)
        #expect(model.batch.warnings.first?.contains("cafe") == true)
        #expect(model.recommendationError == nil)
    }

    @Test func refreshRotatesBoundedQueriesAndKeepsEarlierSelectedPlaces() async throws {
        let search = TripSearchStub()
        let model = try make(specific: false, searcher: search)
        model.answers.interests = Set(TripInterest.allCases)
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        let firstQueries = search.queries
        let chosen = try #require(model.batch.places.first)
        model.toggle(chosen)
        _ = await model.suggest()
        #expect(firstQueries.count == 4)
        #expect(search.queries.count == 8)
        #expect(Set(firstQueries).isDisjoint(with: search.queries.suffix(4)))
        #expect(model.selected.contains(chosen))
    }

    @Test func cancelledDiscoveryDiscardsLateResultsAndCanBeRetried() async throws {
        let search = TripSearchStub()
        search.delay = .milliseconds(80)
        let model = try make(specific: false, searcher: search)
        model.advance(.interests)
        let request = Task { await model.suggest() }
        while !search.started { await Task.yield() }
        model.cancelRecommendations()
        _ = await request.value
        #expect(!model.isSuggesting)
        #expect(model.batch.places.isEmpty)
        #expect(model.recommendationError == nil)
        search.delay = nil
        await model.loadRecommendationsIfNeeded()
        #expect(!model.batch.places.isEmpty)
    }

    @Test func changedPreferencesDiscardStaleSearchErrors() async throws {
        let search = TripSearchStub()
        search.delay = .milliseconds(20)
        search.failing = true
        let model = try make(specific: false, searcher: search)
        model.advance(.interests)
        let request = Task { await model.suggest() }
        while !search.started { await Task.yield() }
        model.answers.interests = [.art]
        _ = await request.value
        #expect(model.recommendationError == nil)
        #expect(model.batch.places.isEmpty)
    }

    @Test func recommendationGroupsInterleaveAndDeduplicatePlaceIdentity() async throws {
        let search = TripSearchStub()
        let shared = RecommendedPlace(place: .init(id: UUID(), name: "Shared place", location: .init(latitude: 0, longitude: 0), visitSeconds: 1800))
        let second = RecommendedPlace(place: .init(id: UUID(), name: "Second place", location: .init(latitude: 0, longitude: 0), visitSeconds: 1800))
        let third = RecommendedPlace(place: .init(id: UUID(), name: "Third place", location: .init(latitude: 0, longitude: 0), visitSeconds: 1800))
        search.placesByQuery = ["first": [shared, second], "second": [shared, third]]
        let batch = try await TripCreationInteractor(searcher: search).recommend(queries: ["first", "second"], near: nil, synthetic: true)
        #expect(batch.places.map(\.id) == [shared.id, second.id, third.id])
        #expect(batch.warnings.isEmpty)
        #expect(batch.synthetic)
    }
}
