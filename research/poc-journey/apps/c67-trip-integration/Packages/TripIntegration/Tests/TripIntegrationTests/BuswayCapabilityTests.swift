import Foundation
import MapKit
import Testing
@testable import TripIntegration

private struct CapabilityManifest: Decodable {
    var schemaVersion: Int
    var scope: String
    var id: String
    var snapshotSHA256: String
    var cases: [CapabilityCase]
}

private struct CapabilityCase: Codable, Sendable {
    var id: String
    var title: String
    var origin: String
    var destination: String
    var requiredCapability: String
    var expectedOutcome: String
    var blockingLayer: String
    var assertion: String
    var routeCandidates: [String]
    var serviceCategory: String
    var operators: [String]
}

private struct CapabilityObservation: Codable {
    var id: String
    var outcome: String
    var layer: String
    var detail: String
    var evidenceMode = "synthetic_probe_with_pinned_gtfs"
    var generatedJourney = false
    var elapsedMilliseconds = 0.0
    var walkingRequests: Int? = nil
    var measurements: [String: Double] = [:]
}

private struct SweepObservation: Codable {
    var id: String
    var from: String
    var to: String
    var departure: Date
    var accessDelayMinutes: Int
    var walkingComponentSeconds: Double
    var outcome: String
    var walkingRequests: Int
    var elapsedMilliseconds: Double
    var totalSeconds: Double?
    var patternID: String?
    var boardID: String?
    var alightID: String?
    var detail: String
}

private struct CapabilityFailure: Error, CustomStringConvertible {
    var description: String
}

/// These tests exercise the existing engine. Unsupported capabilities are gates, not routed trips.
@Suite("TransJakarta capability boundaries", .serialized)
@MainActor struct BuswayCapabilityTests {
    private func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw CapabilityFailure(description: message) }
    }

    private func rejected(_ operation: () throws -> Void) -> Bool {
        do { try operation(); return false } catch { return true }
    }

    private func manifest() throws -> CapabilityManifest {
        let url = try #require(Bundle.module.url(forResource: "transjakarta-capability-v3", withExtension: "json"))
        return try JSONDecoder().decode(CapabilityManifest.self, from: Data(contentsOf: url))
    }

    private func write(_ value: some Encodable, name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["TJ_CAPABILITY_OUTPUT"] else { return }
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try IntegrationJSON.encoder().encode(value).write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    private func pin(_ feed: BuswayFeed, _ id: String) throws -> PlacePin {
        try #require(feed.stops.first { $0.id == id }).pin
    }

    private func day(_ feed: BuswayFeed) -> Date {
        TripClock.calendar.startOfDay(for: feed.source.checkedAt).addingTimeInterval(86400)
    }

    /// Authored two-stop service, using actual coordinates but synthetic offsets and frequencies.
    private func simpleFeed(_ original: BuswayFeed) throws -> BuswayFeed {
        var feed = original
        feed.stops = try ["G00031", "P00017"].map { id in try #require(original.stops.first { $0.id == id }) }
        feed.services = [.init(id: "capability", startDate: "20260101", endDate: "20261231", weekdays: Array(1 ... 7))]
        feed.patterns = [.init(id: "1-capability", serviceID: "capability", headsign: "Synthetic southbound",
                               directionID: "1", shapeID: "synthetic",
                               calls: [.init(stopID: "G00031", sequence: 1, arrivalOffset: 0, departureOffset: 0),
                                       .init(stopID: "P00017", sequence: 2, arrivalOffset: 1800, departureOffset: 1800)],
                               frequencies: [.init(start: 9 * 3600, end: 10 * 3600, headway: 600, exactTimes: 0)])]
        try feed.validate()
        return feed
    }

    private func bus(_ feed: BuswayFeed, from: String = "G00031", to: String = "P00017",
                     departure: Date, walking: CapabilityWalking = .init()) async throws -> BuswayJourney? {
        let planner = try BuswayPlanner(feed: feed, walking: walking, now: feed.source.checkedAt)
        return try await planner.bus(from: pin(feed, from), to: pin(feed, to), departure: departure)
    }

    /// Independent result invariants supplement the production validator.
    private func audit(_ journey: BuswayJourney) throws {
        try journey.validate()
        try check(journey.arrival >= journey.departure, "Arrival precedes departure")
        try check(abs(journey.seconds - journey.walkingSeconds - journey.waitingSeconds - journey.ridingSeconds) < 0.001,
                  "Component arithmetic does not reconcile")
        if let ride = journey.ride {
            try check(ride.boardSequence < ride.alightSequence, "Backward stop occurrences")
            try check(ride.boardAt >= journey.departure.addingTimeInterval(journey.access.seconds), "Board before access")
            try check(journey.waitingSeconds >= Double(ride.frequency.headway), "Missing full-headway buffer")
            try check(ride.boardAt < ride.alightAt, "Nonpositive bus duration")
        } else {
            try check(journey.waitingSeconds == 0 && journey.ridingSeconds == 0, "Walking counted as bus")
        }
    }

    @Test(arguments: 1 ... 64)
    func coreScenario(_ number: Int) async throws {
        let specification = try manifest()
        let feed = try BuswayFeed.load()
        try check(specification.schemaVersion == 3 && specification.scope == "transjakarta_only" && specification.cases.count == 64, "Invalid manifest")
        try check(specification.snapshotSHA256 == feed.source.sourceSHA256, "Manifest/feed hash drift")
        let id = String(format: "T%02d", number)
        let scenario = try #require(specification.cases.first { $0.id == id })
        try check(scenario.operators == ["Tije"], "Active case includes a non-TJ operator")
        let started = Date()
        var result: CapabilityObservation
        do {
            result = try await probe(number, scenario: scenario, feed: feed)
        } catch {
            result = .init(id: id, outcome: "defect", layer: scenario.blockingLayer, detail: String(describing: error))
        }
        result.elapsedMilliseconds = Date().timeIntervalSince(started) * 1000
        try write(result, name: "\(id).json")
        #expect(result.outcome == scenario.expectedOutcome, "\(id): \(result.detail)")
    }

    private func probe(_ number: Int, scenario: CapabilityCase, feed: BuswayFeed) async throws -> CapabilityObservation {
        var result = CapabilityObservation(id: scenario.id, outcome: "defect",
                                           layer: scenario.blockingLayer, detail: "")
        let departure = day(feed).addingTimeInterval(9 * 3600)
        let now = feed.source.checkedAt
        switch number {
        case 1 ... 3:
            result.outcome = "supported_feasible"
            let pair = [("G00034", "G00060"), ("G00061", "G00031"), ("G00036", "G00030")][number - 1]
            let walking = CapabilityWalking(allowed: Set([pair.0, pair.1]))
            let journey = try #require(try await bus(feed, from: pair.0, to: pair.1, departure: departure, walking: walking))
            try audit(journey)
            let ride = try #require(journey.ride)
            result.generatedJourney = true
            result.walkingRequests = walking.requests
            result.measurements = ["totalSeconds": journey.seconds, "walkSeconds": journey.walkingSeconds,
                                   "waitSeconds": journey.waitingSeconds, "rideSeconds": journey.ridingSeconds]
            result.detail = "Actual engine leg: \(ride.board.name) [\(ride.board.id)] -> \(ride.alight.name) [\(ride.alight.id)], \(ride.patternID). Synthetic walking; no catalog or live-provider claim."
        case 4:
            result.outcome = "supported_feasible"
            let walking = CapabilityWalking(seconds: 0)
            let planner = try BuswayPlanner(feed: feed, walking: walking, now: now)
            let point = try pin(feed, "G00031")
            let journey = try #require(try await planner.directWalk(from: point, to: point, departure: departure))
            try audit(journey)
            try check(journey.ride == nil, "Same-stop walk became a bus ride")
            result.generatedJourney = true
            result.walkingRequests = walking.requests
            result.detail = "Walking only, zero seconds in this authored fixture; excluded from TJ ride support."
        case 5 ... 8, 27, 58:
            result.outcome = "unsupported_capability"
            var expanded = feed
            expanded.routeID = scenario.routeCandidates.joined(separator: "+")
            try check(rejected { try expanded.validate() }, "Multi-route feed admitted unexpectedly")
            let sample = try #require(try await bus(try simpleFeed(feed), departure: departure))
            let fields = try JSONSerialization.jsonObject(with: IntegrationJSON.encoder().encode(sample)) as! [String: Any]
            try check(fields["ride"] != nil && fields["rides"] == nil, "Journey contract changed: update capability probe")
            result.detail = "Legacy schema-v1 contract gate: multi-route feed rejected; journey serializes one ride only. No transfer itinerary generated for \(scenario.origin) -> \(scenario.destination)."
        case 9 ... 15, 17 ... 24, 49 ... 57:
            result.outcome = "unsupported_capability"
            var expanded = feed
            expanded.routeID = try #require(scenario.routeCandidates.first)
            expanded.category = scenario.serviceCategory
            try check(scenario.operators == ["Tije"], "Non-TJ operator in the active suite")
            try check(rejected { try expanded.validate() }, "Additional TJ route/category admitted unexpectedly")
            result.detail = "Legacy schema-v1 feed gate rejected route/category probe \(expanded.routeID), category \(expanded.category). No journey generated for \(scenario.origin) -> \(scenario.destination); full-feed audits check the actual source pattern separately."
        case 16:
            result.outcome = "supported_conflict"
            let outside = PlacePin(id: "outside", name: "Outside", address: "Synthetic out-of-bounds input", latitude: 0, longitude: 0)
            try check(!IntegrationCatalog.contains(outside), "Out-of-region pin was admitted")
            var request = try BlokMReplay.request(); request.originQuery = "Bekasi"
            try request.validate(catalog: IntegrationCatalog.load(blokM: true), now: now)
            result.detail = "Custom origin text is admitted; a separate out-of-bounds coordinate probe is still rejected. No Bekasi coordinate route is claimed."
        case 25:
            result.outcome = "supported_conflict"
            var disconnected = try simpleFeed(feed)
            disconnected.stops[1].name = disconnected.stops[0].name
            var a = disconnected.stops[0]; a.id = "synthetic-a"; a.latitude -= 0.02
            var b = disconnected.stops[1]; b.id = "synthetic-b"; b.latitude += 0.02
            disconnected.stops += [a, b]
            disconnected.patterns[0].calls[1].stopID = a.id
            var second = disconnected.patterns[0]; second.id = "1-disconnected"
            second.calls[0].stopID = b.id; second.calls[1].stopID = "P00017"
            disconnected.patterns.append(second)
            let walking = CapabilityWalking(allowed: Set(["G00031", "P00017"]))
            try check(try await bus(disconnected, departure: departure, walking: walking) == nil, "Same names fabricated a connection")
            result.detail = "Disconnected synthetic patterns with same-named endpoints produce no bus journey."
        case 26:
            result.outcome = "supported_conflict"
            try check(try await bus(try simpleFeed(feed), from: "P00017", to: "G00031", departure: departure) == nil,
                      "Reverse direction was fabricated")
            result.detail = "A single directional pattern does not yield a reverse ride."
        case 28:
            result.outcome = "provider_failure"
            let walking = CapabilityWalking(unavailable: true)
            try check(try await bus(try simpleFeed(feed), departure: departure, walking: walking) == nil, "Unavailable access got a fabricated route")
            result.walkingRequests = walking.requests
            result.detail = "Injected walking unavailability blocks the bus route; no fallback ETA."
        case 29:
            result.outcome = "supported_feasible"
            let journey = try #require(try await bus(try simpleFeed(feed), departure: departure.addingTimeInterval(-3600)))
            try audit(journey)
            try check(journey.waitingSeconds == 4080, "Opening wait not included")
            result.generatedJourney = true
            result.detail = "08:00 departure + 120-second access; 09:10 boarding includes opening wait and full headway."
        case 30:
            result.outcome = "supported_conflict"
            let last = departure.addingTimeInterval(50 * 60 - 120)
            try check(try await bus(try simpleFeed(feed), departure: last) == nil, "Exclusive end permitted boarding")
            result.detail = "Synthetic 10:00 service end is exclusive; ready at 09:50 plus 10-minute headway is unavailable."
        case 31:
            result.outcome = "supported_feasible"
            var overnight = try simpleFeed(feed)
            overnight.patterns[0].frequencies = [.init(start: 23 * 3600, end: 26 * 3600, headway: 600, exactTimes: 0)]
            let journey = try #require(try await bus(overnight, departure: day(feed).addingTimeInterval(3600)))
            try audit(journey)
            try check(journey.ride?.serviceDay == day(feed).addingTimeInterval(-86400), "Wrong service day")
            result.generatedJourney = true
            result.detail = "Synthetic 23:00-26:00 service uses the previous service day for a 01:00 journey."
        case 32:
            result.outcome = "missing_data"
            var calendarFeed = try simpleFeed(feed)
            let weekday = (TripClock.calendar.component(.weekday, from: departure) + 5) % 7 + 1
            calendarFeed.services[0].weekdays = Array(1 ... 7).filter { $0 != weekday }
            try check(try await bus(calendarFeed, departure: departure) == nil, "Inactive weekday produced service")
            try check(calendarFeed.services[0].operates(on: departure.addingTimeInterval(86400)), "Following active weekday rejected")
            result.detail = "Weekly exclusion verified. Holiday exception absence is a data gap, not proof that holiday service runs."
        case 33, 34:
            result.outcome = "supported_conflict"
            let baseline = departure.addingTimeInterval(50 * 60 - 120 - 30)
            let original = try #require(try await bus(try simpleFeed(feed), departure: baseline))
            try audit(original)
            let delay = number == 33 ? 60.0 : 300.0
            try check(try await bus(try simpleFeed(feed), departure: baseline.addingTimeInterval(delay)) == nil, "Delayed last connection retained")
            result.detail = "A \(Int(delay / 60))-minute delay invalidates a previously available last synthetic boarding."
        case 35, 42, 43, 48, 60:
            try await itinerary(number, result: &result, now: now)
        case 36:
            result.outcome = "supported_conflict"
            let outbound = try #require(try await bus(try simpleFeed(feed), departure: departure))
            try audit(outbound)
            let returned = try await bus(try simpleFeed(feed), from: "P00017", to: "G00031", departure: outbound.arrival.addingTimeInterval(3600))
            try check(returned == nil, "Outbound success fabricated return service")
            result.detail = "Outbound is available; reverse pattern/service is absent after the visit."
        case 37:
            result.outcome = "supported_conflict"
            let fixture = try simpleFeed(feed)
            let board = try pin(fixture, "G00031"), end = try pin(fixture, "P00017")
            for metres in [799.0, 800.0, 801.0] {
                var origin = board; origin.id = "offset"
                var lower = board.latitude, upper = board.latitude + 0.02
                for _ in 0 ..< 60 {
                    origin.latitude = (lower + upper) / 2
                    if WeatherPolicy.distance(board, origin) <= metres { lower = origin.latitude } else { upper = origin.latitude }
                }
                origin.latitude = lower
                let planner = try BuswayPlanner(feed: fixture, walking: CapabilityWalking(), now: now)
                let journey = try await planner.bus(from: origin, to: end, departure: departure)
                try check((journey != nil) == (metres <= 800), "800m search boundary incorrect at \(metres)")
            }
            result.detail = "Actual nearby search accepts 799/800m and rejects 801m; distances constructed against the engine distance metric."
        case 38:
            result.outcome = "supported_conflict"
            for seconds in [1199.0, 1200.0, 1201.0] {
                let journey = try await bus(try simpleFeed(feed), departure: departure, walking: CapabilityWalking(seconds: seconds))
                try check((journey != nil) == (seconds <= 1200), "Walking boundary incorrect at \(seconds)")
                if let journey { try audit(journey) }
            }
            result.detail = "1199/1200 seconds per walking component accepted; 1201 rejected. This is not a total-trip walking cap."
        case 39:
            result.outcome = "supported_feasible"
            var fixture = try simpleFeed(feed)
            let origin = try pin(fixture, "G00031"), end = try pin(fixture, "P00017")
            for index in 1 ... 2 {
                var decoy = fixture.stops[0]; decoy.id = "decoy-\(index)"; decoy.latitude += Double(index) * 0.00001
                fixture.stops.append(decoy)
            }
            fixture.stops[0].latitude += 0.0001
            let limited = try BuswayPlanner(feed: fixture, walking: CapabilityWalking(), now: now)
            let recovered = try #require(try await limited.bus(from: origin, to: end, departure: departure))
            try audit(recovered)
            result.generatedJourney = true
            fixture.stops.removeAll { $0.id.hasPrefix("decoy-") }
            let exhaustive = try BuswayPlanner(feed: fixture, walking: CapabilityWalking(), now: now)
            try check(try await exhaustive.bus(from: origin, to: end, departure: departure) != nil, "Control route absent")
            result.detail = "Route-aware discovery reaches the third valid platform within 800m despite two closer unusable decoys; the no-decoy control also succeeds."
        case 40:
            result.outcome = "missing_data"
            let request = try BlokMReplay.request()
            let fields = try JSONSerialization.jsonObject(with: IntegrationJSON.encoder().encode(request)) as! [String: Any]
            try check(fields["wheelchairAccessible"] == nil && fields["maxWalkingSeconds"] == nil, "Structured access contract changed")
            result.detail = "Current request has no structured wheelchair/per-user walking constraint; GTFS coordinates cannot prove an accessible entrance."
        case 41:
            result.outcome = "unsupported_capability"
            var request = try BlokMReplay.request()
            request.desiredCount = 6
            request.requiredCandidateIDs = ["kota", "ragunan", "ancol", "palmerah", "manggarai", "lebak-bulus"]
            try check(rejected { try request.validate(catalog: IntegrationCatalog.load(blokM: true), now: now) }, "Uncatalogued citywide venues admitted")
            result.detail = "Six citywide destinations are rejected at catalog validation, before recommendation/routing. Existing six-stop Blok M regression remains separate."
        case 44:
            result.outcome = "supported_conflict"
            for count in [0, 7] {
                var request = try BlokMReplay.request(); request.desiredCount = count
                try check(rejected { try request.validate(catalog: IntegrationCatalog.load(blokM: true), now: now) }, "Invalid count admitted: \(count)")
            }
            result.detail = "Zero and seven requested destinations rejected explicitly."
        case 45:
            result.outcome = "provider_failure"
            let provider = MapKitBuswayWalking()
            provider.maximumAttempts = 1
            provider.requestTimeout = .milliseconds(5)
            provider.startRequest = { _, _ in } // No network: intentionally never complete the callback.
            let value = try await provider.walk(from: pin(feed, "G00031"), to: pin(feed, "P00017"), departure: departure)
            try check(value == nil && provider.failures.count == 1, "Missing callback did not terminate explicitly")
            let partial = CapabilityWalking(deniedDestination: "P00017")
            try check(try await bus(try simpleFeed(feed), departure: departure, walking: partial) == nil, "Partial access fabricated egress")
            result.walkingRequests = provider.requests + partial.requests
            result.detail = "Native callback timeout injected without network; separate partial walking fixture prevents egress."
        case 46:
            result.outcome = "supported_conflict"
            try check(rejected { _ = try BuswayPlanner(feed: feed, walking: CapabilityWalking(), now: now.addingTimeInterval(7 * 86400)) }, "Stale feed admitted")
            var geometry = try BuswayGeometryCatalog.load(); geometry.sourceSHA256 = String(repeating: "0", count: 64)
            try check(rejected { try geometry.validate(feed: feed) }, "Wrong geometry source admitted")
            result.detail = "Seven-day freshness boundary and geometry source-hash mismatch both rejected."
        case 47:
            result.outcome = "supported_conflict"
            let provider = MapKitBuswayWalking()
            provider.startRequest = { _, _ in provider.cancel() }
            do {
                _ = try await provider.walk(from: pin(feed, "G00031"), to: pin(feed, "P00017"), departure: departure)
                throw CapabilityFailure(description: "Cancelled walking completed a route")
            } catch is CancellationError { }
            let pipeline = try BlokMReplay.pipeline()
            var request = try BlokMReplay.request(); request.transport = .transjakartaBRT
            let review = try await pipeline.recommend(request, now: now)
            try check(review.request.effectiveTransport == .transjakartaBRT, "Fresh TJ request lost its mode")
            result.detail = "Cancellation terminates an in-flight native walking continuation; a fresh TJ request retains TJ mode. UI race regression is tracked separately, not claimed here."
        case 59:
            var fixture = try simpleFeed(feed)
            fixture.patterns[0].frequencies = [
                .init(start: 9 * 3600, end: 9 * 3600 + 300, headway: 600, exactTimes: 0),
                .init(start: 10 * 3600, end: 11 * 3600, headway: 600, exactTimes: 0),
            ]
            let journey = try #require(try await bus(fixture, departure: departure))
            try audit(journey)
            try check(journey.ride?.boardAt == day(feed).addingTimeInterval(10 * 3600 + 600), "Missed short window masked the later bus")
            result.outcome = "supported_feasible"; result.generatedJourney = true
            result.detail = "Synthetic short 09:00-09:05 window cannot fit a full headway; the next valid window boards at 10:10 and retains the long wait."
        case 61, 62:
            let providers = number == 61 ? [CapabilityWalking(seconds: .nan), CapabilityWalking(seconds: .infinity), CapabilityWalking(seconds: -1)] : [CapabilityWalking(mismatchedCoordinates: true)]
            for provider in providers {
                var rejected = false
                do { _ = try await bus(try simpleFeed(feed), departure: departure, walking: provider) }
                catch { rejected = true }
                try check(rejected, "Corrupt walking provider evidence was admitted")
            }
            result.outcome = "provider_failure"
            result.detail = number == 61 ? "NaN, infinity and negative walking durations are explicitly rejected; no fabricated TJ leg." : "Walking response with mismatched endpoint coordinates is rejected before calculating a bus journey."
        case 63:
            for frequency in [BuswayFrequency(start: 0, end: 3600, headway: 0, exactTimes: 0),
                              BuswayFrequency(start: 3600, end: 0, headway: 600, exactTimes: 0)] {
                var fixture = try simpleFeed(feed); fixture.patterns[0].frequencies = [frequency]
                try check(rejected { try fixture.validate() }, "Invalid service window/headway admitted")
            }
            result.outcome = "supported_conflict"
            result.detail = "Zero headway and reversed frequency window rejected without running a route."
        case 64:
            var journey = try #require(try await bus(try simpleFeed(feed), departure: departure))
            try audit(journey)
            journey.ride?.alightSequence = 1
            try check(rejected { try journey.validate() }, "Forged ordered bus proof admitted")
            result.outcome = "supported_conflict"
            result.detail = "A forged alighting occurrence before/equal to boarding cannot pass journey validation."
        default:
            throw CapabilityFailure(description: "Unimplemented scenario \(number)")
        }
        try check(!result.detail.isEmpty, "Missing evidence detail")
        return result
    }

    private func itinerary(_ number: Int, result: inout CapabilityObservation, now: Date) async throws {
        let pipeline = try BlokMReplay.pipeline()
        func run(_ input: TripRequest, base: UUID? = nil) async throws -> IntegratedPlan {
            let review = try await pipeline.recommend(input, now: now)
            let selected = input.requiredCandidateIDs.isEmpty ? review.suggestions.filter(\.recommended).map(\.id) : input.requiredCandidateIDs
            let prepared = try await pipeline.prepare(review, selectedIDs: selected, now: now)
            return try await pipeline.plan(prepared, review: review, baseAcceptedID: base, now: now)
        }
        var input = try BlokMReplay.request()
        input.transport = .transjakartaBRT
        input.requiredCandidateIDs = ["bm08"]; input.desiredCount = 1
        input.profile.prefer = [.coffee, .wifi]
        if number == 60 {
            input.profile.prefer = []
            input.requiredCandidateIDs = ["bm01", "bm02", "bm03", "bm05", "bm08", "bm13"]
            input.desiredCount = 6
            input.deadline = TripClock.calendar.startOfDay(for: input.departure).addingTimeInterval(23 * 3600 + 45 * 60)
            input.durationByVenue = Dictionary(uniqueKeysWithValues: zip(input.requiredCandidateIDs, [15, 30, 45, 60, 75, 90]))
            let scaled = try await run(input)
            try check(scaled.feasible, "Six varied-duration TJ visits became infeasible")
            try PlanAudit.validate(scaled)
            try check(Set(scaled.stops.map(\.id)) == Set(input.requiredCandidateIDs), "Scale test dropped a selected venue")
            try check(scaled.stops.allSatisfy { $0.duration == input.duration($0.id) }, "Visit duration changed")
            try check(scaled.legs.contains { $0.busway?.ride != nil }, "Scale test has no bus ride")
            result.outcome = "supported_feasible"; result.generatedJourney = true
            result.measurements = ["venues": 6, "visitMinutes": 315]
            result.detail = "Complete TJ replay preserves six selected Blok M venues and distinct 15/30/45/60/75/90-minute stays. This is a catalog-limited itinerary control, not a citywide network route."
            return
        }
        let accepted = try await run(input)
        try check(accepted.feasible, "Baseline itinerary infeasible")
        try PlanAudit.validate(accepted)
        result.generatedJourney = true
        if number == 43 {
            result.outcome = "supported_feasible"
            input.requiredCandidateIDs = []
            let busReview = try await pipeline.recommend(input, now: now)
            try check(busReview.suggestions.filter(\.recommended).map(\.id) == ["bm08"], "TJ changed sourced recommendation")
            try check(accepted.request.profile == input.profile && accepted.stops.map(\.id) == ["bm08"], "Preferences or mandatory stop lost")
            result.detail = "TJ recommends sourced coffee/Wi-Fi bm08; complete TJ plan preserves profile and venue. Synthetic Blok M end-to-end control."
            return
        }
        if number == 42 {
            result.outcome = "supported_conflict"
            input.deadline = input.departure.addingTimeInterval(3600)
            let conflict = try await run(input)
            try check(!conflict.feasible && conflict.request.requiredCandidateIDs == ["bm08"], "Mandatory deadline conflict hidden")
            var session = IntegrationSession(); session.proposal = conflict
            try check(rejected { try session.apply(now: now) }, "Infeasible proposal accepted")
            result.detail = "Mandatory venue retained in the request; impossible deadline yields an unacceptably infeasible proposal."
            return
        }
        input.id = UUID(); input.revision += 1
        input.deadline = try #require(accepted.finish).addingTimeInterval(1)
        input.durationByVenue["bm08"] = 90
        let revised = try await run(input, base: accepted.id)
        try check(!revised.feasible, "Thirty-minute extension unexpectedly fits the original finish deadline")
        var session = IntegrationSession(); session.accepted = accepted; session.proposal = revised
        try check(rejected { try session.apply(now: now) }, "Conflicting revision accepted")
        if number == 35 {
            result.outcome = "supported_conflict"
            result.detail = "+30-minute visit exceeds the baseline finish deadline; acceptance is rejected."
            return
        }
        result.outcome = "supported_feasible"
        session.proposal = nil
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TJCapability-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TripStore(directory: folder)
        try await store.save(session)
        let restored = try await store.load().session
        try check(restored.accepted?.id == accepted.id && restored.proposal == nil, "Rejected proposal changed accepted identity")
        let decoded = try #require(restored.accepted)
        try PlanAudit.validate(decoded)
        let exported = try await store.export(decoded)
        let text = try String(contentsOf: exported.appendingPathComponent("REPORT.md"), encoding: .utf8)
        try check(text.contains("CC BY 4.0") && text.contains("Koridor 1"), "Export lost source proof")
        result.detail = "Save/reopen/export preserves accepted UUID and audited bus proof after a conflicting revision is rejected."
    }

    @Test func thousandDepartureAccessAndWalkingVariations() async throws {
        let feed = try BuswayFeed.load()
        let pairs = [("G00061", "G00031"), ("G00058", "G00030"), ("G00054", "G00021"),
                     ("G00052", "G00036"), ("G00051", "G00040"), ("G00034", "G00061"),
                     ("G00038", "G00058"), ("G00039", "G00054"), ("G00753", "G00060"), ("G00036", "G00030")]
        let hours = [0, 1, 5, 6, 8, 9, 12, 17, 22, 23]
        var rows: [SweepObservation] = []
        for pair in pairs {
            for hour in hours {
                for delay in [0, 1, 5, 15, 30] {
                    for seconds in [120.0, 1201.0] {
                        let departure = day(feed).addingTimeInterval(Double(hour * 3600))
                        let walking = CapabilityWalking(seconds: seconds, accessDelay: Double(delay * 60),
                                                        accessOrigin: pair.0, allowed: Set([pair.0, pair.1]))
                        let began = Date()
                        var row = SweepObservation(id: String(format: "S%04d", rows.count + 1), from: pair.0, to: pair.1,
                                                   departure: departure, accessDelayMinutes: delay, walkingComponentSeconds: seconds,
                                                   outcome: "supported_conflict", walkingRequests: 0, elapsedMilliseconds: 0,
                                                   detail: "No feasible directed ride within the configured access/service limits.")
                        do {
                            let journey = try await bus(feed, from: pair.0, to: pair.1, departure: departure, walking: walking)
                            if let journey {
                                try audit(journey)
                                let ride = try #require(journey.ride)
                                try check(seconds <= 1200 && seconds + Double(delay * 60) <= 1200, "Over-limit walking admitted")
                                try check(ride.board.id == pair.0 && ride.alight.id == pair.1, "Endpoint identity changed")
                                row.outcome = "supported_feasible"; row.totalSeconds = journey.seconds
                                row.patternID = ride.patternID; row.boardID = ride.board.id; row.alightID = ride.alight.id
                                row.detail = "Ordered GTFS ride with synthetic walking; independent arithmetic/time/identity invariants passed."
                            } else if seconds <= 1200 && seconds + Double(delay * 60) <= 1200 {
                                // An independently bounded exact-platform scan distinguishes search loss from true service conflict.
                                let ready = departure.addingTimeInterval(seconds + Double(delay * 60))
                                let possible = exactPlatformServiceExists(feed, from: pair.0, to: pair.1, ready: ready, departure: departure)
                                try check(!possible, "Engine missed an exact-platform service within its supported bounds")
                            }
                        } catch {
                            row.outcome = "defect"; row.detail = String(describing: error)
                        }
                        row.walkingRequests = walking.requests
                        row.elapsedMilliseconds = Date().timeIntervalSince(began) * 1000
                        rows.append(row)
                    }
                }
            }
        }
        try write(rows, name: "sweep.json")
        #expect(rows.count == 1000)
        let defects = rows.filter { $0.outcome == "defect" }
        #expect(defects.isEmpty, "\(defects.prefix(5).map(\.detail))")
        #expect(rows.contains { $0.outcome == "supported_feasible" })
        #expect(rows.contains { $0.outcome == "supported_conflict" })
    }

    private func exactPlatformServiceExists(_ feed: BuswayFeed, from: String, to: String, ready: Date, departure: Date) -> Bool {
        let midnight = TripClock.calendar.startOfDay(for: departure)
        for serviceDay in [midnight.addingTimeInterval(-86400), midnight] {
            for pattern in feed.patterns {
                guard feed.services.contains(where: { $0.id == pattern.serviceID && $0.operates(on: serviceDay) }) else { continue }
                for board in pattern.calls where board.stopID == from {
                    guard pattern.calls.contains(where: { $0.stopID == to && $0.sequence > board.sequence && $0.arrivalOffset > board.departureOffset }) else { continue }
                    for frequency in pattern.frequencies {
                        let latestReady = serviceDay.addingTimeInterval(Double(frequency.end + board.departureOffset - frequency.headway))
                        let startFits = frequency.start + frequency.headway < frequency.end
                        if startFits && ready < latestReady { return true }
                    }
                }
            }
        }
        return false
    }
}

@MainActor private final class CapabilityWalking: BuswayWalking {
    var requests = 0
    let synthetic = true
    var failures: [String] = []
    let seconds: Double
    let accessDelay: Double
    let accessOrigin: String?
    let allowed: Set<String>?
    let unavailable: Bool
    let cancelled: Bool
    let deniedDestination: String?
    let mismatchedCoordinates: Bool

    init(seconds: Double = 120, accessDelay: Double = 0, accessOrigin: String? = nil,
         allowed: Set<String>? = nil, unavailable: Bool = false, cancelled: Bool = false, deniedDestination: String? = nil, mismatchedCoordinates: Bool = false) {
        self.seconds = seconds; self.accessDelay = accessDelay; self.accessOrigin = accessOrigin
        self.allowed = allowed; self.unavailable = unavailable; self.cancelled = cancelled
        self.deniedDestination = deniedDestination
        self.mismatchedCoordinates = mismatchedCoordinates
    }

    func cancel() {}
    func walk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayWalk? {
        requests += 1
        if cancelled { throw CancellationError() }
        if unavailable || to.id == deniedDestination { return nil }
        if let allowed, !allowed.contains(from.id) || !allowed.contains(to.id) { return nil }
        var returnedTo = to
        if mismatchedCoordinates { returnedTo.latitude += 0.01 }
        return .init(from: from, to: returnedTo, seconds: seconds + (from.id == accessOrigin ? accessDelay : 0),
                     distanceMeters: WeatherPolicy.distance(from, to), provider: "synthetic_walking")
    }
}
