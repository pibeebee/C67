import Foundation
import Testing
import C67Data
import C67Domain
@testable import C67

@Suite("Connected Hi-Fi trip creation")
@MainActor struct TripCreationTests {
    private func make(specific: Bool = true, repository: any PlanningRepository = MockPlanningRepository()) throws -> TripCreationPresenter {
        let planning = PlanningPresenter(interactor: .init(repository: repository), initialInput: try MockPlanningRepository.sampleInput())
        return TripCreationPresenter(planning: planning, mode: "Mock • memory only", specificPlace: specific,
                                     interactor: .init(searcher: SyntheticTripPlaceSearch()))
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
        #expect(model.path == [.question(.popularity)])
        model.path.removeLast()
        #expect(model.answers.interests == [.art])
        model.advance(.interests, skip: true)
        #expect(model.answers.interests.isEmpty)
    }

    @Test func sixPlaceLimitAndRemovingMainSpot() throws {
        let model = try make()
        for index in 0 ..< 10 {
            model.toggle(.init(place: .init(id: UUID(), name: "Synthetic \(index)",
                                            location: .init(latitude: 0, longitude: 0), visitSeconds: 1800)))
        }
        #expect(model.selected.count == 6)
        let chosen = model.selected[0]
        model.mainSpot = .place(chosen.id)
        model.toggle(chosen)
        #expect(model.selected.count == 5)
        #expect(model.mainSpot == .automatic)
        #expect(model.planning.places.count == 5)
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

    @Test func suggestionFailureKeepsRequiredPlacesAndCanBeSkipped() async throws {
        let repo = TripFlowRepositoryStub()
        await repo.configure(failing: true)
        let model = try make(specific: false, repository: repo)
        let original = model.selected.map(\.id)
        model.path = [.confirmation]
        await model.confirm()
        #expect(model.route == .recommendations)
        #expect(model.error != nil)
        #expect(model.selected.map(\.id) == original)
        model.chooseRecommendations([])
        #expect(model.route == .mainSpot)
        await repo.configure(failing: false)
        await model.plan()
        #expect(model.route == .review)
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
        model.path = [.confirmation]
        await model.confirm()
        let candidate = try #require(model.batch.places.first?.place)
        let originalCount = model.selected.count
        model.chooseRecommendations([candidate, candidate])
        #expect(model.selected.count == originalCount + 1)
        await model.plan()
        #expect(model.planning.job?.input.places.contains(where: { $0.id == candidate.id }) == true)
    }

    @Test func refreshPreservesEarlierCandidateAndBackAllowsRemovingIt() async throws {
        let model = try make(specific: false)
        model.path = [.confirmation]
        await model.confirm()
        let original = model.selected.map(\.id)
        let first = try #require(model.batch.places.first?.place)
        _ = await model.suggest()
        #expect(model.batch.places.first?.id != first.id)
        model.chooseRecommendations([first])
        #expect(model.selected.contains(where: { $0.id == first.id }))
        model.path.removeLast()
        model.chooseRecommendations([])
        #expect(model.selected.map(\.id) == original)
        #expect(model.chosenRecommendations.isEmpty)
    }

}
