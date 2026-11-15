import Foundation
import Testing
@testable import TripIntegration

@Suite("TJ routing improvement comparison", .serialized)
@MainActor struct BuswayImprovementTests {
    private struct Observation: Codable {
        var id: String
        var group: String
        var beforeFeasible: Bool
        var afterFeasible: Bool
        var beforeMilliseconds: Double
        var afterMilliseconds: Double
        var beforeRequests: Int
        var afterRequests: Int
        var rides: Int
        var routeIDs: [String]
        var categories: [String]
        var totalSeconds: Double?
        var searchLimited: Bool
    }

    private func pin(_ feed: BuswayFeed, _ id: String) throws -> PlacePin {
        try #require(feed.stops.first { $0.id == id }).pin
    }
    private func clock(_ feed: BuswayFeed, hour: Int = 9) -> Date {
        TripClock.calendar.startOfDay(for: feed.source.checkedAt).addingTimeInterval(Double(86400 + hour * 3600))
    }
    private func fixture() throws -> BuswayFeed {
        var feed = try BuswayFeed.load()
        feed.stops = feed.stops.filter { ["G00031", "P00017"].contains($0.id) }
        feed.services = [.init(id: "test", startDate: "20260101", endDate: "20261231", weekdays: Array(1 ... 7))]
        feed.patterns = [.init(id: "1-test", serviceID: "test", headsign: "Synthetic southbound", directionID: "1", shapeID: "test",
                               calls: [.init(stopID: "G00031", sequence: 1, arrivalOffset: 0, departureOffset: 0),
                                       .init(stopID: "P00017", sequence: 2, arrivalOffset: 1800, departureOffset: 1800)],
                               frequencies: [.init(start: 0, end: 86400, headway: 600, exactTimes: 0)])]
        return feed
    }
    private func transferFixture() throws -> BuswayFeed {
        var feed = try fixture()
        feed.schemaVersion = 2; feed.routeID = "network"; feed.category = "TJ"
        let original = try BuswayFeed.load()
        let middle = try #require(original.stops.first { $0.id == "G00021" })
        feed.stops.append(middle)
        feed.patterns[0].routeID = "1"; feed.patterns[0].category = "BRT"
        feed.patterns[0].calls[1].stopID = middle.id
        feed.patterns[0].calls[1].arrivalOffset = 600; feed.patterns[0].calls[1].departureOffset = 600
        var second = feed.patterns[0]; second.id = "6-test"; second.routeID = "6"
        second.calls[0].stopID = middle.id; second.calls[1].stopID = "P00017"
        feed.patterns.append(second)
        feed.transfers = [.init(fromStopID: middle.id, toStopID: middle.id, minimumSeconds: 120,
                                evidence: "Synthetic same-platform interchange with 120-second buffer")]
        try feed.validate()
        return feed
    }

    private func compare(id: String, group: String, before: BuswayFeed, after: BuswayFeed,
                         from: PlacePin, to: PlacePin, departure: Date, exact: Bool = false) async throws -> Observation {
        // Let independent actor-bound provider/timeout tests progress between benchmark inputs.
        await Task.yield()
        let oldWalking = ImprovementWalking(allowed: exact ? [from.id, to.id] : nil)
        let newWalking = ImprovementWalking(allowed: exact ? [from.id, to.id] : nil)
        let old = try BaselineBuswayPlanner(feed: before, walking: oldWalking, now: before.source.checkedAt)
        let current = try BuswayPlanner(feed: after, walking: newWalking, now: after.source.checkedAt)
        let started = Date()
        let oldResult = try await old.bus(from: from, to: to, departure: departure)
        let beforeTime = Date().timeIntervalSince(started) * 1000
        await Task.yield()
        let next = Date()
        let result = try await current.bus(from: from, to: to, departure: departure)
        let afterTime = Date().timeIntervalSince(next) * 1000
        if let result {
            try result.validate()
            #expect(abs(result.seconds - result.walkingSeconds - result.waitingSeconds - result.ridingSeconds) < 0.01)
            #expect(result.access.from.latitude == from.latitude)
            #expect(result.egress?.to.latitude == to.latitude)
            #expect(result.walks.allSatisfy { $0.seconds <= 1200 })
        }
        return .init(id: id, group: group, beforeFeasible: oldResult != nil, afterFeasible: result != nil,
                     beforeMilliseconds: beforeTime, afterMilliseconds: afterTime,
                     beforeRequests: oldWalking.requests, afterRequests: newWalking.requests,
                     rides: result?.rides.count ?? 0, routeIDs: result?.rides.map { $0.pattern.effectiveRouteID } ?? [],
                     categories: result?.rides.map { $0.pattern.effectiveCategory } ?? [],
                     totalSeconds: result?.seconds, searchLimited: current.searchLimited)
    }

    @Test func pairedPlatformServiceAndNetworkCoverage() async throws {
        var rows: [Observation] = []
        let legacy = try BuswayFeed.load(), network = try BuswayFeed.network()
        for decoys in 0 ..< 20 {
            for hour in [0, 1, 5, 6, 8, 9, 12, 17, 22, 23] {
                var feed = try fixture()
                let from = try pin(feed, "G00031"), to = try pin(feed, "P00017")
                for index in 0 ..< decoys {
                    var decoy = feed.stops[0]; decoy.id = "decoy-\(index)"; decoy.latitude += Double(index + 1) * 0.000001
                    feed.stops.append(decoy)
                }
                feed.stops[0].latitude += 0.0001
                let row = try await compare(id: "platform-\(decoys)-\(hour)", group: "route_aware_platforms_200", before: feed, after: feed,
                                            from: from, to: to, departure: clock(feed, hour: hour))
                rows.append(row)
                #expect(row.afterFeasible)
                #expect(row.afterRequests <= 2)
            }
        }
        let pairs = [("G00061", "G00031"), ("G00058", "G00030"), ("G00054", "G00021"),
                     ("G00052", "G00036"), ("G00051", "G00040"), ("G00034", "G00061"),
                     ("G00038", "G00058"), ("G00039", "G00054"), ("G00753", "G00060"), ("G00036", "G00030")]
        for (index, pair) in pairs.enumerated() {
            let from = try pin(legacy, pair.0), to = try pin(legacy, pair.1)
            for hour in [0, 1, 5, 6, 8, 9, 12, 17, 22, 23] {
                rows.append(try await compare(id: "destination-\(index)-\(hour)", group: "alternative_destination_platforms_100",
                                              before: legacy, after: legacy, from: from, to: to, departure: clock(legacy, hour: hour)))
            }
        }
        let routeIDs = Set(network.patterns.map(\.effectiveRouteID)).sorted()
        for routeID in routeIDs {
            let pattern = try #require(network.patterns.first { $0.effectiveRouteID == routeID })
            let board = try #require(pattern.calls.first { $0.pickupAllowed != false })
            guard let exit = pattern.calls.last(where: { $0.dropOffAllowed != false && $0.sequence > board.sequence && $0.stopID != board.stopID }) else { continue }
            let from = try pin(network, board.stopID), to = try pin(network, exit.stopID)
            rows.append(try await compare(id: "network-\(routeID)", group: "network_source_route_endpoints",
                                          before: legacy, after: network, from: from, to: to, departure: clock(network)))
        }
        // These pairs use the same attributed stop/time data while restricting the test to the two requested corridors.
        for (firstRoute, origin, secondRoute, destination) in [("2", "G00126", "1", "P00017"),
                                                               ("3", "G00161", "1", "P00017")] {
            var twoRoutes = network
            twoRoutes.patterns = network.patterns.filter { [firstRoute, secondRoute].contains($0.effectiveRouteID) }
            let used = Set(twoRoutes.patterns.flatMap { $0.calls.map(\.stopID) })
            twoRoutes.stops = twoRoutes.stops.filter { used.contains($0.id) }
            twoRoutes.transfers = twoRoutes.transfers?.filter { used.contains($0.fromStopID) && used.contains($0.toStopID) }
            let row = try await compare(id: "transfer-\(firstRoute)-\(secondRoute)", group: "official_two_corridor_transfer",
                                        before: legacy, after: twoRoutes, from: pin(network, origin), to: pin(network, destination), departure: clock(network))
            rows.append(row)
            #expect(row.afterFeasible && row.rides == 2)
        }
        if let output = ProcessInfo.processInfo.environment["TJ_IMPROVEMENT_OUTPUT"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try IntegrationJSON.encoder().encode(rows).write(to: directory.appendingPathComponent("paired-results.json"), options: .atomic)
        }
        #expect(rows.filter { $0.beforeFeasible && !$0.afterFeasible }.isEmpty)
        #expect(rows.filter { $0.afterFeasible }.count > rows.filter { $0.beforeFeasible }.count)
    }

    @Test func transferTimingPersistenceAndFailureBoundaries() async throws {
        let feed = try transferFixture()
        let walking = ImprovementWalking()
        let planner = try BuswayPlanner(feed: feed, walking: walking, now: feed.source.checkedAt)
        let journey = try #require(try await planner.bus(from: pin(feed, "G00031"), to: pin(feed, "P00017"), departure: clock(feed)))
        #expect(journey.rides.count == 2)
        #expect(journey.connection?.bufferSeconds == 120)
        try journey.validate()
        let decoded = try IntegrationJSON.decoder().decode(BuswayJourney.self, from: IntegrationJSON.encoder().encode(journey))
        try decoded.validate()
        #expect(decoded.rides.map { $0.pattern.effectiveRouteID } == ["1", "6"])
        var forged = decoded; forged.connection?.ride.boardAt.addTimeInterval(-120)
        #expect(throws: (any Error).self) { try forged.validate() }
        var missing = feed; missing.transfers = []
        let disconnected = try BuswayPlanner(feed: missing, walking: ImprovementWalking(), now: feed.source.checkedAt)
        #expect(try await disconnected.bus(from: pin(feed, "G00031"), to: pin(feed, "P00017"), departure: clock(feed)) == nil)
        var missed = feed
        missed.patterns[1].frequencies = [.init(start: 0, end: 9 * 3600 + 20 * 60, headway: 600, exactTimes: 0)]
        let late = try BuswayPlanner(feed: missed, walking: ImprovementWalking(), now: feed.source.checkedAt)
        #expect(try await late.bus(from: pin(feed, "G00031"), to: pin(feed, "P00017"), departure: clock(feed)) == nil)
        var restricted = feed; restricted.patterns[1].calls[0].pickupAllowed = false
        let prohibited = try BuswayPlanner(feed: restricted, walking: ImprovementWalking(), now: feed.source.checkedAt)
        #expect(try await prohibited.bus(from: pin(feed, "G00031"), to: pin(feed, "P00017"), departure: clock(feed)) == nil)
    }

    @Test func timeBudgetRejectsImpossibleDwellBeforeSearch() async throws {
        let catalog = try IntegrationCatalog.load(blokM: true)
        var request = try BlokMReplay.request()
        request.requiredCandidateIDs = ["bm01", "bm04", "bm08"]; request.desiredCount = 3
        request.deadline = request.departure.addingTimeInterval(90 * 60)
        let budget = TripTimeBudget.evaluate(request, selectedIDs: request.requiredCandidateIDs, catalog: catalog)
        #expect(budget.visitMinutes == 180 && budget.visitsExceedBudget)
        let pipeline = try BlokMReplay.pipeline()
        let review = try await pipeline.recommend(request, now: catalog.quality.sources.map(\.checkedAt).max() ?? request.departure.addingTimeInterval(-86400))
        await #expect(throws: (any Error).self) {
            _ = try await pipeline.prepare(review, selectedIDs: request.requiredCandidateIDs, now: request.departure.addingTimeInterval(-1))
        }
    }

    @Test func walkingRetriesOnlyTransientErrorsAndHonoursCancellation() async throws {
        let feed = try fixture()
        let provider = MapKitBuswayWalking()
        var attempts = 0
        provider.startRequest = { _, callback in
            attempts += 1
            if attempts == 1 { callback(nil, URLError(.networkConnectionLost)) }
            else { provider.cancel() }
        }
        await #expect(throws: CancellationError.self) {
            _ = try await provider.walk(from: pin(feed, "G00031"), to: pin(feed, "P00017"), departure: clock(feed))
        }
        #expect(attempts == 2 && provider.requests == 2)
        let invalid = MapKitBuswayWalking()
        invalid.startRequest = { _, callback in callback(nil, URLError(.badServerResponse)) }
        #expect(try await invalid.walk(from: pin(feed, "G00031"), to: pin(feed, "P00017"), departure: clock(feed)) == nil)
        #expect(invalid.requests == 1)
    }

    @Test func cityCatalogAndCustomOriginCompleteAnAuditedTJItinerary() async throws {
        let network = try BuswayFeed.network()
        let pipeline = try BlokMReplay.pipeline(city: true)
        var input = TripRequest(now: network.source.checkedAt)
        var day = TripClock.calendar.startOfDay(for: input.departure)
        while TripClock.calendar.component(.weekday, from: day) != 3 { day.addTimeInterval(86400) }
        input.departure = day.addingTimeInterval(9 * 3600)
        input.deadline = day.addingTimeInterval(18 * 3600)
        input.originQuery = "Perpustakaan Jakarta Cikini"
        input.useCityCatalog = true; input.useEmbedding = false; input.transport = .transjakartaBRT
        input.requiredCandidateIDs = ["erasmus"]; input.desiredCount = 1; input.profile.prefer = [.reading]
        let review = try await pipeline.recommend(input, now: network.source.checkedAt)
        let prepared = try await pipeline.prepare(review, selectedIDs: input.requiredCandidateIDs, now: network.source.checkedAt)
        let plan = try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: network.source.checkedAt)
        #expect(plan.feasible)
        #expect(plan.request.originQuery == input.originQuery)
        #expect(plan.stops.map(\.id) == ["erasmus"])
        #expect(plan.request.profile == input.profile)
        #expect(plan.legs.contains { !($0.busway?.rides.isEmpty ?? true) })
        try PlanAudit.validate(plan)
    }

    @Test func officialTransferCompletesItinerarySaveReloadAndExport() async throws {
        var feed = try BuswayFeed.network()
        feed.patterns = feed.patterns.filter { ["1", "2"].contains($0.effectiveRouteID) }
        let used = Set(feed.patterns.flatMap { $0.calls.map(\.stopID) })
        feed.stops = feed.stops.filter { used.contains($0.id) }
        feed.transfers = feed.transfers?.filter { used.contains($0.fromStopID) && used.contains($0.toStopID) }
        let origin = try pin(feed, "G00126")
        let catalog = try IntegrationCatalog.load(blokM: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TJTransferStorage-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let pipeline = IntegrationPipeline(catalog: catalog, search: ImprovementSearch(catalog: catalog, origin: origin),
                                           weather: .init(provider: ReplayWeather()), logDirectory: folder.appendingPathComponent("logs"),
                                           buswayWalking: ImprovementWalking(), buswayFeed: feed)
        var input = try BlokMReplay.request()
        input.originQuery = "Pulo Gadung"; input.transport = .transjakartaBRT
        input.requiredCandidateIDs = ["bm08"]; input.desiredCount = 1
        let review = try await pipeline.recommend(input, now: feed.source.checkedAt)
        let prepared = try await pipeline.prepare(review, selectedIDs: input.requiredCandidateIDs, now: feed.source.checkedAt)
        let plan = try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: feed.source.checkedAt)
        #expect(plan.feasible)
        #expect(plan.legs.contains { $0.busway?.connection != nil })
        try PlanAudit.validate(plan)
        var session = IntegrationSession(); session.proposal = plan; try session.apply(now: feed.source.checkedAt)
        let store = TripStore(directory: folder)
        try await store.save(session)
        let restored = try #require(try await store.load().session.accepted)
        try PlanAudit.validate(restored)
        #expect(restored.id == plan.id && restored.legs.contains { $0.busway?.connection != nil })
        let exported = try await store.export(restored)
        let text = try String(contentsOf: exported.appendingPathComponent("REPORT.md"), encoding: .utf8)
        #expect(text.contains("→ 1 arah") || text.contains("→ 2 arah"))
        #expect(text.contains("CC BY 4.0"))
    }
}

@MainActor private struct ImprovementSearch: TripPlaceSearching {
    let catalog: IntegrationCatalog
    let origin: PlacePin
    func cancel() {}
    func search(query: String) async throws -> [PlacePin] {
        if query == "Pulo Gadung" { return [origin] }
        guard let candidate = catalog.quality.candidates.first(where: { $0.mapQuery == query }),
              let point = catalog.region?.anchors.first(where: { $0.candidateID == candidate.id })?.pin else { return [] }
        return [point]
    }
}

@MainActor private final class ImprovementWalking: BuswayWalking {
    var requests = 0
    let synthetic = true
    let failures: [String] = []
    let allowed: Set<String>?
    init(allowed: Set<String>? = nil) { self.allowed = allowed }
    func cancel() {}
    func walk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayWalk? {
        try Task.checkCancellation()
        requests += 1
        if let allowed, !allowed.contains(from.id) || !allowed.contains(to.id) { return nil }
        let metres = WeatherPolicy.distance(from, to)
        return .init(from: from, to: to, seconds: ceil(metres / 1.2), distanceMeters: metres, provider: "synthetic_walking")
    }
}
