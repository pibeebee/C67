import Foundation
import Testing
import MapKit
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

    @Test func recommendationDistanceUsesDevicePointAndRejectsInvalidCoordinates() throws {
        let location = PlanningPoint(latitude: -6.20, longitude: 106.84)
        let place = PlanningPlace(id: UUID(), name: "Synthetic place",
                                  location: .init(latitude: -6.19, longitude: 106.84), visitSeconds: 1800)
        var item = RecommendedPlace(place: place)
        let distance = try #require(item.straightLineDistance(from: location))
        #expect((1_000 ... 1_300).contains(distance))
        #expect(item.straightLineDistance(from: nil) == nil)
        #expect(item.distanceDescription(from: nil) == "Distance unavailable")
        item.place.location.latitude = 100
        #expect(item.straightLineDistance(from: location) == nil)
    }

    @Test func itineraryTimesUse24HourClockInTripTimeZone() throws {
        let parser = ISO8601DateFormatter()
        let samples = [
            ("2026-11-15T17:00:00Z", "00:00"),
            ("2026-11-16T01:00:00Z", "08:00"),
            ("2026-11-16T05:00:00Z", "12:00"),
            ("2026-11-16T08:14:00Z", "15:14"),
        ]
        for (value, expected) in samples {
            let date = try #require(parser.date(from: value))
            for locale in [Locale(identifier: "en_US"), Locale(identifier: "id_ID")] {
                #expect(ItineraryFormatting.time(date, zone: "Asia/Jakarta", locale: locale) == expected)
            }
        }
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

    @Test func newTripClearsPreviousSelectionAndPreservesStartingPoint() throws {
        let previous = try make()
        let planning = previous.planning
        let origin = planning.origin
        let originLabel = planning.originLabel
        let oldIDs = Set(previous.selected.map(\.id))
        previous.mainSpot = .place(try #require(previous.selected.first).id)
        previous.stay = .ninetyMinutes
        planning.preferences = "Previous preferences"
        planning.enginePreferences?.mainSpotID = previous.mainSpot.placeID

        planning.startNewTrip()
        let next = TripCreationAssembly.makePresenter(planning: planning, mode: "Mock • memory only", specificPlace: false)
        #expect(next.selected.isEmpty)
        #expect(planning.places.isEmpty)
        #expect(planning.preferences.isEmpty)
        #expect(planning.enginePreferences?.mainSpotID == nil)
        #expect(planning.origin == origin)
        #expect(planning.originLabel == originLabel)
        #expect(next.mainSpot == .automatic)
        #expect(next.stay == nil)

        let place = RecommendedPlace(place: .init(id: UUID(), name: "New place",
                                                  location: .init(latitude: -6.2, longitude: 106.8), visitSeconds: 1800))
        next.toggle(place)
        next.finishChoosingPlaces()
        #expect(next.route == .mainSpot)
        #expect(next.selected.map(\.id) == [place.id])
        #expect(planning.draftInput?.places.map(\.id) == [place.id])
        #expect(oldIDs.isDisjoint(with: Set(planning.places.map(\.id))))
    }

    @Test func loadingDuringNewTripDoesNotRestoreThePreviousPendingJob() async throws {
        let model = try make()
        await model.planning.request()
        #expect(model.planning.job != nil)
        model.planning.startNewTrip()
        await model.planning.load()
        #expect(model.planning.job == nil)
        #expect(model.planning.places.isEmpty)
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
        #expect(model.route == .review)
        #expect(model.planning.job?.purpose == .plan)
    }

    @Test func reasonableOrderRenameSavesExactTitleAndOpensTheSameRecommendation() async throws {
        let repository = try PocketIntegrationFixture.repository()
        var input = PocketIntegrationFixture.input()
        input.places = Array(try PocketIntegrationFixture.searchablePlaces().prefix(5))
        let planning = PlanningPresenter(interactor: .init(repository: repository), initialInput: input)
        await planning.request(.firstItinerary)
        let before = try #require(planning.job?.result?.proposal?.experiencePlan)
        await planning.saveReviewedProposal(named: "  Live order acceptance  ")
        #expect(planning.error == nil)
        let trip = try #require(planning.trips.first)
        #expect(trip.title == "Live order acceptance")
        #expect(trip.input.title == trip.title)
        #expect(trip.plan.input.title == trip.title)
        #expect(trip.plan.experiencePlan == before)
        #expect(planning.openTripID == trip.id)
        #expect(planning.job == nil)
        #expect(await repository.personalTrips().count == 1)
    }

    private func orderedPlanning(_ repository: TripFlowRepositoryStub) async throws -> PlanningPresenter {
        var input = PocketIntegrationFixture.input()
        input.places = Array(try PocketIntegrationFixture.searchablePlaces().prefix(5))
        let planning = PlanningPresenter(interactor: .init(repository: repository), initialInput: input)
        await planning.request(.firstItinerary)
        _ = try #require(planning.job?.result?.proposal?.experiencePlan)
        return planning
    }

    @Test func duplicateSaveWhileRenamingDoesNotApplyOrRenameTwice() async throws {
        let repo = TripFlowRepositoryStub(supportsOnDevicePlanning: true, base: try PocketIntegrationFixture.repository())
        let planning = try await orderedPlanning(repo)
        await repo.holdRename()
        let save = Task { await planning.saveReviewedProposal(named: "First name") }
        while !(await repo.renameStarted) { await Task.yield() }
        #expect(planning.isBusy)
        await planning.saveReviewedProposal(named: "Second name")
        await planning.apply()
        #expect(await repo.renameCalls == 1)
        #expect(await repo.applyCalls == 0)
        await repo.releaseRename()
        await save.value
        #expect(planning.trips.first?.title == "First name")
        #expect(await repo.applyCalls == 1)
        #expect(!planning.isBusy)
    }

    @Test func sessionChangeDuringRenameDoesNotOpenOrApplyStaleTrip() async throws {
        let repo = TripFlowRepositoryStub(supportsOnDevicePlanning: true, base: try PocketIntegrationFixture.repository())
        let planning = try await orderedPlanning(repo)
        await repo.holdRename()
        let save = Task { await planning.saveReviewedProposal(named: "Stale name") }
        while !(await repo.renameStarted) { await Task.yield() }
        planning.sessionDidChange(.init(account: nil, sessionID: UUID()))
        await repo.releaseRename()
        await save.value
        #expect(planning.trips.isEmpty)
        #expect(planning.openTripID == nil)
        #expect(planning.job == nil)
        #expect(planning.error == nil)
        #expect(await repo.applyCalls == 0)
        #expect(!planning.isBusy)
    }

    @Test func saveFailureRetainsRenamedRecommendationForRetry() async throws {
        let repo = TripFlowRepositoryStub(supportsOnDevicePlanning: true, base: try PocketIntegrationFixture.repository())
        let planning = try await orderedPlanning(repo)
        let plan = planning.job?.result?.proposal?.experiencePlan
        await repo.setApplyError(.unavailable)
        await planning.saveReviewedProposal(named: "Retry name")
        #expect(planning.error != nil)
        #expect(planning.trips.isEmpty)
        #expect(planning.job?.input.title == "Retry name")
        #expect(planning.job?.result?.proposal?.experiencePlan == plan)
        #expect(!planning.isBusy)
        await repo.setApplyError(nil)
        await planning.apply()
        #expect(planning.error == nil)
        #expect(planning.trips.first?.title == "Retry name")
        #expect(planning.trips.first?.plan.experiencePlan == plan)
        #expect(await repo.renameCalls == 1)
    }

    @Test func failedRenameCanRetryTheRequestedNameWithoutSavingTheOldTitle() async throws {
        let repo = TripFlowRepositoryStub(supportsOnDevicePlanning: true, base: try PocketIntegrationFixture.repository())
        let planning = try await orderedPlanning(repo)
        let original = try #require(planning.job)
        await repo.setRenameError(.unavailable)
        await planning.saveReviewedProposal(named: "Requested name")
        #expect(planning.error != nil)
        #expect(planning.job == original)
        #expect(planning.trips.isEmpty)
        #expect(await repo.applyCalls == 0)
        #expect(!planning.isBusy)

        await repo.setRenameError(nil)
        await planning.saveReviewedProposal(named: "Requested name")
        #expect(planning.error == nil)
        #expect(planning.trips.first?.title == "Requested name")
        #expect(planning.trips.first?.plan.experiencePlan == original.result?.proposal?.experiencePlan)
        #expect(await repo.renameCalls == 2)
        #expect(await repo.applyCalls == 1)
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

    @Test func surveyDirectlyProcessesDurationAndFlexibleRestoresTheOriginal() async throws {
        let repo = TripFlowRepositoryStub()
        let model = try make(repository: repo)
        let chosen = try #require(model.selected.first)
        model.finishChoosingPlaces()
        model.mainSpot = .place(chosen.id)
        await model.finishMainSpot()
        #expect(model.route == .stay)
        #expect(model.planning.job == nil)
        model.stay = .ninetyMinutes
        await model.finishSurvey()
        #expect(model.route == .review)
        #expect(model.planning.places.first(where: { $0.id == chosen.id })?.visitSeconds == 5400)
        #expect(model.selected.first(where: { $0.id == chosen.id })?.place.visitSeconds == chosen.place.visitSeconds)
        model.path.removeLast()
        model.stay = .flexible
        await model.finishSurvey()
        #expect(model.route == .review)
        #expect(model.planning.places.first(where: { $0.id == chosen.id })?.visitSeconds == chosen.place.visitSeconds)
        #expect(model.planning.job?.input.firstPlaceID == nil)
        #expect(await repo.started == true)
    }

    @Test func largerSelectionStopsAtPlannerBoundaryWithoutTruncationOrPlannerRequest() async throws {
        let repo = TripFlowRepositoryStub()
        let model = try make(specific: false, repository: repo)
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        for item in model.batch.places.prefix(10) { model.toggle(item) }
        let ids = model.selected.map(\.id)
        model.finishChoosingPlaces()
        await model.finishMainSpot()
        #expect(model.route == .mainSpot)
        #expect(model.selected.count > 6)
        #expect(!model.canPlan)
        #expect(model.planningHandoffMessage != nil)
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
        let shared = RecommendedPlace(place: .init(id: UUID(), name: "Shared place", location: TripDiscoveryArea.center, visitSeconds: 1800))
        let second = RecommendedPlace(place: .init(id: UUID(), name: "Second place", location: TripDiscoveryArea.center, visitSeconds: 1800))
        let third = RecommendedPlace(place: .init(id: UUID(), name: "Third place", location: TripDiscoveryArea.center, visitSeconds: 1800))
        search.placesByQuery = ["first": [shared, second], "second": [shared, third]]
        let batch = try await TripCreationInteractor(searcher: search).recommend(queries: ["first", "second"], near: nil, synthetic: true)
        #expect(batch.places.map(\.id) == [shared.id, second.id, third.id])
        #expect(batch.warnings.isEmpty)
        #expect(batch.synthetic)
    }

    @Test func unrelatedPreferencesSearchSeparatelyRatherThanAsOneCombinedVenue() async throws {
        let search = TripSearchStub()
        let model = try make(specific: false, searcher: search)
        model.answers.refinements = ["ramen", "independent_bookstore", "jogging"]
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        #expect(Set(search.queries.map { $0.lowercased() }) == ["ramen shop", "independent bookstore", "jogging park"])
        #expect(model.batch.places.count == 3)
        #expect(Set(model.batch.places.map(\.place.name)) == Set(search.queries))
    }

    @Test func searchResultsAreNotLimitedByCountryOrFormerPlanningAreas() async throws {
        let search = TripSearchStub()
        let local = RecommendedPlace(place: .init(id: UUID(), name: "Synthetic Jakarta bookstore", location: TripDiscoveryArea.center, visitSeconds: 1800))
        let foreign = RecommendedPlace(place: .init(id: UUID(), name: "Synthetic Australian bookstore", location: .init(latitude: -37.8136, longitude: 144.9631), visitSeconds: 1800))
        search.placesByQuery = ["bookstore": [foreign, local]]
        let interactor = TripCreationInteractor(searcher: search)
        let manual = try await interactor.search("bookstore", near: foreign.place.location)
        let batch = try await interactor.recommend(queries: ["bookstore"], near: foreign.place.location, synthetic: true)
        #expect(manual.map(\.id) == [foreign.id, local.id])
        #expect(batch.places.map(\.id) == [foreign.id, local.id])
        search.placesByQuery = ["bookstore": [foreign]]
        let empty = try await interactor.recommend(queries: ["bookstore"], near: nil, synthetic: true)
        #expect(empty.places.map(\.id) == [foreign.id])
        #expect(empty.warnings.isEmpty)
    }

    @Test func searchAcceptsAnyValidCoordinatesAndRejectsInvalidCoordinates() {
        for point in [TripDiscoveryArea.center, .init(latitude: -37.8136, longitude: 144.9631), .init(latitude: -8.65, longitude: 115.2), .init(latitude: -6.1783, longitude: 106.6319),
                      .init(latitude: -6.4025, longitude: 106.7942), .init(latitude: -6.2383, longitude: 106.9756),
                      .init(latitude: -6.595, longitude: 106.8166)] {
            #expect(TripDiscoveryArea.contains(point))
        }
        for point in [PlanningPoint(latitude: .nan, longitude: 106.84), .init(latitude: -6.2, longitude: .infinity),
                      .init(latitude: 91, longitude: 106.84)] {
            #expect(!TripDiscoveryArea.contains(point))
        }
        let delta = 180 / Double.pi / 6_371_000
        #expect(TripDiscoveryArea.contains(.init(latitude: TripDiscoveryArea.center.latitude + 59_000 * delta, longitude: TripDiscoveryArea.center.longitude)))
        #expect(TripDiscoveryArea.contains(.init(latitude: TripDiscoveryArea.center.latitude + 61_000 * delta, longitude: TripDiscoveryArea.center.longitude)))
        #expect(TripDiscoveryArea.contains(TripDiscoveryArea.center, countryCode: "ID"))
        #expect(TripDiscoveryArea.contains(TripDiscoveryArea.center, countryCode: "AU"))
    }

    @Test func missingStartingPointDoesNotInventAnOriginAndCanResumeProcessing() async throws {
        let repo = TripFlowRepositoryStub()
        let model = try make(repository: repo)
        model.planning.origin = nil
        model.finishChoosingPlaces()
        await model.finishMainSpot()
        #expect(model.route == .mainSpot)
        #expect(model.error?.contains("starting point") == true)
        #expect(model.planning.origin == nil)
        #expect(await repo.started == false)
        model.planning.origin = TripDiscoveryArea.center
        await model.plan()
        #expect(model.route == .review)
    }

    @Test func directProcessingBuildsUntimedRecommendationWithoutAvailabilityForm() async throws {
        let repository = try PocketIntegrationFixture.repository()
        let model = try make(repository: repository)
        model.selected = [.init(place: .init(id: UUID(), name: "Unverified trip selection",
                                             location: .init(latitude: -6.2515, longitude: 106.8), visitSeconds: 2700))]
        model.finishChoosingPlaces()
        await model.finishMainSpot()
        #expect(model.route == .review)
        #expect(model.planning.job?.purpose == .firstItinerary)
        let proposal = try #require(model.planning.job?.result?.proposal)
        #expect(proposal.experiencePlan != nil)
        #expect(proposal.stops.map(\.id) == model.selected.map { $0.place.id })
        #expect(proposal.stops.allSatisfy { $0.arrivalAt == nil && $0.departureAt == nil })
        #expect(model.availabilityPlaces.isEmpty)
        #expect(model.error == nil)
        #expect(model.planning.enginePreferences?.allowsAIProcessing == true)
    }

    @Test func previouslySelectedForeignPlaceCanReachThePlanner() async throws {
        let repo = TripFlowRepositoryStub()
        let model = try make(repository: repo)
        let foreign = RecommendedPlace(place: .init(id: UUID(), name: "Synthetic earlier overseas selection",
                                                    location: .init(latitude: -37.8136, longitude: 144.9631), visitSeconds: 1800))
        model.selected.append(foreign)
        model.finishChoosingPlaces()
        await model.finishMainSpot()
        #expect(model.selected.contains(foreign))
        #expect(model.error == nil)
        #expect(model.planning.job?.result?.proposal != nil)
        #expect(await repo.started == true)
    }

    @Test func correctingSelectionAfterCountFailureClearsErrorAndCanProceed() async throws {
        let model = try make(specific: false)
        model.advance(.interests)
        await model.loadRecommendationsIfNeeded()
        let extras = Array(model.batch.places.prefix(4))
        for item in extras { model.toggle(item) }
        #expect(model.selected.count == 7)
        model.finishChoosingPlaces()
        await model.finishMainSpot()
        #expect(model.error == model.planningHandoffMessage)
        model.path.removeLast()
        for item in extras { model.toggle(item) }
        #expect(model.selected.count == 3)
        #expect(model.error == nil)
        model.finishChoosingPlaces()
        await model.finishMainSpot()
        #expect(model.route == .review)
        #expect(model.planning.job?.input.places.count == 3)
    }

    @Test func emptyAppleSearchIsDifferentFromProviderOutageOrThrottling() {
        #expect(MapKitTripPlaceSearch.isEmptyResult(NSError(domain: MKErrorDomain, code: Int(MKError.Code.placemarkNotFound.rawValue))))
        #expect(!MapKitTripPlaceSearch.isEmptyResult(NSError(domain: MKErrorDomain, code: Int(MKError.Code.loadingThrottled.rawValue))))
        #expect(!MapKitTripPlaceSearch.isEmptyResult(NSError(domain: MKErrorDomain, code: Int(MKError.Code.serverFailure.rawValue))))
        #expect(!MapKitTripPlaceSearch.isEmptyResult(NSError(domain: NSURLErrorDomain, code: Int(MKError.Code.placemarkNotFound.rawValue))))
    }
}
