import Foundation
import Testing
import C67Domain
import PocketEngine
@testable import C67Data

@Test func pocketReportsRouteWorkDuringFormulaPlanningAndClearsItOnCompletion() async throws {
    let calls = V41Calls()
    let gate = RouteActivityGate()
    var services = v41Services(calls, model: false)
    services.travel = { _, _, at, _ in
        await gate.wait()
        return try await calls.travel(at)
    }
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: nil)
    let input = try v41Input()
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    var observed = job
    do {
        for _ in 0 ..< 100 {
            observed = try await repository.planningJob(id: job.id)
            if observed.activity == .travelTimes || observed.status != .running { break }
            try await Task.sleep(for: .milliseconds(5))
        }
    } catch {
        await gate.release()
        throw error
    }
    await gate.release()
    #expect(observed.status == .running)
    #expect(observed.activity == .travelTimes)
    let result = try await finished(repository, id: job.id)
    #expect(result.status == .succeeded)
    #expect(result.activity == nil)
    #expect(await calls.modelIDs.isEmpty)
}

private actor RouteActivityGate {
    private var released = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        released = true
        for waiter in waiting { waiter.resume() }
        waiting.removeAll()
    }
}

@Test func pocketRejectsAnotherRequestWhilePlanningAndKeepsRetryIdentity() async throws {
    let calls = V41Calls()
    var services = v41Services(calls, model: false)
    services.travel = { _, _, at, _ in
        try await Task.sleep(for: .milliseconds(20))
        return try await calls.travel(at)
    }
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: nil)
    let input = try v41Input()
    let request = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
    let job = try await repository.requestPlan(request)
    #expect(try await repository.requestPlan(request).id == job.id)
    let other = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
    await #expect(throws: PlanningError.failed("PLANNING_ALREADY_RUNNING")) {
        try await repository.requestPlan(other)
    }
    _ = try await finished(repository, id: job.id)
    let next = try await repository.requestPlan(other)
    #expect(next.id != job.id)
}

@Test func v41ResolvesTomorrowInTheTripCalendarAndPreservesManualEdits() throws {
    let anchor = ISO8601DateFormatter().date(from: "2026-11-30T23:30:00+07:00")!
    let tomorrow = ISO8601DateFormatter().date(from: "2026-12-01T09:00:00+07:00")!
    var input = try v41Input()
    input.enginePreferences?.scheduleSource = .timingAnswer
    input.enginePreferences?.tripTiming = .tomorrow
    input.enginePreferences?.timingAnchor = anchor
    #expect(try PlanningDayWindow.v41Inputs(input, at: anchor)[0].startsAt == tomorrow)
    #expect(try PlanningDayWindow.v41Inputs(input, at: anchor.addingTimeInterval(86400))[0].startsAt == tomorrow)
    input.enginePreferences?.scheduleSource = .manual
    #expect(try PlanningDayWindow.v41Inputs(input, at: anchor)[0].startsAt == input.startsAt)
    input.enginePreferences?.scheduleSource = .timingAnswer
    input.enginePreferences?.tripTiming = .bestDay
    #expect(try PlanningDayWindow.v41Inputs(input, at: anchor).count == 3)
}

@Test func v41WithoutAnOrderingServiceSavesReopensRenamesAndReorders() async throws {
    let calls = V41Calls()
    let services = v41Services(calls, model: false)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = folder.appendingPathComponent("trips.json")
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: storage, synthetic: true)
    let input = try v41Input()
    let request = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
    let job = try await repository.requestPlan(request)
    let done = try await finished(repository, id: job.id)
    let proposal = try #require(done.result?.proposal)
    #expect(done.status == .succeeded)
    #expect(proposal.experiencePlan == nil)
    #expect(proposal.usesExperienceFlow)
    #expect(proposal.synthetic)
    #expect(proposal.scheduleAssessment?.modelCalls == 0)
    #expect(proposal.scheduleAssessment?.needsAccessConfirmation == true)
    #expect(try await repository.requestPlan(request).id == job.id)
    let renamed = try await repository.renameProposal(jobID: job.id, title: "My v4.1 trip")
    let reversed = Array(proposal.stops.map(\.id).reversed())
    let edited = try await repository.updateExperienceRoute(jobID: renamed.id, orderedIDs: reversed, departure: input.startsAt)
    #expect(edited.result?.proposal?.stops.map(\.id) == reversed)
    let saved = try await repository.applyProposal(jobID: edited.id, expectedRevision: nil, requestID: UUID())
    let reopened = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: storage)
    let trips = await reopened.personalTrips()
    #expect(trips.first?.id == saved.id)
    #expect(trips.first?.title == "My v4.1 trip")
    #expect(trips.first?.plan.scheduleAssessment != nil)
    #expect(await calls.modelIDs.isEmpty)
}

@Test func v41ReusesOneValidatedSemanticResponseAcrossScheduleEditsAndRestart() async throws {
    let calls = V41Calls()
    let services = v41Services(calls)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = folder.appendingPathComponent("trips.json")
    var input = try v41Input()
    input.enginePreferences?.usesLuna = true
    input.enginePreferences?.allowsAIProcessing = true
    input.enginePreferences?.semanticAssistance = .whenNeeded
    for index in input.places.indices { input.places[index].durationOverridden = false }
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: storage)
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let done = try await finished(repository, id: first.id)
    #expect(done.status == .succeeded)
    #expect(done.semanticSnapshot != nil)
    #expect(await calls.modelIDs.count == 1)
    input = try #require(done.result?.proposal?.input)
    input.startsAt = input.startsAt.addingTimeInterval(1800)
    input.enginePreferences?.scheduleSource = .manual
    let reopened = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: storage)
    let second = try await reopened.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let updated = try await finished(reopened, id: second.id)
    #expect(updated.status == .succeeded)
    #expect(updated.result?.proposal?.scheduleAssessment?.modelCalls == 0)
    #expect(await calls.modelIDs.count == 1)
    input.startsAt = input.startsAt.addingTimeInterval(86400)
    input.finishBy = input.finishBy.addingTimeInterval(86400)
    let third = try await reopened.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(try await finished(reopened, id: third.id).status == .succeeded)
    #expect(await calls.modelIDs.count == 2)
}

@Test func v41KeepsSessionCheckInAndEntryCutoffSeparateFromActivityStart() async throws {
    let calls = V41Calls()
    var input = try v41Input(count: 1)
    let sessionStart = input.startsAt.addingTimeInterval(3600)
    input.places[0].activitySession = .init(startsAt: sessionStart, endsAt: sessionStart.addingTimeInterval(3600),
                                            arriveBy: input.startsAt.addingTimeInterval(15 * 60))
    var access = PlanningVisitConfirmation(opensAt: input.startsAt, closesAt: input.finishBy, publicAccessConfirmed: true)
    access.lastEntryAt = input.startsAt.addingTimeInterval(20 * 60)
    input.places[0].visitConfirmation = access
    input.enginePreferences?.maximumWaitMinutes = 60
    let repository = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: nil)
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let done = try await finished(repository, id: first.id)
    #expect(done.status == .succeeded)
    #expect(done.result?.proposal?.stops.first?.visitStartsAt == sessionStart)
    #expect(done.result?.proposal?.stops.first?.visitSeconds == 3600)
    input.places[0].activitySession?.arriveBy = input.startsAt.addingTimeInterval(5 * 60)
    let late = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let rejected = try await finished(repository, id: late.id)
    #expect(rejected.status == .failed)
    #expect(rejected.scheduleAssessment?.conflicts.contains { $0.code == "session_arrival_missed" } == true)
}

@Test func v41ReschedulesAutomaticTodayAndNowButProtectsPinnedVisits() async throws {
    let now = ISO8601DateFormatter().date(from: "2026-11-30T23:30:00+07:00")!
    let calls = V41Calls()
    let repository = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: nil,
                                                  synthetic: true, jobClock: { now })
    var input = try v41Input()
    input.enginePreferences?.scheduleSource = .automatic
    input.enginePreferences?.usesAutomaticTripDate = true
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let scheduled = try await finished(repository, id: first.id)
    #expect(scheduled.status == .succeeded)
    #expect(scheduled.result?.proposal?.rescheduledFromDate != nil)
    #expect(scheduled.scheduleAssessment?.dates.count == 2)
    let effectiveDate = try #require(scheduled.result?.proposal?.input.startsAt)
    #expect(await calls.routeDates.allSatisfy { PlanningDayWindow.isSameDay($0, effectiveDate, timeZone: input.timeZone) })
    #expect(await calls.modelIDs.isEmpty)
    input.enginePreferences?.tripTiming = .now
    input.enginePreferences?.scheduleSource = .timingAnswer
    let today = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let rescheduled = try await finished(repository, id: today.id)
    #expect(rescheduled.status == .succeeded)
    #expect(rescheduled.result?.proposal?.rescheduledFromDate != nil)
    input.enginePreferences?.tripTiming = .tomorrow
    input.places[0].activitySession = .init(startsAt: now, endsAt: now.addingTimeInterval(600))
    let pinned = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(try await finished(repository, id: pinned.id).errorCode == "V41_DATE_CONFLICT")
}

@Test func v41AccountsForEveryRouteCallAndStopsAfterThrottling() async throws {
    let calls = V41Calls()
    let input = try v41Input(count: 4)
    let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: input.startsAt)
    let planner = V41ItineraryPlanner(services: v41Services(calls), hours: { _ in .init(status: "unavailable") }, quoteLimit: 3)
    do {
        _ = try await planner.plan(job)
        Issue.record("Expected shared route budget to stop the incomplete schedule")
    } catch let failure as PlanningScheduleFailure {
        #expect(failure.code == "V41_BUDGET_REACHED")
        #expect(failure.assessment.routeCalls == 3)
    }
    #expect(await calls.routeDates.count == 3)
    let throttled = V41Calls()
    await throttled.throttle()
    let repository = try PocketPlanningRepository(services: v41Services(throttled), connection: OrderConnection(), storageURL: nil)
    let request = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let done = try await finished(repository, id: request.id)
    #expect(done.errorCode == "V4_ROUTE_THROTTLED")
    #expect(done.scheduleAssessment?.routeCalls == 1)
    #expect(await throttled.routeDates.count == 1)
}

@Test func v41OffersAnEvaluatedShorterVisitWithoutChangingTheFixedInput() async throws {
    let calls = V41Calls()
    var input = try v41Input(count: 1)
    input.finishBy = input.startsAt.addingTimeInterval(55 * 60)
    input.enginePreferences?.semanticAssistance = .whenNeeded
    input.enginePreferences?.usesLuna = true
    input.enginePreferences?.allowsAIProcessing = true
    input.places[0].durationOverridden = false
    let services = PocketPlanningServices(travel: { _, _, at, _ in try await calls.travel(at) },
                                          weather: { _, _, _ in throw PlanningError.invalidResponse }, advise: { _ in throw PlanningError.invalidResponse },
                                          order: { input, id in
                                              var plan = try await calls.order(input, id)
                                              plan.stops[0].duration?.minMinutes = 30
                                              plan.stops[0].duration?.maxMinutes = 90
                                              return plan
                                          })
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: nil)
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let failed = try await finished(repository, id: first.id)
    #expect(failed.status == .failed)
    let offer = try #require(failed.scheduleAssessment?.durationAlternatives.first)
    #expect(offer.proposedSeconds == 1800)
    #expect(failed.input.places[0].durationOverridden == false)
    input.places[0].durationOverridden = true
    input.places[0].visitSeconds = offer.proposedSeconds
    let accepted = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    #expect(try await finished(repository, id: accepted.id).status == .succeeded)
    #expect(await calls.modelIDs.count == 1)
}

@Test func v41AddsABoundaryDepartureForThePreferredExplorationPeriod() async throws {
    let calls = V41Calls()
    var input = try v41Input(count: 1)
    input.enginePreferences?.preferredDayPart = .evening
    input.enginePreferences?.flexibleDeparture = true
    let desired = ISO8601DateFormatter().date(from: "2026-11-30T15:00:00+07:00")!
    input.places[0].visitConfirmation = .init(opensAt: desired, closesAt: desired.addingTimeInterval(3600), publicAccessConfirmed: true)
    let repository = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: nil)
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let done = try await finished(repository, id: first.id)
    let proposal = try #require(done.result?.proposal)
    #expect(proposal.stops.first?.visitStartsAt == desired)
    #expect(proposal.departureAt == desired.addingTimeInterval(-600))
    #expect(proposal.scheduleAssessment?.preferredPeriodOutsideMinutes == 0)
}

@Test func v41ExpandsPastFiveOrdersWithTheSameUnavailableFirstLeg() async throws {
    let input = try v41Input(count: 4)
    let blocked = input.places[0].location
    let origin = input.origin
    let services = PocketPlanningServices(travel: { from, to, _, _ in
        if from.latitude == origin.latitude, to.latitude == blocked.latitude { throw PlanningError.unavailable }
        return .init(seconds: 60, meters: 100)
    }, weather: { _, _, _ in throw PlanningError.invalidResponse }, advise: { _ in throw PlanningError.invalidResponse })
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: nil)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let done = try await finished(repository, id: job.id)
    let assessment = try #require(done.scheduleAssessment)
    #expect(done.status == .succeeded)
    #expect(assessment.evaluatedCandidates > 5)
    #expect(assessment.routeCalls <= 72)
    #expect(done.result?.proposal?.stops.first?.id != input.places[0].id)
    #expect(Set(done.result?.proposal?.stops.map(\.id) ?? []) == Set(input.places.map(\.id)))
    let originalOrder = try #require(done.result?.proposal?.stops.map(\.id))
    let updated = try await repository.updateExperienceRoute(jobID: job.id, orderedIDs: nil, departure: input.startsAt)
    #expect(updated.result?.proposal?.stops.map(\.id) == originalOrder)
    let saved = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
    let refreshed = try await repository.refreshExperienceRoute(tripID: saved.id)
    #expect(refreshed.plan.stops.map(\.id) == originalOrder)
}

@Test func v41PersistsAnAccessConflictBeforeSpendingRouteBudget() async throws {
    let calls = V41Calls()
    var input = try v41Input(count: 2)
    input.places[0].visitConfirmation = .init(opensAt: input.startsAt, closesAt: input.startsAt.addingTimeInterval(300), publicAccessConfirmed: true)
    let repository = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: nil)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let done = try await finished(repository, id: job.id)
    #expect(done.errorCode == "V41_ACCESS_CONFLICT")
    #expect(done.scheduleAssessment?.conflicts.first?.placeID == input.places[0].id)
    #expect(await calls.routeDates.isEmpty)
    #expect(done.input.places == input.places)
}

@Test func v41FailedOptionalSuggestionsKeepTheSuppliedDurationSchedule() async throws {
    let calls = V41Calls()
    var services = v41Services(calls)
    services.order = { _, _ in throw PlanningError.invalidResponse }
    var input = try v41Input()
    input.enginePreferences?.semanticAssistance = .requested
    input.enginePreferences?.usesLuna = true
    input.enginePreferences?.allowsAIProcessing = true
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: nil)
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let done = try await finished(repository, id: first.id)
    #expect(done.status == .succeeded)
    #expect(done.scheduleAssessment?.modelCalls == 1)
    #expect(done.scheduleAssessment?.unresolved.contains { $0.code == "semantic_unavailable" } == true)
    #expect(done.result?.proposal?.stops.allSatisfy { $0.visitSeconds == 3600 } == true)
    #expect(done.result?.proposal?.warnings.contains { $0.contains("Luna suggestions are unavailable") } == true)
}

@Test func v41CancellationDiscardsLateSemanticDataAndResumeKeepsItsIdentity() async throws {
    let calls = V41Calls()
    let gate = SuspendedOrder()
    var services = v41Services(calls)
    services.order = { input, id in
        await gate.wait()
        return try await calls.order(input, id)
    }
    var input = try v41Input()
    input.enginePreferences?.usesLuna = true
    input.enginePreferences?.allowsAIProcessing = true
    input.enginePreferences?.semanticAssistance = .whenNeeded
    for index in input.places.indices { input.places[index].durationOverridden = false }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("trip.json")
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: storage)
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    await gate.waitUntilStarted(1)
    let before = try Data(contentsOf: storage)
    await repository.suspendOrdering()
    await gate.release()
    try await Task.sleep(for: .milliseconds(50))
    #expect(try Data(contentsOf: storage) == before)
    _ = await repository.resumePlanning()
    await gate.waitUntilStarted(2)
    await gate.release()
    #expect(try await finished(repository, id: first.id).status == .succeeded)
    #expect(Set(await calls.modelIDs).count == 1)
}

@Test func v41ResumedRouteSearchRetainsItsPreviouslyReservedBudget() async throws {
    let calls = V41Calls()
    let gate = SuspendedOrder()
    var services = v41Services(calls, model: false)
    services.travel = { _, _, at, _ in
        let quote = try await calls.travel(at)
        if await calls.routeDates.count == 1 { await gate.wait() }
        return quote
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("trip.json")
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: storage)
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: v41Input()))
    await gate.waitUntilStarted(1)
    let before = try Data(contentsOf: storage)
    await repository.suspendOrdering()
    await gate.release()
    try await Task.sleep(for: .milliseconds(50))
    #expect(try Data(contentsOf: storage) == before)
    _ = await repository.resumePlanning()
    let done = try await finished(repository, id: first.id)
    #expect(done.status == .succeeded)
    #expect(done.scheduleAssessment?.routeCalls == (await calls.routeDates.count))
}

@Test func v41CanWaitForASoftTargetWithoutMakingAnImpossibleWaitMandatory() async throws {
    let calls = V41Calls()
    var input = try v41Input(count: 1)
    let target = input.startsAt.addingTimeInterval(3600)
    input.places[0].visitTiming = .preferred
    input.places[0].preferredAfter = target
    input.places[0].preferredBefore = target
    input.enginePreferences?.maximumWaitMinutes = 60
    let repository = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: nil)
    let first = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let waited = try await finished(repository, id: first.id)
    #expect(waited.result?.proposal?.stops.first?.visitStartsAt == target)
    input.finishBy = input.startsAt.addingTimeInterval(80 * 60)
    let shorter = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let fitted = try await finished(repository, id: shorter.id)
    #expect(fitted.status == .succeeded)
    #expect(fitted.result?.proposal?.stops.first?.visitStartsAt == input.startsAt.addingTimeInterval(600))
}

private func referenceOrders(_ ids: [Int]) -> [[Int]] {
    guard ids.count > 1 else { return [ids] }
    return ids.indices.flatMap { index in
        var rest = ids
        let first = rest.remove(at: index)
        return referenceOrders(rest).map { [first] + $0 }
    }
}

private func referenceLeg(_ from: Int, _ to: Int, seed: Int) -> Int {
    (from * 31 + to * 17 + seed * 13) % 19 + 1
}

@Test func v41ScheduleArithmeticMatchesAnIndependentFourStopReference() async throws {
    for seed in 0 ..< 6 {
        var input = try v41Input(count: 4)
        input.enginePreferences?.returnToOrigin = true
        // This reference isolates route arithmetic from estimated access preferences.
        for index in input.places.indices {
            input.places[index].visitConfirmation = .init(opensAt: input.startsAt, closesAt: input.finishBy, publicAccessConfirmed: true)
        }
        let points = [input.origin] + input.places.map(\.location)
        let indices = Dictionary(uniqueKeysWithValues: points.enumerated().map { ($0.element.latitude, $0.offset) })
        let services = PocketPlanningServices(travel: { from, to, _, _ in
            let minutes = referenceLeg(indices[from.latitude]!, indices[to.latitude]!, seed: seed)
            return .init(seconds: Double(minutes * 60), meters: Double(minutes * 100))
        }, weather: { _, _, _ in throw PlanningError.invalidResponse }, advise: { _ in throw PlanningError.invalidResponse })
        let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: nil)
        let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
        let done = try await finished(repository, id: job.id)
        let proposal = try #require(done.result?.proposal)
        func minutes(_ order: [Int]) -> Int {
            let travel = zip([0] + order, order + [0]).reduce(0) { $0 + referenceLeg($1.0, $1.1, seed: seed) }
            return 4 * 60 + travel
        }
        let optimal = referenceOrders([1, 2, 3, 4]).map(minutes).min()!
        let selected = proposal.stops.map { stop in input.places.firstIndex(where: { $0.id == stop.id })! + 1 }
        let actual = Int(try #require(proposal.finishesAt).timeIntervalSince(try #require(proposal.departureAt)) / 60)
        #expect(actual == minutes(selected))
        #expect(actual == optimal)
        #expect(proposal.scheduleAssessment!.routeCalls <= 72)
        #expect(Set(proposal.stops.map(\.id)) == Set(input.places.map(\.id)))
        print("V41_REFERENCE seed=\(seed) optimalMinutes=\(optimal) selectedMinutes=\(actual) routeCalls=\(proposal.scheduleAssessment!.routeCalls)")
    }
}

@Test func v41AcceptsConfirmedOvernightAccessThatIncludesTheSelectedDate() async throws {
    let calls = V41Calls()
    var input = try v41Input(count: 1)
    input.startsAt = ISO8601DateFormatter().date(from: "2026-11-30T00:30:00+07:00")!
    input.finishBy = ISO8601DateFormatter().date(from: "2026-11-30T02:00:00+07:00")!
    input.places[0].visitSeconds = 1800
    input.places[0].visitConfirmation = .init(
        opensAt: ISO8601DateFormatter().date(from: "2026-11-29T23:00:00+07:00")!,
        closesAt: input.finishBy, publicAccessConfirmed: true)
    let repository = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: nil)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let done = try await finished(repository, id: job.id)
    #expect(done.status == .succeeded)
    #expect(done.result?.proposal?.stops.first?.visitStartsAt == input.startsAt.addingTimeInterval(600))
}

@Test func v41RefreshingATripPreservesItsOriginalAvailabilityWindowAndFlexibility() async throws {
    let calls = V41Calls()
    var input = try v41Input(count: 1)
    let opens = ISO8601DateFormatter().date(from: "2026-11-30T15:00:00+07:00")!
    input.places[0].visitConfirmation = .init(opensAt: opens, closesAt: opens.addingTimeInterval(3600), publicAccessConfirmed: true)
    input.enginePreferences?.flexibleDeparture = true
    let repository = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: nil)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let done = try await finished(repository, id: job.id)
    #expect(done.result?.proposal?.departureAt != input.startsAt)
    let saved = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
    let refreshed = try await repository.refreshExperienceRoute(tripID: saved.id)
    #expect(refreshed.input == saved.input)
    #expect(refreshed.plan.input == saved.input)
    #expect(refreshed.plan.input.enginePreferences?.flexibleDeparture == true)
    #expect(refreshed.plan.departureAt == saved.plan.departureAt)
}

@Test func v41LunaDayPartRemainsSoftAndAnExplicitVisitTimeTakesPrecedence() async throws {
    let calls = V41Calls()
    var services = v41Services(calls)
    services.order = { input, id in
        var plan = try await calls.order(input, id)
        plan.stops[0].preferredDayPart = "night"
        return plan
    }
    var input = try v41Input(count: 1)
    input.finishBy = ISO8601DateFormatter().date(from: "2026-11-30T22:00:00+07:00")!
    input.enginePreferences?.flexibleDeparture = true
    input.enginePreferences?.usesLuna = true
    input.enginePreferences?.allowsAIProcessing = true
    input.enginePreferences?.semanticAssistance = .requested
    let repository = try PocketPlanningRepository(services: services, connection: OrderConnection(), storageURL: nil)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let suggested = try await finished(repository, id: job.id)
    let visit = try #require(suggested.result?.proposal?.stops.first?.visitStartsAt)
    let night = ISO8601DateFormatter().date(from: "2026-11-30T18:00:00+07:00")!
    #expect(visit >= night)
    let required = input.startsAt.addingTimeInterval(1800)
    input.places[0].visitTiming = .required
    input.places[0].preferredAfter = required
    input.places[0].preferredBefore = required
    let fixed = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let honoured = try await finished(repository, id: fixed.id)
    #expect(honoured.status == .succeeded)
    #expect(honoured.result?.proposal?.stops.first?.visitStartsAt == required)
    #expect(await calls.modelIDs.count == 1)
}

@Test func v41BoundsCandidateWorkEvenWhenAllLegsNeedZeroProviderCalls() async throws {
    let calls = V41Calls()
    var input = try v41Input(count: 2)
    for index in input.places.indices {
        input.places[index].location = input.origin
    }
    input.enginePreferences?.maximumWaitMinutes = 60
    let planner = V41ItineraryPlanner(services: v41Services(calls), hours: { _ in .init(status: "unavailable") }, candidateLimit: 1)
    let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: input.startsAt)
    let result = try await planner.plan(job)
    let assessment = try #require(result.proposal?.scheduleAssessment)
    #expect(assessment.stopReason == "candidate_budget_exhausted")
    #expect(assessment.evaluatedCandidates == 1)
    #expect(assessment.routeCalls == 0)
    #expect(await calls.routeDates.isEmpty)
}

@Test func v41RejectsOverlappingBookingsBeforeRequestingTravel() async throws {
    let calls = V41Calls()
    var input = try v41Input(count: 2)
    let start = input.startsAt.addingTimeInterval(3600)
    input.places[0].activitySession = .init(startsAt: start, endsAt: start.addingTimeInterval(3600))
    input.places[1].activitySession = .init(startsAt: start.addingTimeInterval(1800), endsAt: start.addingTimeInterval(5400))
    let repository = try PocketPlanningRepository(services: v41Services(calls), connection: OrderConnection(), storageURL: nil)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let done = try await finished(repository, id: job.id)
    #expect(done.errorCode == "V41_ACCESS_CONFLICT")
    let affected = done.scheduleAssessment?.conflicts.filter { $0.code == "required_visits_overlap" }.compactMap(\.placeID) ?? []
    #expect(Set(affected) == Set(input.places.map(\.id)))
    #expect(await calls.routeDates.isEmpty)
}

@Test func v42TriesTomorrowWhenKnownHoursExcludeTodayAndKeepsLockedDates() async throws {
    let anchor = ISO8601DateFormatter().date(from: "2026-11-30T12:00:00+07:00")!
    var input = try v41Input()
    input.enginePreferences?.orderingMethod = .hybridV42
    input.enginePreferences?.scheduleSource = .timingAnswer
    input.enginePreferences?.tripTiming = .now
    input.enginePreferences?.timingAnchor = anchor
    input.places[0].sourceID = "apple:museum"
    let days = (1 ... 7).map { weekday in
        ["weekday": weekday, "intervals": weekday == 3 ? [["startSeconds": 32400, "endSeconds": 57600]] : []] as [String: Any]
    }
    let data = try JSONSerialization.data(withJSONObject: ["timezone": input.timeZone, "placeId": "museum", "weekly": days])
    let hours = try JSONDecoder().decode(PlanningRegularHours.self, from: data)
    let calls = V41Calls()
    let planner = V41ItineraryPlanner(services: v41Services(calls, model: false),
                                      hours: { _ in .init(status: "available", hours: hours) })
    let result = try await planner.plan(.init(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: anchor))
    let proposal = try #require(result.proposal)
    let tomorrow = try #require(PlanningDayWindow.tomorrow(after: anchor, timeZone: input.timeZone))
    #expect(proposal.input.startsAt == tomorrow.start)
    #expect(proposal.rescheduledFromDate != nil)
    #expect(proposal.input.places == input.places)
    #expect(proposal.scheduleAssessment?.dates.count == 2)
    #expect(await calls.routeDates.allSatisfy { $0 >= tomorrow.start })
    #expect(await calls.modelIDs.isEmpty)

    input.enginePreferences?.scheduleSource = .manual
    do {
        _ = try await planner.plan(.init(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: anchor))
        Issue.record("Expected known closure on the manually selected day")
    } catch let failure as PlanningScheduleFailure {
        #expect(failure.code == "V41_ACCESS_CONFLICT")
        #expect(failure.assessment.dates.count == 1)
    }
}

@Test(arguments: [
    ("MKPOICategoryMuseum", 9, 16),
    ("movie_theater", 10, 26),
    ("shopping_mall", 10, 22),
    ("unclassified", 10, 17)
])
func v42UsesUnverifiedHoursAsAVisitPreference(category: String, opens: Int, closes: Int) async throws {
    let anchor = ISO8601DateFormatter().date(from: "2026-11-30T06:00:00+07:00")!
    var input = try v41Input(count: 1)
    input.startsAt = anchor
    input.finishBy = anchor.addingTimeInterval(12 * 3600)
    input.enginePreferences?.orderingMethod = .hybridV42
    input.enginePreferences?.flexibleDeparture = true
    input.places[0].categories = [category]
    input.places[0].sourceID = "apple:unknown"
    let rule = EstimatedVisitWindow(categories: [category])
    #expect(rule.opensHour == opens)
    #expect(rule.closesHour == closes)
    let interval = try #require(rule.interval(on: anchor, timeZone: input.timeZone))
    if closes == 26 {
        #expect(interval.end == ISO8601DateFormatter().date(from: "2026-12-01T02:00:00+07:00"))
    }
    let calls = V41Calls()
    let planner = V41ItineraryPlanner(services: v41Services(calls, model: false),
                                      hours: { _ in .init(status: "available") })
    func run(_ input: PlanningInput) async throws -> PlanProposal {
        let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: anchor)
        return try #require(try await planner.plan(job).proposal)
    }
    let preferred = try await run(input)
    #expect(try #require(preferred.stops.first?.visitStartsAt) >= interval.start)
    #expect(try #require(preferred.stops.first?.departureAt) <= interval.end)
    #expect(preferred.scheduleAssessment?.unresolved.contains { $0.source == EstimatedVisitWindow.source } == true)

    input.enginePreferences?.flexibleDeparture = false
    input.finishBy = anchor.addingTimeInterval(90 * 60)
    let outside = try await run(input)
    #expect(try #require(outside.stops.first?.departureAt) < interval.start)
    #expect(outside.scheduleAssessment?.needsAccessConfirmation == true)
    #expect(await calls.modelIDs.isEmpty)
}

@Test func v42VeryLateNowRemainsValidAndReportsWhenNeitherDayCanFit() async throws {
    let anchor = ISO8601DateFormatter().date(from: "2026-11-30T23:59:59+07:00")!
    var input = try v41Input()
    input.enginePreferences?.orderingMethod = .hybridV42
    input.enginePreferences?.scheduleSource = .timingAnswer
    input.enginePreferences?.tripTiming = .now
    input.enginePreferences?.timingAnchor = anchor
    let draft = try #require(try PlanningDayWindow.v41Inputs(input, at: anchor).first)
    try draft.validate(purpose: .firstItinerary)
    // Two 8-hour visits cannot fit into either day's available window.
    for index in input.places.indices { input.places[index].visitSeconds = 8 * 3600 }
    let calls = V41Calls()
    let planner = V41ItineraryPlanner(services: v41Services(calls, model: false), hours: { _ in .init(status: "unavailable") })
    let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: anchor)
    do {
        _ = try await planner.plan(job)
        Issue.record("Expected both dates to be too short")
    } catch let failure as PlanningScheduleFailure {
        #expect(failure.code == "V4_WINDOW_TOO_SHORT")
        #expect(failure.assessment.dates.count == 2)
    }
    #expect(await calls.routeDates.isEmpty)
}
