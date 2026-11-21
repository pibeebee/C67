import Foundation
import Testing
import MapKit
import C67Data
import C67Domain
@testable import C67

@Suite("Connected Hi-Fi trip creation")
@MainActor struct TripCreationTests {
    @Test func newTripUsesV42EvenWithAnOlderSavedMethod() throws {
        let key = "io.pibeebee.c67.orderingMethod"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(PlanningOrderingMethod.luna.rawValue, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let presenter = try make(repository: TripFlowRepositoryStub(supportsOnDevicePlanning: true))
        presenter.finishChoosingPlaces()
        #expect(presenter.planning.enginePreferences?.orderingMethod == .hybridV42)
        #expect(presenter.usesV41)
        #expect(!presenter.usesFoundationModels)
    }

    @Test func departureFallbackUsesOnlyTheMatchingForecastHour() throws {
        let data = Data(#"{"hourly_units":{"time":"unixtime","temperature_2m":"°C"},"hourly":{"time":[3600,7200],"temperature_2m":[24,29],"weather_code":[0,61]}}"#.utf8)
        let reading = try DepartureWeatherLoader.decodeOpenMeteo(data, departure: Date(timeIntervalSince1970: 7500))
        #expect(reading.temperature.value == 29)
        #expect(reading.condition == "Rain")
        #expect(reading.source == "Open-Meteo")
        #expect(throws: DepartureWeatherLoader.ForecastFailure.noForecastForDeparture) {
            try DepartureWeatherLoader.decodeOpenMeteo(data, departure: Date(timeIntervalSince1970: 12_000))
        }
        #expect(throws: (any Error).self) {
            try DepartureWeatherLoader.decodeOpenMeteo(data, departure: Date(timeIntervalSince1970: 11000))
        }
        let badUnits = Data(#"{"hourly_units":{"time":"unixtime","temperature_2m":"°F"},"hourly":{"time":[3600],"temperature_2m":[72],"weather_code":[0]}}"#.utf8)
        #expect(throws: (any Error).self) {
            try DepartureWeatherLoader.decodeOpenMeteo(badUnits, departure: Date(timeIntervalSince1970: 3600))
        }
    }

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

    @Test func selectionStopsAtSixAndRemovingMainSpotClearsStay() throws {
        let model = try make()
        for index in 0 ..< 10 {
            model.toggle(.init(place: .init(id: UUID(), name: "Synthetic \(index)",
                                            location: .init(latitude: 0, longitude: 0), visitSeconds: 1800)))
        }
        #expect(model.selected.count == TripCreationPresenter.maximumPlaces)
        #expect(!model.canAddPlace)
        let chosen = model.selected[0]
        model.mainSpot = .place(chosen.id)
        model.stay = .ninetyMinutes
        model.toggle(chosen)
        #expect(model.selected.count == TripCreationPresenter.maximumPlaces - 1)
        #expect(model.canAddPlace)
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

    @Test func newCreationRecoversAnInterruptedPendingItinerary() async throws {
        let repository = TripFlowRepositoryStub(supportsOnDevicePlanning: true)
        let model = try make(repository: repository)
        let input = try #require(model.planning.draftInput)
        let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
        var pending = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input,
                                  tripID: nil, baseRevision: nil, result: nil,
                                  errorCode: "ORDER_CONNECTION_INTERRUPTED", createdAt: .now)
        pending.command = command
        await repository.setPendingJob(pending)
        model.planning.startNewTrip()
        let restored = await model.planning.recoverPendingCreation()
        #expect(restored?.id == pending.id)
        #expect(model.planning.firstItineraryJob?.id == pending.id)
        #expect(model.planning.draftInput == input)
        model.planning.startNewTrip()
        #expect(model.planning.firstItineraryJob?.id == pending.id)
    }

    @Test func failedTripRefreshPreservesPreviouslyLoadedTrips() async throws {
        let repository = TripFlowRepositoryStub()
        let model = try make(repository: repository)
        await model.planning.request()
        await model.planning.apply()
        let before = model.planning.trips
        #expect(!before.isEmpty)
        await repository.setTripsError(.unavailable)
        await model.planning.load()
        #expect(model.planning.trips == before)
        #expect(model.planning.tripListError == PlanningError.unavailable.localizedDescription)
        await repository.setTripsError(nil)
        await model.planning.load()
        #expect(model.planning.tripListError == nil)
        #expect(model.planning.trips == before)
    }

    @Test func failedAutomaticArrivalWaitsForManualRetryAndKeepsIdentity() async throws {
        let repository = TripFlowRepositoryStub()
        let model = try make(repository: repository)
        await model.planning.request()
        await model.planning.apply()
        let planned = try #require(model.planning.trips.first)
        await model.planning.event(.start, trip: planned)
        let active = try #require(model.planning.trips.first)
        await repository.setEventError(.unavailable)
        #expect(model.planning.claimAutomaticArrival(for: active))
        await model.planning.event(.arrive, trip: active)
        #expect(!model.planning.claimAutomaticArrival(for: active))
        #expect(!model.planning.claimAutomaticArrival(for: active))
        await model.planning.event(.arrive, trip: active)
        let arrivals = await repository.recordedEvents.filter { $0.kind == .arrive }
        #expect(arrivals.count == 2)
        #expect(arrivals[0].requestID == arrivals[1].requestID)
    }

    @Test func reviewRetryRepeatsRouteWithoutRequestingOrApplyingAPlan() async throws {
        let repo = TripFlowRepositoryStub()
        let planning = try make(repository: repo).planning
        await planning.request()
        let original = try #require(planning.job)
        await repo.setRouteError(.unavailable)
        await planning.updateExperienceRoute()
        #expect(planning.reviewIssue?.operation == .changeRoute(order: nil, departure: nil))
        #expect(planning.job == original)
        await repo.setTripsError(.unavailable)
        await planning.load(resumesJobs: false)
        #expect(planning.reviewIssue?.operation == .changeRoute(order: nil, departure: nil))
        #expect(planning.issues[.tripList]?.operation == .loadTrips)
        await repo.setRouteError(nil)
        await planning.retryReviewIssue()
        #expect(await repo.routeJobIDs == [original.id, original.id])
        #expect(await repo.requests.count == 1)
        #expect(await repo.applyCalls == 0)
        #expect(planning.reviewIssue == nil)
        #expect(planning.tripListError != nil)
    }

    @Test func rejectedStopOrderKeepsThePreviousItineraryAndExplainsTheConflict() async throws {
        let repo = TripFlowRepositoryStub()
        let planning = try make(repository: repo).planning
        await planning.request()
        let original = try #require(planning.job)
        let stops = try #require(original.result?.proposal?.stops)
        let reversed = stops.reversed().map(\.id)
        #expect(reversed != stops.map(\.id))

        await repo.setRouteError(.failed("V41_ACCESS_CONFLICT"))
        await planning.updateExperienceRoute(orderedIDs: reversed)

        #expect(planning.job == original)
        #expect(planning.reviewIssue?.operation == .changeRoute(order: reversed, departure: nil))
        #expect(planning.reviewIssue?.message.contains("opening hours") == true)
        #expect(await repo.routeJobIDs == [original.id])
        #expect(await repo.requests.count == 1)
        #expect(await repo.applyCalls == 0)
    }

    @Test func timedReviewRejectsAnOrderThatFinishesAfterTheDeadline() async throws {
        let repo = TripFlowRepositoryStub()
        let planning = try make(repository: repo).planning
        let origin = try #require(planning.origin)
        planning.places = [
            PlanningPlace(id: UUID(), name: "Nearby", location: .init(latitude: origin.latitude + 0.001, longitude: origin.longitude), visitSeconds: 1800),
            PlanningPlace(id: UUID(), name: "Farther away", location: .init(latitude: origin.latitude + 0.008, longitude: origin.longitude), visitSeconds: 1800),
        ]
        await planning.request()
        let finish = try #require(planning.job?.result?.proposal?.finishesAt)
        planning.finishBy = finish.addingTimeInterval(1)
        planning.draftChanged()
        await planning.request()
        let previous = try #require(planning.job)
        try #require(previous.result?.proposal?.feasible == true)
        let reversed = Array(planning.places.reversed())

        await planning.updateTimedReviewOrder(reversed)

        #expect(planning.job == previous)
        #expect(planning.draftInput == previous.input)
        #expect(planning.reviewIssue?.operation == .changeRoute(order: reversed.map(\.id), departure: nil))
        #expect(planning.reviewIssue?.recovery == nil)
    }

    @Test func statusRecoveryReadsTheSameJobWithoutASecondPlanningRequest() async throws {
        let repo = TripFlowRepositoryStub()
        let planning = try make(repository: repo).planning
        await repo.setInterruptsStatusRead(true)
        await planning.request()
        let id = try #require(planning.job?.id)
        #expect(planning.creationIssue?.certainty == .unconfirmed)
        #expect(planning.creationIssue?.recovery == .checkStatus)
        await repo.setInterruptsStatusRead(false)
        await planning.checkStatus()
        #expect(await repo.statusReadIDs == [id, id])
        #expect(await repo.requests.count == 1)
        #expect(planning.job?.status == .succeeded)
        #expect(planning.creationIssue == nil)
    }

    @Test func mainSpotLoadFailureRetriesUnconfirmedRequestWithTheSameInput() async throws {
        let repo = TripFlowRepositoryStub(supportsOnDevicePlanning: true)
        let model = try make(repository: repo)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: model.planning.timeZone))
        let start = try #require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: .now))
        model.planning.startsAt = start
        model.planning.finishBy = start.addingTimeInterval(4 * 3600)
        model.finishChoosingPlaces()
        let selected = model.selected.map(\.id)
        model.selectMainSpot(.place(try #require(selected.first)))

        await repo.configure(failing: true)
        await model.finishMainSpot()
        #expect(model.route == .mainSpot)
        #expect(model.connectionNotice == .loadFailed)
        #expect(!model.checksExistingRequest)
        #expect(model.selected.map(\.id) == selected)

        await model.plan()
        let requests = await repo.requests
        #expect(requests.count == 2)
        #expect(requests.first == requests.last)
        #expect(requests.first?.input.enginePreferences?.mainSpotID == selected.first)
    }

    @Test func requestRecoveryPreservesUnconfirmedIdentityUntilFinalFailure() async throws {
        let repo = TripFlowRepositoryStub()
        let planning = try make(repository: repo).planning
        await repo.configure(failing: true)
        await planning.request()
        planning.draftChanged()
        await planning.request()
        let requests = await repo.requests
        #expect(requests.count == 2)
        #expect(requests.first?.requestID == requests.last?.requestID)
        planning.title = "Changed trip"
        planning.draftChanged()
        await planning.request()
        #expect(await repo.requests.last?.requestID != requests.last?.requestID)

        await repo.configure(failing: false)
        await planning.request()
        await repo.setApplyError(.unavailable)
        await planning.apply()
        await repo.setApplyError(.invalidResponse)
        await planning.retryReviewIssue()
        #expect(planning.reviewIssue?.certainty == .unconfirmed)
        await repo.setApplyError(.rateLimited)
        await planning.retryReviewIssue()
        #expect(planning.reviewIssue?.recovery == .wait)
        await repo.setApplyError(nil)
        await planning.retryReviewIssue()
        let applyIDs = await repo.appliedRequestIDs
        #expect(applyIDs.count == 4)
        #expect(Set(applyIDs.prefix(3)).count == 1)
        #expect(applyIDs.first != applyIDs.last)
        #expect(planning.trips.count == 1)
    }

    @Test func deleteFailureIsScopedToTheSavedTripAndPreservesItsSnapshot() async throws {
        let repo = TripFlowRepositoryStub()
        let planning = try make(repository: repo).planning
        await planning.request()
        await planning.apply()
        let trip = try #require(planning.trips.first)
        await repo.setDeleteError(.unavailable)
        #expect(await planning.deleteTrip(trip) == false)
        #expect(planning.trips == [trip])
        #expect(planning.issues[.savedTrip(trip.id)]?.operation == .delete)
        #expect(planning.tripListError == nil)
        #expect(planning.reviewIssue == nil)
        await repo.setDeleteError(nil)
        #expect(await planning.deleteTrip(trip))
        #expect(planning.trips.isEmpty)
        #expect(planning.issues[.savedTrip(trip.id)] == nil)
    }

    @Test func openingHoursRetryPerformsOnlyTheRequestedPlaceLookup() async throws {
        let repo = TripFlowRepositoryStub()
        let planning = try make(repository: repo).planning
        await planning.request()
        let original = try #require(planning.job)
        await repo.setHours(.init(status: "temporary_error"))
        #expect(await planning.openingHours(placeID: "I1A").status == "temporary_error")
        await repo.setHours(.init(status: "unavailable"))
        #expect(await planning.openingHours(placeID: "I1A").status == "unavailable")
        #expect(await repo.lookedUpHoursIDs == ["I1A", "I1A"])
        #expect(await repo.requests.count == 1)
        #expect(await repo.applyCalls == 0)
        #expect(planning.job == original)
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

    @Test func automaticV4FallbackKeepsTomorrowInReviewAndAfterSavingAndReopening() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-30T23:30:00+07:00"))
        let tomorrow = try #require(ISO8601DateFormatter().date(from: "2026-12-01T09:00:00+07:00"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = directory.appendingPathComponent("trips.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try PocketIntegrationFixture.repository(storageURL: storage, jobClock: { now })
        let model = try v4DateFlow(repository: repository, now: now, automatic: true)
        let selectedIDs = Set(model.selected.map(\.id))

        model.finishChoosingPlaces()
        await model.finishMainSpot()

        #expect(model.route == .review)
        let proposal = try #require(model.reviewProposal)
        let job = try #require(model.planning.firstItineraryJob)
        #expect(proposal.estimatedExperienceDeparture == tomorrow)
        #expect(proposal.rescheduledFromDate != nil)
        #expect(job.originalInput?.startsAt == now)
        #expect(job.input == proposal.input)
        #expect(model.planning.draftInput == proposal.input)
        #expect(Set(proposal.stops.map(\.id)) == selectedIDs)

        await model.planning.saveReviewedProposal(named: proposal.input.title)
        #expect(model.planning.error == nil)
        let openedTripID = try #require(model.planning.openTripID)
        let reopened = try PocketIntegrationFixture.repository(storageURL: storage, jobClock: { now })
        let reopenedPlanning = PlanningPresenter(interactor: .init(repository: reopened))
        await reopenedPlanning.load()
        let saved = try #require(reopenedPlanning.trips.first(where: { $0.id == openedTripID }))
        #expect(saved.input.startsAt == tomorrow)
        #expect(saved.plan.input == saved.input)
        #expect(saved.plan.estimatedExperienceDeparture == tomorrow)
        #expect(saved.plan.rescheduledFromDate == proposal.rescheduledFromDate)
        #expect(Set(saved.plan.stops.map(\.id)) == selectedIDs)
    }

    @Test func explicitTodayStaysSelectedUntilTheTryTomorrowActionCreatesANewRequest() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-30T23:30:00+07:00"))
        let tomorrow = try #require(ISO8601DateFormatter().date(from: "2026-12-01T09:00:00+07:00"))
        let repository = try PocketIntegrationFixture.repository(jobClock: { now })
        let model = try v4DateFlow(repository: repository, now: now, automatic: false)

        model.finishChoosingPlaces()
        await model.finishMainSpot()

        let todayJob = try #require(model.planning.firstItineraryJob)
        #expect(model.route == .mainSpot)
        #expect(model.canTryTomorrow)
        #expect(todayJob.status == .failed)
        #expect(todayJob.errorCode == "V4_TODAY_TOO_SHORT")
        #expect(todayJob.input.startsAt == now)
        #expect(model.planning.startsAt == now)
        #expect(model.reviewProposal == nil)

        await model.tryTomorrow()

        #expect(model.route == .review)
        #expect(!model.canTryTomorrow)
        let tomorrowJob = try #require(model.planning.firstItineraryJob)
        let proposal = try #require(model.reviewProposal)
        #expect(tomorrowJob.id != todayJob.id)
        #expect(tomorrowJob.command?.requestID != todayJob.command?.requestID)
        #expect(tomorrowJob.command?.input.startsAt == tomorrow)
        #expect(tomorrowJob.command?.input.enginePreferences?.usesAutomaticTripDate == false)
        #expect(proposal.estimatedExperienceDeparture == tomorrow)
        #expect(proposal.rescheduledFromDate == nil)
        #expect(Set(proposal.stops.map(\.id)) == Set(model.selected.map(\.id)))
    }

    @Test func v41UsesTheTimingAnswerAndSavesTomorrowWithoutLuna() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-30T12:00:00+07:00"))
        let tomorrow = try #require(ISO8601DateFormatter().date(from: "2026-12-01T09:00:00+07:00"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("trip.json")
        let repository = try PocketIntegrationFixture.repository(storageURL: storage, jobClock: { now })
        let model = try v4DateFlow(repository: repository, now: now, automatic: true, method: .hybridV41)
        model.answers.timing = .tomorrow
        model.finishChoosingPlaces()
        model.prepareScheduleOptions()
        #expect(model.planning.startsAt == tomorrow)
        await model.finishMainSpot()
        let proposal = try #require(model.reviewProposal)
        #expect(model.route == .review)
        let departure = try #require(proposal.estimatedExperienceDeparture)
        #expect(PlanningDayWindow.isSameDay(departure, tomorrow, timeZone: proposal.input.timeZone))
        #expect(departure >= tomorrow && departure < proposal.input.finishBy)
        #expect(proposal.scheduleAssessment?.modelCalls == 0)
        #expect(proposal.experiencePlan == nil)
        #expect(model.planning.draftInput == proposal.input)
        await model.planning.saveReviewedProposal(named: "Tomorrow without Luna")
        #expect(model.planning.error == nil)
        let reopened = try PocketIntegrationFixture.repository(storageURL: storage)
        let saved = try #require(await reopened.personalTrips().first)
        #expect(saved.title == "Tomorrow without Luna")
        #expect(saved.input.startsAt == tomorrow)
        #expect(saved.plan.usesExperienceFlow)
    }

    @Test func v41ScheduleEditTakesPrecedenceOverTheEarlierTimingAnswer() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-30T12:00:00+07:00"))
        let selectedDay = try #require(ISO8601DateFormatter().date(from: "2026-12-03T09:00:00+07:00"))
        let repository = try PocketIntegrationFixture.repository(jobClock: { now })
        let model = try v4DateFlow(repository: repository, now: now, automatic: true, method: .hybridV41)
        model.answers.timing = .tomorrow
        model.finishChoosingPlaces()
        model.prepareScheduleOptions()
        model.changeTripDate(selectedDay)
        await model.finishMainSpot()
        let proposal = try #require(model.reviewProposal)
        #expect(proposal.input.startsAt == selectedDay)
        #expect(proposal.scheduleAssessment?.modelCalls == 0)
    }

    @Test func v41RecalculatesAChangedDurationAfterManualReordering() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-30T12:00:00+07:00"))
        let repository = try PocketIntegrationFixture.repository(jobClock: { now })
        let model = try v4DateFlow(repository: repository, now: now, automatic: true, method: .hybridV41)
        model.answers.timing = .tomorrow
        model.finishChoosingPlaces()
        await model.finishMainSpot()
        let initial = try #require(model.reviewProposal)
        let ids = Array(initial.stops.map(\.id).reversed())
        await model.planning.updateExperienceRoute(orderedIDs: ids)
        #expect(model.planning.error == nil)
        model.planning.places[0].visitSeconds = 3600
        model.planning.draftChanged()
        await model.planning.request()
        #expect(model.planning.error == nil)
        let updated = try #require(model.planning.job?.result?.proposal)
        #expect(updated.stops.map(\.id) == ids)
        #expect(updated.stops[0].visitSeconds == 3600)
        #expect(updated.scheduleAssessment?.modelCalls == 0)
        #expect(updated.input == model.planning.draftInput)
    }

    @Test func v41DateSourceEditsKeepTheSemanticPreferencePayloadStable() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-30T12:00:00+07:00"))
        let tomorrow = try #require(ISO8601DateFormatter().date(from: "2026-12-01T09:00:00+07:00"))
        let repository = try PocketIntegrationFixture.repository(jobClock: { now })
        let model = try v4DateFlow(repository: repository, now: now, automatic: true, method: .hybridV41)
        model.answers.timing = .tomorrow
        model.answers.dayPart = .evening
        model.finishChoosingPlaces()
        let before = model.preferenceText
        model.prepareScheduleOptions()
        model.changeTripDate(tomorrow)
        #expect(!before.isEmpty)
        #expect(model.preferenceText == before)
        #expect(model.planning.startsAt == tomorrow)
    }

    @Test func futureTripRequiresDateRevisionAndExplicitSameDayStartConfirmation() async throws {
        let input = try savedTripFixture()
        let replacementDeparture = input.startsAt.addingTimeInterval(-86_400)
        let now = replacementDeparture.addingTimeInterval(30 * 60)
        let repository = try PocketIntegrationFixture.repository(jobClock: { now })
        let planning = PlanningPresenter(interactor: .init(repository: repository), initialInput: input)
        let original = try await saveTripFixture(using: planning)

        await #expect(throws: PlanningError.failed("START_DATE_MISMATCH")) {
            try await planning.prepareStart(original)
        }
        #expect(planning.issues[.activity(original.id)]?.cause == .planning(.failed("START_DATE_MISMATCH")))
        #expect(planning.trips.first == original)

        await planning.request(.replan, trip: original, replacementDeparture: replacementDeparture)
        let preview = try #require(planning.job?.result?.proposal)
        #expect(preview.departureAt == replacementDeparture)
        #expect(preview.stops.map(\.id) == original.plan.stops.map(\.id))
        #expect(planning.trips.first == original)
        await planning.apply(scope: .savedTrip(original.id))
        let revised = try #require(planning.trips.first)
        #expect(revised.id == original.id)
        #expect(revised.status == .planned)
        #expect(revised.revision == original.revision + 1)
        #expect(revised.plan.departureAt == replacementDeparture)

        let confirmation = try #require(await planning.prepareStart(revised))
        #expect(confirmation.scheduleChanged)
        #expect(confirmation.proposal.departureAt == now)
        #expect(planning.trips.first == revised)
        await planning.event(.start, trip: revised)
        #expect(planning.issues[.activity(revised.id)]?.cause == .planning(.expired))
        #expect(planning.trips.first == revised)

        await planning.event(.start, trip: revised, preparationID: confirmation.id)
        let started = try #require(planning.trips.first)
        #expect(started.status == .active)
        #expect(started.revision == revised.revision + 1)
        #expect(started.plan == confirmation.proposal)
    }

    @Test func replanPreservesProgressAndRestoresPendingEndpointFromDisk() async throws {
        let input = try savedTripFixture()
        let now = input.startsAt
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("trips.json")
        let repository = try PocketIntegrationFixture.repository(storageURL: storage, jobClock: { now })
        let planning = PlanningPresenter(interactor: .init(repository: repository), initialInput: input)
        let saved = try await saveTripFixture(using: planning)
        let confirmation = try #require(await planning.prepareStart(saved))
        await planning.event(.start, trip: saved, preparationID: confirmation.id)
        let started = try #require(planning.trips.first)
        let first = try #require(started.nextStop)

        await planning.event(.arrive, trip: started)
        await planning.event(.completeStop, trip: try #require(planning.trips.first))
        let afterFirst = try #require(planning.trips.first)
        let second = try #require(afterFirst.nextStop)
        await planning.event(.arrive, trip: afterFirst)
        await planning.event(.extendStay, trip: try #require(planning.trips.first), extraSeconds: 1800)
        let extended = try #require(planning.trips.first)
        let extendedDeparture = try #require(extended.nextStop?.departureAt)
        #expect(extendedDeparture == now.addingTimeInterval(Double(second.visitSeconds + 1800)))

        await planning.request(.replan, trip: extended)
        let preview = try #require(planning.job?.result?.proposal)
        #expect(preview.stops.map(\.id) == [second.id])
        #expect(preview.stops.first?.departureAt == extendedDeparture)
        #expect(preview.input.planningEndpoint == input.origin)
        #expect(preview.experiencePlan == nil)
        #expect(planning.trips.first == extended)
        await planning.apply(scope: .planning(extended.id))
        let updated = try #require(planning.trips.first)
        #expect(updated.revision == extended.revision + 1)
        #expect(updated.completedStopIDs == [first.id])
        #expect(updated.currentStopID == second.id)
        #expect(updated.plan.stops.map(\.id) == [first.id, second.id])

        await planning.event(.completeStop, trip: updated)
        let pending = try #require(planning.trips.first)
        #expect(pending.status == .active)
        #expect(pending.pendingEndpoint == input.origin)
        let reopened = try PocketIntegrationFixture.repository(storageURL: storage, jobClock: { now })
        let restoredPlanning = PlanningPresenter(interactor: .init(repository: reopened))
        await restoredPlanning.load(resumesJobs: false)
        let restored = try #require(restoredPlanning.trips.first)
        #expect(restored.id == pending.id)
        #expect(restored.status == .active)
        #expect(restored.completedStopIDs == [first.id, second.id])
        #expect(restored.pendingEndpoint == input.origin)

        await restoredPlanning.event(.arriveAtEndpoint, trip: restored)
        let completed = try #require(restoredPlanning.trips.first)
        #expect(completed.status == .completed)
        #expect(completed.pendingEndpoint == nil)
        #expect(completed.completedStopIDs == restored.completedStopIDs)
    }

    private func savedTripFixture() throws -> PlanningInput {
        var input = PocketIntegrationFixture.input()
        input.places = Array(try PocketIntegrationFixture.searchablePlaces().prefix(2))
        for index in input.places.indices { input.places[index].durationOverridden = true }
        input.enginePreferences?.orderingMethod = .hybridV42
        input.enginePreferences?.scheduleSource = .manual
        input.enginePreferences?.returnToOrigin = true
        input.preservesPlaceOrder = true
        return input
    }

    private func saveTripFixture(using planning: PlanningPresenter) async throws -> PersonalPlanningTrip {
        await planning.request(.firstItinerary)
        _ = try #require(planning.job?.result?.proposal)
        await planning.apply()
        return try #require(planning.trips.first)
    }

    private func v4DateFlow(repository: PocketPlanningRepository, now: Date, automatic: Bool, method: PlanningOrderingMethod = .hybridV4) throws -> TripCreationPresenter {
        var input = PocketIntegrationFixture.input()
        input.startsAt = now
        input.finishBy = now.addingTimeInterval(25 * 60)
        input.enginePreferences?.usesAutomaticTripDate = automatic
        input.places = Array(try PocketIntegrationFixture.searchablePlaces().prefix(2))
        for index in input.places.indices {
            input.places[index].visitSeconds = 45 * 60
            input.places[index].durationOverridden = true
        }
        let planning = PlanningPresenter(interactor: .init(repository: repository), initialInput: input)
        return TripCreationPresenter(planning: planning, mode: "Pocket • synthetic integration fixture", specificPlace: true,
                                     interactor: .init(searcher: SyntheticTripPlaceSearch()),
                                     orderingMethod: { method }, clock: { now })
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
    @Test func recommendationShortAddressUsesAvailableLocationWithoutRepeatingName() {
        var item = RecommendedPlace(place: .init(id: UUID(), name: "Kopi Kenangan", location: TripDiscoveryArea.center, visitSeconds: 1800),
                                    address: "Kopi Kenangan, Jalan Thamrin, Central Jakarta")
        #expect(item.shortAddress == "Jalan Thamrin")
        item.branchAddress = "Jalan Cikini 10"
        #expect(item.shortAddress == "Jalan Cikini 10")
        item.branchAddress = nil
        item.address = "Kopi Kenangan"
        #expect(item.shortAddress == nil)
        item.address = nil
        #expect(item.shortAddress == nil)
    }
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
        #expect(model.batch.places.isEmpty)
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
        let refreshedQueries = search.queries.dropFirst(firstQueries.count)
        #expect(Set(firstQueries).count == 4)
        #expect(Set(refreshedQueries).count == 4)
        #expect(Set(firstQueries).isDisjoint(with: refreshedQueries))
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
        let batch = try await TripCreationInteractor(searcher: search).recommend(queries: ["first", "second"], near: TripDiscoveryArea.center, synthetic: true)
        #expect(batch.places.map(\.id) == [shared.id, second.id, third.id])
        #expect(batch.warnings.isEmpty)
        #expect(batch.synthetic)
    }

    @Test func recommendationsExpandAndExcludePlacesOutsideMaximumRadius() async throws {
        let search = TripSearchStub()
        let origin = TripDiscoveryArea.center
        func place(_ name: String, latitudeOffset: Double) -> RecommendedPlace {
            .init(place: .init(id: UUID(), name: name,
                               location: .init(latitude: origin.latitude + latitudeOffset, longitude: origin.longitude), visitSeconds: 1800))
        }
        let nearby = place("Nearby", latitudeOffset: 0.01)
        let expanded = place("Expanded", latitudeOffset: 0.15)
        let tooFar = place("Too far", latitudeOffset: 0.5)
        search.placesByQuery = ["park": [tooFar, expanded, nearby]]
        let batch = try await TripCreationInteractor(searcher: search).recommend(queries: ["park"], near: origin, synthetic: true)
        #expect(batch.radiusKilometers == 30)
        #expect(batch.places.map(\.id) == [nearby.id, expanded.id])
        #expect(search.queries.count == 3)

        search.placesByQuery = ["park": (0 ..< 10).map { place("Nearby \($0)", latitudeOffset: Double($0) * 0.001) }]
        let initial = try await TripCreationInteractor(searcher: search).recommend(queries: ["park"], near: origin, synthetic: true)
        #expect(initial.radiusKilometers == 10)
        #expect(initial.places.count == 10)
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
        #expect(batch.places.map(\.id) == [foreign.id])
        search.placesByQuery = ["bookstore": [foreign]]
        let empty = try await interactor.recommend(queries: ["bookstore"], near: nil, synthetic: true)
        #expect(empty.places.isEmpty)
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

    @Test func directProcessingBuildsV42ScheduleWithoutAvailabilityForm() async throws {
        let repository = try PocketIntegrationFixture.repository()
        let model = try make(repository: repository)
        let fixtureInput = PocketIntegrationFixture.input()
        model.planning.startsAt = fixtureInput.startsAt
        model.planning.finishBy = fixtureInput.finishBy
        model.selected = [.init(place: .init(id: UUID(), name: "Unverified trip selection",
                                             location: .init(latitude: -6.2515, longitude: 106.8), visitSeconds: 2700))]
        model.finishChoosingPlaces()
        await model.finishMainSpot()
        #expect(model.error == nil)
        #expect(model.route == .review)
        #expect(model.planning.job?.purpose == .firstItinerary)
        let proposal = try #require(model.planning.job?.result?.proposal)
        #expect(proposal.experiencePlan != nil)
        #expect(proposal.stops.map(\.id) == model.selected.map { $0.place.id })
        #expect(proposal.input.enginePreferences?.orderingMethod == .hybridV42)
        #expect(proposal.stops.allSatisfy { $0.arrivalAt != nil && $0.departureAt != nil })
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

@Suite("Recent places in the place picker")
@MainActor struct PlanningRecentPlacesTests {
    private func defaults() -> UserDefaults {
        let name = "PlanningRecentPlacesTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    private func place(_ name: String, latitude: Double) -> PlanningPlace {
        PlanningPlace(id: UUID(), name: name, location: .init(latitude: latitude, longitude: 106.8), visitSeconds: 2700)
    }

    @Test func newestChoiceComesFirstAndReplacesTheSameSpot() {
        let store = defaults()
        PlanningRecentPlaces.owner = nil
        PlanningRecentPlaces.record(place("Blok M", latitude: -6.244), in: store)
        PlanningRecentPlaces.record(place("Senayan", latitude: -6.227), in: store)
        PlanningRecentPlaces.record(place("Blok M station", latitude: -6.24401), in: store)
        #expect(PlanningRecentPlaces.load(from: store).map(\.name) == ["Blok M station", "Senayan"])
    }

    @Test func keepsOnlyTheMostRecentFive() {
        let store = defaults()
        PlanningRecentPlaces.owner = nil
        for index in 0 ..< 7 {
            PlanningRecentPlaces.record(place("Place \(index)", latitude: -6.2 - Double(index) * 0.01), in: store)
        }
        let names = PlanningRecentPlaces.load(from: store).map(\.name)
        #expect(names.count == PlanningRecentPlaces.limit)
        #expect(names.first == "Place 6")
    }

    @Test func anotherAccountNeverSeesTheList() {
        let store = defaults()
        PlanningRecentPlaces.owner = UUID()
        PlanningRecentPlaces.record(place("Home", latitude: -6.2), in: store)
        PlanningRecentPlaces.owner = UUID()
        #expect(PlanningRecentPlaces.load(from: store).isEmpty)
        PlanningRecentPlaces.owner = nil
        #expect(PlanningRecentPlaces.load(from: store).isEmpty)
    }
}
