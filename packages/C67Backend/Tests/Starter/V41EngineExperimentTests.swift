import Foundation
import Testing
import C67Domain
import PocketEngine
@testable import C67Data

/// Prepared engine experiments. Every provider is synthetic; no UI or network is involved.
@Suite("Hybrid v4.1 engine experiments")
struct V41EngineExperimentTests {
    @Test(arguments: PlanningTripTiming.allCases)
    func calendarChoicesCrossTheYearInTheTripTimeZone(_ timing: PlanningTripTiming) throws {
        let anchor = date("2026-12-31T23:55:00+09:00")
        var input = try v41Input(count: 1)
        input.timeZone = "Asia/Tokyo"
        input.enginePreferences?.scheduleSource = .timingAnswer
        input.enginePreferences?.tripTiming = timing
        input.enginePreferences?.timingAnchor = anchor
        let expected: [String]
        switch timing {
        case .now: expected = ["2026-12-31T23:59:58+09:00"]
        case .tomorrow: expected = ["2027-01-01T09:00:00+09:00"]
        case .inAFewDays: expected = ["2027-01-02T09:00:00+09:00", "2027-01-03T09:00:00+09:00"]
        case .bestDay: expected = ["2026-12-31T23:59:58+09:00", "2027-01-01T09:00:00+09:00", "2027-01-02T09:00:00+09:00"]
        }
        let windows = try PlanningDayWindow.v41Inputs(input, at: anchor)
        #expect(windows.map(\.startsAt) == expected.map(date))
        #expect(try PlanningDayWindow.v41Inputs(input, at: anchor.addingTimeInterval(86400)) == windows)
        #expect(windows.allSatisfy { $0.finishBy > $0.startsAt && $0.timeZone == "Asia/Tokyo" })
    }

    @Test func routeCacheSeparatesDirectionMinuteAndCommandMode() async throws {
        var input = try v41Input(count: 1)
        input.mode = .automobile
        let probe = RouteProbe()
        let routes = V41RouteSession(input: input, services: services(probe))
        let stop = input.places[0].id.uuidString
        let minute = Int(input.startsAt.timeIntervalSince1970 / 60)
        let first = try await routes.quote("origin", stop, minute)
        let cached = try await routes.quote("origin", stop, minute)
        #expect(first.minutes == cached.minutes)
        #expect(first.meters == cached.meters)
        #expect(await probe.calls.count == 1)
        _ = try await routes.quote(stop, "origin", minute)
        _ = try await routes.quote("origin", stop, minute + 1)
        input.mode = .walking
        let walking = V41RouteSession(input: input, services: services(probe))
        _ = try await walking.quote("origin", stop, minute)
        let calls = await probe.calls
        try #require(calls.count == 4)
        #expect(calls[1].from == calls[0].to && calls[1].to == calls[0].from)
        #expect(calls[2].at.timeIntervalSince(calls[0].at) == 60)
        #expect(calls.map(\.mode) == [.automobile, .automobile, .automobile, .walking])
        #expect(await routes.calls == 3)
        #expect(await walking.calls == 1)
    }

    @Test func anUnavailableQuoteIsCachedOnlyWithinItsAttempt() async throws {
        let input = try v41Input(count: 1)
        let probe = RouteProbe(failsFirst: true)
        let routes = V41RouteSession(input: input, services: services(probe))
        let stop = input.places[0].id.uuidString
        let minute = Int(input.startsAt.timeIntervalSince1970 / 60)
        #expect(try await routes.quote("origin", stop, minute).status == "route_unavailable")
        #expect(try await routes.quote("origin", stop, minute).minutes == nil)
        #expect(await probe.calls.count == 1)
        let retry = V41RouteSession(input: input, services: services(probe))
        #expect(try await retry.quote("origin", stop, minute).minutes == 10)
        #expect(await probe.calls.count == 2)
    }

    @Test func bestDaySharesItsQuoteLimitAndRetainsAnEarlierCompleteSchedule() async throws {
        let calls = V41Calls()
        var input = try v41Input(count: 1)
        let anchor = date("2026-11-30T12:00:00+07:00")
        input.enginePreferences?.scheduleSource = .timingAnswer
        input.enginePreferences?.tripTiming = .bestDay
        input.enginePreferences?.timingAnchor = anchor
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: unknownHours, quoteLimit: 2, synthetic: true)
        let result = try await planner.plan(job(input, at: anchor))
        let proposal = try #require(result.proposal)
        let assessment = try #require(proposal.scheduleAssessment)
        #expect(proposal.feasible && proposal.stops.count == 1)
        #expect(assessment.routeCalls == 2 && assessment.modelCalls == 0)
        try #require(assessment.dates.count == 3)
        #expect(assessment.dates[0].completeCandidates > 0 && assessment.dates[1].completeCandidates > 0)
        #expect(assessment.dates[2].completeCandidates == 0)
        #expect(assessment.stopReason == "quote_budget_exhausted")
        #expect(!proposal.warnings.isEmpty)
        #expect(await calls.routeDates.count == 2)
    }

    @Test func repeatingACommandOrReadingItsStatusDoesNotSpendMoreBudget() async throws {
        let calls = V41Calls()
        let repository = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: nil, synthetic: true)
        let input = try v41Input(count: 1)
        let request = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
        let receipt = try await repository.requestPlan(request)
        let done = try await finished(repository, id: receipt.id)
        #expect(done.status == .succeeded)
        let originalDates = await calls.routeDates
        for _ in 0 ..< 3 {
            #expect(try await repository.requestPlan(request).id == receipt.id)
            #expect(try await repository.planningJob(id: receipt.id) == done)
        }
        var changed = request
        changed.input.title = "Another synthetic trip"
        await #expect(throws: PlanningError.requestConflict) { try await repository.requestPlan(changed) }
        #expect(await calls.routeDates == originalDates)
        #expect(await calls.modelIDs.isEmpty)
    }

    @Test func failedAccessDiagnosticsSurvivePersistenceWithoutAnotherSearch() async throws {
        let calls = V41Calls()
        var input = try v41Input(count: 1)
        input.places[0].visitConfirmation = .init(opensAt: input.startsAt, closesAt: input.startsAt.addingTimeInterval(300), publicAccessConfirmed: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = folder.appendingPathComponent("synthetic-v41-failure.json")
        let repository = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: storage, synthetic: true)
        let request = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
        let receipt = try await repository.requestPlan(request)
        let done = try await finished(repository, id: receipt.id)
        var expectedInput = input
        expectedInput.enginePreferences?.reasonableOrdering = true
        expectedInput.enginePreferences?.automaticFirstPlan = true
        #expect(done.status == .failed)
        #expect(done.errorCode == "V41_ACCESS_CONFLICT")
        #expect(done.input == expectedInput)
        #expect(done.command == request)
        let assessment = try #require(done.scheduleAssessment)
        #expect(assessment.conflicts.contains { $0.placeID == input.places[0].id && $0.source == "traveller_confirmation" })
        let reopened = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: storage, synthetic: true)
        let restored = try await reopened.planningJob(id: receipt.id)
        #expect(restored.scheduleAssessment == assessment)
        #expect(restored.status == done.status)
        #expect(restored.errorCode == done.errorCode)
        #expect(restored.input == done.input)
        #expect(restored.command == request)
        #expect(await calls.routeDates.isEmpty)
        #expect(await calls.modelIDs.isEmpty)
    }

    enum SemanticGate: CaseIterable, Sendable { case assistanceDisabled, lunaDisabled, consentDenied }

    @Test(arguments: SemanticGate.allCases)
    func missingDurationNeverBypassesSemanticPermission(_ gate: SemanticGate) async throws {
        let calls = V41Calls()
        var input = try v41Input(count: 1)
        input.places[0].visitSeconds = 0
        input.places[0].durationOverridden = false
        input.enginePreferences?.semanticAssistance = gate == .assistanceDisabled ? .disabled : .whenNeeded
        input.enginePreferences?.usesLuna = gate != .lunaDisabled
        input.enginePreferences?.allowsAIProcessing = gate != .consentDenied
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: unknownHours)
        do {
            _ = try await planner.plan(job(input))
            Issue.record("A duration must be supplied when semantic assistance is unavailable.")
        } catch let failure as PlanningScheduleFailure {
            #expect(failure.code == "V4_DURATION_UNKNOWN")
            #expect(failure.assessment.unresolved.contains { $0.code == "duration_unknown" && $0.placeID == input.places[0].id })
        }
        #expect(await calls.modelIDs.isEmpty)
        #expect(await calls.routeDates.isEmpty)
    }

    enum ContextChange: CaseIterable, Sendable { case preferences, coordinates, mainSpot, selection }

    @Test func automaticFirstItineraryEstimatesDurationsAndRollsOverWithoutAI() async throws {
        let calls = V41Calls()
        let anchor = date("2026-11-30T23:45:00+07:00")
        var input = try v41Input(count: 3)
        input.enginePreferences?.orderingMethod = .hybridV42
        input.enginePreferences?.automaticFirstPlan = true
        input.enginePreferences?.scheduleSource = .automatic
        input.enginePreferences?.usesAutomaticTripDate = true
        input.enginePreferences?.mainSpotID = input.places[0].id
        input.places[0].durationOverridden = false
        input.places[0].visitSeconds = 0
        input.places[1].durationOverridden = false
        input.places[1].visitSeconds = 1_800
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: unknownHours)

        let proposal = try #require(try await planner.plan(job(input, at: anchor)).proposal)
        let durations = Dictionary(uniqueKeysWithValues: proposal.stops.map { ($0.id, $0.visitSeconds) })
        #expect(proposal.feasible && proposal.rescheduledFromDate != nil)
        #expect(proposal.scheduleAssessment?.dates.count == 2)
        #expect(proposal.scheduleAssessment?.modelCalls == 0)
        #expect(durations[input.places[0].id] == 2_700 && durations[input.places[1].id] == 1_800)
        #expect(durations[input.places[2].id] == input.places[2].visitSeconds)
        #expect(proposal.stops.filter { $0.warnings.contains("Visit duration is estimated by Travelants.") }.count == 2)
        #expect(await calls.modelIDs.isEmpty)
    }

    @Test func failedModelDoesNotPreventAnAutomaticFirstItinerary() async throws {
        let calls = V41Calls()
        let anchor = date("2026-11-30T23:45:00+07:00")
        var input = try v41Input(count: 1)
        input.enginePreferences?.orderingMethod = .hybridV42
        input.enginePreferences?.automaticFirstPlan = true
        input.enginePreferences?.scheduleSource = .automatic
        input.enginePreferences?.usesAutomaticTripDate = true
        input.enginePreferences?.semanticAssistance = .whenNeeded
        input.enginePreferences?.usesLuna = true
        input.enginePreferences?.allowsAIProcessing = true
        input.places[0].durationOverridden = false
        var services = v41Services(calls)
        services.experience = { _, _ in throw PlanningError.timedOut }
        let planner = V41ItineraryPlanner(services: services, hours: unknownHours)

        let proposal = try #require(try await planner.plan(job(input, at: anchor)).proposal)
        #expect(proposal.feasible && proposal.rescheduledFromDate != nil)
        #expect(proposal.scheduleAssessment?.modelCalls == 1)
        #expect(proposal.stops.first?.warnings.contains("Visit duration is estimated by Travelants.") == true)
    }

    @Test(arguments: ContextChange.allCases)
    func changedSemanticContextInvalidatesTheSavedResponse(_ change: ContextChange) async throws {
        let calls = V41Calls()
        let snapshots = SemanticStore()
        var input = try v41Input(count: 2)
        input.enginePreferences?.semanticAssistance = .whenNeeded
        input.enginePreferences?.usesLuna = true
        input.enginePreferences?.allowsAIProcessing = true
        for index in input.places.indices { input.places[index].durationOverridden = false }
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: unknownHours)
        let firstJob = job(input)
        _ = try await planner.plan(firstJob, retain: { await snapshots.append($0) })
        switch change {
        case .preferences: input.preferences += "\nPreferred time of day: afternoon."
        case .coordinates: input.places[0].location.latitude += 0.001
        case .mainSpot: input.enginePreferences?.mainSpotID = input.places[1].id
        case .selection: input.places.removeLast()
        }
        var next = firstJob
        next.input = input
        let result = try await planner.plan(next, snapshots: await snapshots.values, retain: { await snapshots.append($0) })
        #expect(result.proposal?.scheduleAssessment?.modelCalls == 1)
        let ids = await calls.modelIDs
        #expect(ids.count == 2 && Set(ids).count == 2)
        #expect(await snapshots.values.count == 2)
    }

    @Test func splitRegularHoursRequireOneContinuousVisitWindow() async throws {
        let calls = V41Calls()
        var input = try v41Input(count: 1)
        input.places[0].sourceID = "apple:synthetic-split"
        input.places[0].visitSeconds = 3 * 3600
        input.enginePreferences?.flexibleDeparture = true
        let lookup = try weeklyHours(id: "synthetic-split", intervals: [(9 * 3600, 11 * 3600), (13 * 3600, 17 * 3600)])
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: { _ in lookup })
        let result = try await planner.plan(job(input))
        let proposal = try #require(result.proposal)
        let stop = try #require(proposal.stops.first)
        #expect(try #require(stop.visitStartsAt) >= date("2026-11-30T13:00:00+07:00"))
        #expect(try #require(stop.departureAt) <= date("2026-11-30T17:00:00+07:00"))
        #expect(stop.visitSeconds == 3 * 3600)
        #expect(proposal.scheduleAssessment?.unresolved.contains { $0.code == "date_access_unverified" && $0.source == "apple_regular_hours" } == true)
    }

    @Test func regularOvernightHoursIncludeThePreviousDaysOpening() async throws {
        let calls = V41Calls()
        var input = try v41Input(count: 1)
        input.startsAt = date("2026-11-30T00:30:00+07:00")
        input.finishBy = date("2026-11-30T02:00:00+07:00")
        input.places[0].sourceID = "apple:synthetic-overnight"
        input.places[0].visitSeconds = 1800
        let lookup = try weeklyHours(id: "synthetic-overnight", intervals: [(23 * 3600, 2 * 3600)])
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: { _ in lookup })
        let result = try await planner.plan(job(input))
        let stop = try #require(result.proposal?.stops.first)
        #expect(stop.visitStartsAt == date("2026-11-30T00:40:00+07:00"))
        #expect(stop.departureAt == date("2026-11-30T01:10:00+07:00"))
        #expect(result.proposal?.scheduleAssessment?.needsAccessConfirmation == true)
    }

    @Test func anOpenVenueDoesNotOverrideItsLastEntryCutoff() async throws {
        let calls = V41Calls()
        var input = try v41Input(count: 1)
        var access = PlanningVisitConfirmation(opensAt: input.startsAt, closesAt: input.finishBy, publicAccessConfirmed: true)
        access.lastEntryAt = input.startsAt.addingTimeInterval(5 * 60)
        input.places[0].visitConfirmation = access
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: unknownHours)
        do {
            _ = try await planner.plan(job(input))
            Issue.record("Arrival after last entry must reject the schedule even while the venue is open.")
        } catch let failure as PlanningScheduleFailure {
            #expect(failure.assessment.conflicts.contains { $0.code == "visit_outside_hours_or_entry" && $0.placeID == input.places[0].id })
            #expect(failure.assessment.dates.count == 1)
        }
        #expect(await calls.routeDates.count == 1)
    }

    @Test func adaptiveSearchRespectsBothLocksWhenTheMainSpotIsLast() async throws {
        let calls = V41Calls()
        var input = try v41Input(count: 4)
        input.firstPlaceID = input.places[1].id
        input.enginePreferences?.lastPlaceID = input.places[0].id
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: unknownHours)
        let result = try await planner.plan(job(input))
        let stops = try #require(result.proposal?.stops)
        #expect(stops.first?.id == input.firstPlaceID)
        #expect(stops.last?.id == input.enginePreferences?.mainSpotID)
        #expect(Set(stops.map(\.id)) == Set(input.places.map(\.id)))
        #expect(stops.allSatisfy { $0.visitSeconds == 3600 })
    }

    @Test func anUnavailableLockedFirstLegDoesNotPermitReordering() async throws {
        var input = try v41Input(count: 2)
        input.preservesPlaceOrder = true
        let first = input.places[0].location
        var synthetic = v41Services(V41Calls())
        synthetic.travel = { _, destination, _, _ in
            if destination.latitude == first.latitude, destination.longitude == first.longitude { throw PlanningError.unavailable }
            return .init(seconds: 600, meters: 1000)
        }
        let planner = V41ItineraryPlanner(services: synthetic, hours: unknownHours)
        do {
            _ = try await planner.plan(job(input))
            Issue.record("A complete schedule cannot skip the mandatory unavailable first leg.")
        } catch let failure as PlanningScheduleFailure {
            #expect(failure.code == "V41_NO_SCHEDULE")
            #expect(failure.assessment.completeCandidates == 0)
        }
    }

    @Test func missingETAIsNotEvidenceThatTodayIsTooShort() async throws {
        let probe = RouteProbe(failsAlways: true)
        let anchor = date("2026-11-30T12:00:00+07:00")
        var input = try v41Input(count: 1)
        input.enginePreferences?.scheduleSource = .automatic
        input.enginePreferences?.usesAutomaticTripDate = true
        let planner = V41ItineraryPlanner(services: services(probe), hours: unknownHours)
        do {
            _ = try await planner.plan(job(input, at: anchor))
            Issue.record("An unavailable route cannot produce a complete schedule.")
        } catch let failure as PlanningScheduleFailure {
            #expect(failure.code == "V41_NO_SCHEDULE")
            #expect(failure.assessment.dates.count == 1)
            #expect(!failure.assessment.allCandidatesMissedDeadline)
        }
        let calls = await probe.calls
        #expect(!calls.isEmpty)
        #expect(calls.allSatisfy { PlanningDayWindow.isSameDay($0.at, anchor, timeZone: input.timeZone) })
    }

    @Test func anAlreadyExhaustedPersistedBudgetCannotDispatchAnotherQuote() async throws {
        let calls = V41Calls()
        let input = try v41Input(count: 1)
        var resumed = job(input)
        var previous = PlanningScheduleAssessment()
        previous.routeCalls = 72
        resumed.scheduleAssessment = previous
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: unknownHours)
        do {
            _ = try await planner.plan(resumed)
            Issue.record("A resumed command must retain the already spent route budget.")
        } catch let failure as PlanningScheduleFailure {
            #expect(failure.code == "V41_BUDGET_REACHED")
            #expect(failure.assessment.routeCalls == 72)
            #expect(failure.assessment.stopReason == "quote_budget_exhausted")
        }
        #expect(await calls.routeDates.isEmpty)
    }

    @Test(arguments: [false, true])
    func aShorterUserVisitRequiresAnAcceptedMinimumAndStillNeedsReview(_ acceptsMinimum: Bool) async throws {
        let calls = V41Calls()
        var input = try v41Input(count: 1)
        input.finishBy = input.startsAt.addingTimeInterval(55 * 60)
        input.places[0].minimumAcceptedVisitSeconds = acceptsMinimum ? 1800 : nil
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: unknownHours)
        do {
            _ = try await planner.plan(job(input))
            Issue.record("A shorter alternative must be offered for review instead of replacing the requested hour.")
        } catch let failure as PlanningScheduleFailure {
            let offers = failure.assessment.durationAlternatives
            if acceptsMinimum {
                let offer = try #require(offers.first)
                #expect(offers.count == 1)
                #expect(offer.placeID == input.places[0].id)
                #expect(offer.originalSeconds == 3600 && offer.proposedSeconds == 1800)
                #expect(offer.source == "traveller_accepted_minimum")
                #expect(offer.startsAt == input.startsAt && offer.finishBy == input.finishBy)
                #expect(failure.assessment.routeCalls == 1)
            } else {
                #expect(offers.isEmpty)
                #expect(failure.assessment.routeCalls == 0)
            }
        }
        #expect(await calls.modelIDs.isEmpty)
    }

    @Test func aBookedSessionIsNeverOfferedAsAShorterVisit() async throws {
        let calls = V41Calls()
        var input = try v41Input(count: 1)
        input.finishBy = input.startsAt.addingTimeInterval(55 * 60)
        input.places[0].minimumAcceptedVisitSeconds = 1800
        input.places[0].activitySession = .init(startsAt: input.startsAt.addingTimeInterval(600), endsAt: input.startsAt.addingTimeInterval(4200))
        let planner = V41ItineraryPlanner(services: v41Services(calls), hours: unknownHours)
        do {
            _ = try await planner.plan(job(input))
            Issue.record("A booked one-hour session cannot fit into this availability window.")
        } catch let failure as PlanningScheduleFailure {
            #expect(failure.assessment.durationAlternatives.isEmpty)
            #expect(failure.assessment.routeCalls == 0)
        }
        #expect(await calls.routeDates.isEmpty)
        #expect(await calls.modelIDs.isEmpty)
    }

    @Test func legacyPreferencesKeepTheirExplicitDateWhenV41IsSelected() throws {
        let legacy = Data(#"{"themes":[],"labels":[],"conditions":{},"area":"jakarta-selatan","flexibleDeparture":false,"returnToOrigin":false,"maximumWaitMinutes":0,"avoidRain":false,"usesLuna":false,"allowsAIProcessing":false,"orderingMethod":"hybrid_v4"}"#.utf8)
        var options = try JSONDecoder().decode(PlanningPreferences.self, from: legacy)
        #expect(options.tripTiming == nil && options.scheduleSource == nil && options.semanticAssistance == nil)
        options.orderingMethod = .hybridV41
        var input = try v41Input(count: 1)
        input.enginePreferences = options
        let windows = try PlanningDayWindow.v41Inputs(input, at: date("2026-12-31T23:55:00+07:00"))
        #expect(windows == [input])
    }
}

private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

private func job(_ input: PlanningInput, at anchor: Date? = nil) -> PlanningJob {
    .init(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: anchor ?? input.startsAt)
}

private let unknownHours: @Sendable (String) async -> PlanningHoursLookup = { _ in .init(status: "unavailable") }

private func weeklyHours(id: String, intervals: [(Int, Int)]) throws -> PlanningHoursLookup {
    let weekly = (1 ... 7).map { weekday in
        ["weekday": weekday, "intervals": intervals.map { ["startSeconds": $0.0, "endSeconds": $0.1] }] as [String: Any]
    }
    let data = try JSONSerialization.data(withJSONObject: ["placeId": id, "timezone": "Asia/Jakarta", "weekly": weekly])
    return try .init(status: "available", hours: JSONDecoder().decode(PlanningRegularHours.self, from: data))
}

private actor SemanticStore {
    var values: [PlanningSemanticSnapshot] = []
    func append(_ value: PlanningSemanticSnapshot) { values.append(value) }
}

private actor RouteProbe {
    struct Call: Sendable {
        let from: Coordinate
        let to: Coordinate
        let at: Date
        let mode: PlanningMode
    }

    var calls: [Call] = []
    let failsFirst: Bool
    let failsAlways: Bool

    init(failsFirst: Bool = false, failsAlways: Bool = false) {
        self.failsFirst = failsFirst
        self.failsAlways = failsAlways
    }

    func quote(_ from: Coordinate, _ to: Coordinate, _ at: Date, _ mode: PlanningMode) throws -> LegQuote {
        calls.append(.init(from: from, to: to, at: at, mode: mode))
        if failsAlways || (failsFirst && calls.count == 1) { throw PlanningError.unavailable }
        return .init(seconds: 600, meters: 1000)
    }
}

private func services(_ probe: RouteProbe) -> PocketPlanningServices {
    .init(travel: { from, to, at, mode in try await probe.quote(from, to, at, mode) },
          weather: { _, _, _ in throw PlanningError.invalidResponse }, advise: { _ in throw PlanningError.invalidResponse })
}
