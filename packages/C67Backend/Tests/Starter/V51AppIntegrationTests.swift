import C67Domain
import C67PlannerV5
import Foundation
import Testing
@testable import C67Data

private struct V51TestConnection: PocketConnectionProviding {
    func credentials() async -> PocketCredentials { .init(serverURL: "", token: "") }
    func update(serverURL: String, token: String) async throws { throw PlanningError.unavailable }
}

private actor V51ForecastCounter {
    private(set) var count = 0
    func forecast(start: Date, end: Date) -> PocketScheduleForecast {
        count += 1
        return .init(series: [.init(kind: .uvIndex, source: "Synthetic hourly forecast",
                                   samples: [.init(interval: .init(start: start, end: end), value: 4)])])
    }
}

private actor HoursRequests {
    var batches: [[String]] = []
    func lookup(_ ids: [String]) -> [String: PlanningHoursLookup] {
        batches.append(ids)
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, .init(status: "unavailable")) })
    }
}

@Test func v52BatchesOpeningHoursOnceAndPreservesTheV51Schedule() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let finish = now.addingTimeInterval(7200)
    let connection = V51TestConnection()
    let calls = HoursRequests()
    var services = PocketPlanningServices(travel: { _, _, _, _ in .init(seconds: 120, meters: 500) },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable },
                                          hours: { _ in .init(status: "unavailable") })
    let baseline = try PocketPlanningRepository(services: services, connection: connection, storageURL: nil,
                                                 synthetic: true, jobClock: { now })
    services.batchHours = { await calls.lookup($0) }
    services.hours = { _ in
        Issue.record("The batch path must not issue a single lookup")
        return .init(status: "temporary_error")
    }
    let batch = try PocketPlanningRepository(services: services, connection: connection, storageURL: nil,
                                              synthetic: true, jobClock: { now }, currentOrderingOnly: true)
    let places = ["I1", "I2", "I2", "I3"].enumerated().map { index, id in
        var place = PlanningPlace(id: UUID(), name: "Stop \(index)", location: .init(latitude: 0, longitude: Double(index + 1)),
                                  visitSeconds: 600)
        place.durationOverridden = true
        place.sourceID = "apple:" + id
        if id == "I3" { place.visitConfirmation = .init(opensAt: now, closesAt: finish, publicAccessConfirmed: true) }
        return place
    }
    var input = PlanningInput(title: "Hours comparison", origin: .init(latitude: 0, longitude: 0), places: places,
                              preferences: "", startsAt: now, finishBy: finish, timeZone: "UTC", mode: .automobile)
    var preferences = PlanningPreferences()
    preferences.orderingMethod = .hybridV51
    preferences.semanticAssistance = .disabled
    preferences.scheduleSource = .manual
    input.enginePreferences = preferences
    var plans: [PlanProposal] = []
    var batchJob: PlanningJob?
    for repository in [baseline, batch] {
        let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
        plans.append(try #require(try await finished(repository, id: job.id).result?.proposal))
        batchJob = job
    }
    #expect(plans.map(\.effectiveOrderingMethod) == [.hybridV51, .hybridV52])
    #expect(plans[0].stops == plans[1].stops)
    #expect(plans[0].scheduleAssessment == plans[1].scheduleAssessment)
    #expect(await calls.batches == [["I1", "I2"]])

    let edited = try await batch.updateExperienceRoute(jobID: try #require(batchJob).id,
                                                        orderedIDs: Array(plans[1].stops.map(\.id).reversed()),
                                                        departure: nil)
    #expect(edited.result?.proposal?.stops.map(\.id) == Array(plans[1].stops.map(\.id).reversed()))
    #expect(await calls.batches == [["I1", "I2"], ["I1", "I2"]])
}

@Test func v52RepositoryReadsV51AndUpgradesEditsAndActiveReplans() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let counter = V51ForecastCounter()
    let connection = V51TestConnection()
    var services = PocketPlanningServices(travel: { _, _, _, _ in .init(seconds: 120, meters: 500) },
                                          weather: { _, _, _ in throw PlanningError.invalidResponse },
                                          advise: { _ in throw PlanningError.invalidResponse })
    services.scheduleForecast = { _, start, end, _ in await counter.forecast(start: start, end: end) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("trips.json")
    let legacyRepository = try PocketPlanningRepository(services: services, connection: connection, storageURL: storage,
                                                        synthetic: true, jobClock: { now })
    let origin = PlanningPoint(latitude: 0, longitude: 0)
    var outside = PlanningPlace(id: UUID(), name: "Synthetic park", location: .init(latitude: 0, longitude: 1), visitSeconds: 600)
    outside.visitExposure = .sheltered
    outside.durationOverridden = true
    var inside = PlanningPlace(id: UUID(), name: "Synthetic exhibit", location: outside.location, visitSeconds: 600)
    inside.visitExposure = .outdoor
    inside.durationOverridden = true
    let finish = now.addingTimeInterval(7200)
    let access = PlanningVisitConfirmation(opensAt: now, closesAt: finish, publicAccessConfirmed: true)
    outside.visitConfirmation = access
    inside.visitConfirmation = access
    var input = PlanningInput(title: "Synthetic v5.1 repository integration", origin: origin, places: [outside, inside],
                              preferences: "", startsAt: now, finishBy: finish, timeZone: "UTC", mode: .automobile)
    var options = PlanningPreferences()
    options.orderingMethod = .hybridV51
    options.semanticAssistance = .disabled
    options.scheduleSource = .manual
    options.checkInBufferMinutes = 17
    options.extraTravelMinutes = 4
    options.returnToOrigin = true
    input.enginePreferences = options
    let job = try await legacyRepository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let legacy = try #require(try await finished(legacyRepository, id: job.id).result?.proposal)
    let repository = try PocketPlanningRepository(services: services, connection: connection, storageURL: storage,
                                                   synthetic: true, jobClock: { now }, currentOrderingOnly: true)
    #expect(try await repository.planningJob(id: job.id).result?.proposal == legacy)
    #expect(legacy.effectiveOrderingMethod == .hybridV51)
    let archivedV51 = try JSONEncoder().encode(legacy)
    #expect(try JSONDecoder().decode(PlanProposal.self, from: archivedV51) == legacy)
    let order = legacy.stops.map(\.id).reversed()
    let edit = try await repository.updateExperienceRoute(jobID: job.id, orderedIDs: Array(order), departure: nil)
    let updated = try #require(edit.result?.proposal)
    #expect(updated.effectiveOrderingMethod == .hybridV52)
    #expect(updated.stops.map(\.id) == Array(order))
    #expect(updated.scheduleDecision?.outdoor.count == 2)
    #expect(updated.scheduleDecision?.outdoor.flatMap(\.readings).filter { $0.id == "UV index" }.map(\.value) == [4, 4])
    #expect(await counter.count == 2)
    #expect(updated.input.enginePreferences?.checkInBufferMinutes == 17)
    #expect(updated.input.enginePreferences?.extraTravelMinutes == 4)
    let archived = try JSONEncoder().encode(updated)
    #expect(try JSONDecoder().decode(PlanProposal.self, from: archived) == updated)

    let saved = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
    let prepared = try #require(try await repository.prepareStart(tripID: saved.id, expectedRevision: saved.revision))
    var startEvent = PlanningEvent(requestID: UUID(), expectedRevision: saved.revision, kind: .start)
    startEvent.preparationID = prepared.id
    let active = try await repository.recordEvent(tripID: saved.id, event: startEvent)
    let first = try #require(active.nextStop)
    let arrived = try await repository.recordEvent(tripID: active.id, event: .init(requestID: UUID(), expectedRevision: active.revision,
                                                                                  kind: .arrive, stopID: first.id))
    let replan = try await repository.requestPlan(.init(requestID: UUID(), purpose: .replan, input: arrived.input,
                                                        tripID: arrived.id, baseRevision: arrived.revision))
    let repeated = try #require(try await finished(repository, id: replan.id).result?.proposal)
    #expect(repeated.effectiveOrderingMethod == .hybridV52)
    #expect(repeated.stops.first?.arrivalAt == arrived.currentArrivedAt)
    #expect(repeated.stops.map(\.id) == Array(order))
    #expect(repeated.returnTravelSeconds == 120)
}

@Test(arguments: [nil, PlanningOrderingMethod.hybridV42, .hybridV51])
func currentRepositoryUsesV52ForNewPlansAndReplans(method: PlanningOrderingMethod?) async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let services = PocketPlanningServices(travel: { _, _, _, _ in .init(seconds: 120, meters: 500) },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable })
    let repository = try PocketPlanningRepository(services: services, connection: V51TestConnection(),
                                                   storageURL: nil, synthetic: true, jobClock: { now },
                                                   currentOrderingOnly: true)
    let origin = PlanningPoint(latitude: 0, longitude: 0)
    var place = PlanningPlace(id: UUID(), name: "Synthetic stop",
                              location: .init(latitude: 0, longitude: 1), visitSeconds: 600)
    place.durationOverridden = true
    var input = PlanningInput(title: "Current ordering", origin: origin, places: [place], preferences: "",
                              startsAt: now, finishBy: now.addingTimeInterval(7200), timeZone: "UTC", mode: .automobile)
    var preferences = PlanningPreferences()
    preferences.orderingMethod = method
    preferences.semanticAssistance = .disabled
    preferences.scheduleSource = .manual
    preferences.checkInBufferMinutes = 19
    input.enginePreferences = preferences

    for purpose in [PlanningPurpose.firstItinerary, .plan] {
        let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: purpose, input: input))
        let proposal = try #require(try await finished(repository, id: job.id).result?.proposal)
        #expect(proposal.effectiveOrderingMethod == .hybridV52)
        #expect(proposal.input.enginePreferences?.checkInBufferMinutes == 19)
        let trip = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
        let replan = try await repository.requestPlan(.init(requestID: UUID(), purpose: .replan, input: trip.input,
                                                            tripID: trip.id, baseRevision: trip.revision))
        let revised = try #require(try await finished(repository, id: replan.id).result?.proposal)
        #expect(revised.effectiveOrderingMethod == .hybridV52)
        #expect(revised.input.enginePreferences?.checkInBufferMinutes == 19)
    }
}

@Test func savedV51DateRevisionPersistsOnlyAfterSuccessfulApply() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let canceledDate = now.addingTimeInterval(86_400)
    let newDate = now.addingTimeInterval(172_800)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("trips.json")
    let connection = V51TestConnection()
    let services = PocketPlanningServices(travel: { _, _, departure, _ in
        if departure >= canceledDate, departure < newDate {
            try await Task.sleep(for: .seconds(30))
        }
        return .init(seconds: 120, meters: 500)
    }, weather: { _, _, _ in throw PlanningError.unavailable },
       advise: { _ in throw PlanningError.unavailable })
    let legacy = try PocketPlanningRepository(services: services, connection: connection, storageURL: storage,
                                               synthetic: true, jobClock: { now })
    func openCurrent() throws -> PocketPlanningRepository {
        try PocketPlanningRepository(services: services, connection: connection, storageURL: storage,
                                     synthetic: true, jobClock: { now }, currentOrderingOnly: true)
    }
    var place = PlanningPlace(id: UUID(), name: "Synthetic stop",
                              location: .init(latitude: 0, longitude: 1), visitSeconds: 600)
    place.durationOverridden = true
    var input = PlanningInput(title: "Saved v5.1", origin: .init(latitude: 0, longitude: 0), places: [place],
                              preferences: "", startsAt: now, finishBy: now.addingTimeInterval(7200), timeZone: "UTC",
                              mode: .automobile)
    var preferences = PlanningPreferences()
    preferences.orderingMethod = .hybridV51
    preferences.semanticAssistance = .disabled
    preferences.scheduleSource = .manual
    input.enginePreferences = preferences
    let initial = try await legacy.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    _ = try #require(try await finished(legacy, id: initial.id).result?.proposal)
    let saved = try await legacy.applyProposal(jobID: initial.id, expectedRevision: nil, requestID: UUID())
    #expect(saved.plan.effectiveOrderingMethod == .hybridV51)

    let repository = try openCurrent()
    func request(_ departure: Date) -> PlanningRequest {
        var request = PlanningRequest(requestID: UUID(), purpose: .replan, input: saved.input,
                                      tripID: saved.id, baseRevision: saved.revision)
        request.replacementDeparture = departure
        return request
    }
    await #expect(throws: PlanningError.invalidInput) {
        try await repository.requestPlan(request(input.finishBy))
    }
    #expect(try await openCurrent().personalTrips() == [saved])

    let canceled = try await repository.requestPlan(request(canceledDate))
    try await repository.cancelPlanning(id: canceled.id)
    #expect(try await openCurrent().personalTrips() == [saved])

    let revised = try await repository.requestPlan(request(newDate))
    let proposal = try #require(try await finished(repository, id: revised.id).result?.proposal)
    #expect(proposal.effectiveOrderingMethod == .hybridV52)
    #expect(proposal.departureAt == newDate)
    #expect(try await openCurrent().personalTrips() == [saved])
    let applied = try await repository.applyProposal(jobID: revised.id, expectedRevision: saved.revision, requestID: UUID())
    #expect(applied.revision == saved.revision + 1)
    #expect(applied.plan.stops.map(\.id) == saved.plan.stops.map(\.id))
    #expect(try await openCurrent().personalTrips() == [applied])
}

@Test func openMeteoScheduleForecastUsesPrecedingHoursAndPreservesGaps() throws {
    let data = Data("""
        {"hourly_units":{"time":"unixtime","apparent_temperature":"°C","uv_index":"","direct_radiation":"W/m²","precipitation_probability":"%"},
         "hourly":{"time":[3600,7200],"apparent_temperature":[28,30],"uv_index":[5,null],
                   "direct_radiation":[240,280],"precipitation_probability":[30,60]}}
        """.utf8)
    let forecast = try PocketOpenMeteoScheduleForecast.decode(data)
    let temperature = try #require(forecast.series.first { $0.kind == .apparentTemperature })
    let uv = try #require(forecast.series.first { $0.kind == .uvIndex })
    let radiation = try #require(forecast.series.first { $0.kind == .directIrradiance })
    #expect(temperature.samples.first?.interval.start == Date(timeIntervalSince1970: 3600))
    #expect(uv.samples.count == 1)
    #expect(uv.samples.first?.interval.start == Date(timeIntervalSince1970: 0))
    #expect(radiation.samples.last?.interval.end == Date(timeIntervalSince1970: 7200))
    #expect(forecast.rain.map(\.probability) == [0.3, 0.6])
}

private actor V51RouteProbe {
    private(set) var dates: [Date] = []
    let pauseFirst: Bool

    init(pauseFirst: Bool = false) { self.pauseFirst = pauseFirst }

    func record(_ at: Date) async throws {
        dates.append(at)
        if pauseFirst, dates.count == 1 { try await Task.sleep(for: .seconds(30)) }
    }
}

@Test func v51RepositorySharesBudgetAcrossDatesAndRestarts() async throws {
    let repositoryFile = FileManager.default.temporaryDirectory.appendingPathComponent("v51-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: repositoryFile) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let probe = V51RouteProbe(pauseFirst: true)
    let connection = V51TestConnection()
    let services = PocketPlanningServices(travel: { _, _, date, _ in
        try await probe.record(date)
        return .init(seconds: 120, meters: 500)
    }, weather: { _, _, _ in throw PlanningError.unavailable }, advise: { _ in throw PlanningError.invalidResponse })
    func repository() throws -> PocketPlanningRepository {
        try .init(services: services, connection: connection, storageURL: repositoryFile, synthetic: true, jobClock: { now })
    }
    let first = try repository()
    var input = PlanningInput(title: "Synthetic date budget", origin: .init(latitude: 0, longitude: 0), places: [
        .init(id: UUID(), name: "Synthetic stop", location: .init(latitude: 0, longitude: 1), visitSeconds: 600)
    ], preferences: "", startsAt: now, finishBy: now.addingTimeInterval(3600), timeZone: "UTC", mode: .automobile)
    input.enginePreferences = .init()
    input.enginePreferences?.orderingMethod = .hybridV51
    input.enginePreferences?.semanticAssistance = .disabled
    input.enginePreferences?.tripTiming = .bestDay
    input.enginePreferences?.scheduleSource = .timingAnswer
    input.enginePreferences?.flexibleDeparture = true
    input.enginePreferences?.returnToOrigin = true
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
    let job = try await first.requestPlan(command)
    for _ in 0 ..< 100 {
        if await !probe.dates.isEmpty { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await probe.dates.count == 1)
    await first.suspendOrdering()
    let reopened = try repository()
    let resumed = try await reopened.requestPlan(command)
    #expect(resumed.id == job.id)
    let completed = try await finished(reopened, id: job.id)
    let timestamps = await probe.dates
    #expect(completed.status == .succeeded)
    #expect(timestamps.count <= 72)
    #expect(completed.scheduleAssessment?.routeCalls == timestamps.count)
    #expect(completed.scheduleAssessment?.dates.count ?? 0 >= 2)
}

@Test func v51CancellationRetainsReservedRouteCount() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let probe = V51RouteProbe(pauseFirst: true)
    let connection = V51TestConnection()
    let services = PocketPlanningServices(travel: { _, _, date, _ in
        try await probe.record(date)
        return .init(seconds: 120, meters: 500)
    }, weather: { _, _, _ in throw PlanningError.unavailable }, advise: { _ in throw PlanningError.invalidResponse })
    let repository = try PocketPlanningRepository(services: services, connection: connection, storageURL: nil,
                                                   synthetic: true, jobClock: { now })
    var input = PlanningInput(title: "Synthetic cancellation", origin: .init(latitude: 0, longitude: 0), places: [
        .init(id: UUID(), name: "Synthetic stop", location: .init(latitude: 0, longitude: 1), visitSeconds: 600)
    ], preferences: "", startsAt: now, finishBy: now.addingTimeInterval(3600), timeZone: "UTC", mode: .automobile)
    input.enginePreferences = .init()
    input.enginePreferences?.orderingMethod = .hybridV51
    input.enginePreferences?.semanticAssistance = .disabled
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    for _ in 0 ..< 100 {
        if await !probe.dates.isEmpty { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    try await repository.cancelPlanning(id: job.id)
    let cancelled = try await repository.planningJob(id: job.id)
    #expect(cancelled.status == .failed && cancelled.errorCode == "PLANNING_CANCELLED")
    #expect(cancelled.scheduleAssessment?.routeCalls == 1)
    #expect(await probe.dates.count == 1)
}
