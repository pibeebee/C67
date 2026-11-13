import Foundation
import MapKit
import Testing
@testable import TripIntegration

@Suite("TransJakarta GTFS itinerary", .serialized)
@MainActor struct BuswayTests {
    func context() throws -> (BuswayFeed, Date, Date) {
        let feed = try BuswayFeed.load()
        let now = feed.source.checkedAt.addingTimeInterval(1)
        let tomorrow = TripClock.calendar.date(byAdding: .day, value: 1, to: now)!
        let departure = TripClock.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        return (feed, now, departure)
    }
    func restricted(_ feed: BuswayFeed, patternID: String) -> BuswayFeed {
        var value = feed
        value.patterns = feed.patterns.filter { $0.id == patternID }
        return value
    }
    func pin(_ feed: BuswayFeed, _ id: String) -> PlacePin { feed.stops.first { $0.id == id }!.pin }

    @Test func importedFeedPreservesPatternsPlatformsAndOffsets() throws {
        let (feed, now, _) = try context()
        try feed.validate(); try feed.requireFresh(at: now)
        #expect(feed.stops.count == 59)
        #expect(feed.patterns.count == 18)
        #expect(feed.patterns.allSatisfy { $0.calls.first?.departureOffset == 0 })
        #expect(feed.patterns.allSatisfy { $0.frequencies.allSatisfy { $0.exactTimes == 0 } })
        let loop = try #require(feed.patterns.first { $0.id == "1-P28" })
        #expect(loop.calls.filter { $0.stopID == "P00017" }.count == 2)
        var invalid = feed; invalid.patterns[0].calls[1].sequence = invalid.patterns[0].calls[0].sequence
        #expect(throws: (any Error).self) { try invalid.validate() }
        invalid = feed; invalid.patterns[0].frequencies[0].exactTimes = 1
        #expect(throws: (any Error).self) { try invalid.validate() }
    }

    @Test func fullHeadwayAndDirectionalPlatformOffsetsAreApplied() async throws {
        let (feed, now, departure) = try context()
        let planner = try BuswayPlanner(feed: restricted(feed, patternID: "1-P97"), walking: FixedBuswayWalking(allowedStops: ["G00031", "P00017"]), now: now)
        let journey = try #require(try await planner.bus(from: pin(feed, "G00031"), to: pin(feed, "P00017"), departure: departure))
        let ride = try #require(journey.ride)
        #expect(ride.board.id == "G00031")
        #expect(ride.alight.id == "P00017")
        #expect(ride.boardSequence == 3 && ride.alightSequence == 13)
        #expect(journey.waitingSeconds == 1200)
        #expect(journey.ridingSeconds == 2596 - 563)
        #expect(journey.walkingSeconds == 240)
        #expect(journey.seconds == 240 + 1200 + 2033)
        try journey.validate()
        let reverse = try await planner.bus(from: pin(feed, "P00017"), to: pin(feed, "G00031"), departure: departure)
        #expect(reverse == nil)
    }

    @Test func loopUsesOrderedOccurrencesAndCanReturnSouthbound() async throws {
        let (feed, now, departure) = try context()
        let planner = try BuswayPlanner(feed: restricted(feed, patternID: "1-P28"), walking: FixedBuswayWalking(allowedStops: ["G00031", "P00017"]), now: now)
        let journey = try #require(try await planner.bus(from: pin(feed, "G00031"), to: pin(feed, "P00017"), departure: departure))
        #expect(journey.ride?.boardSequence == 17)
        #expect(journey.ride?.alightSequence == 27)
        #expect(journey.waitingSeconds == 900)
    }

    @Test func frequencyEndIsExclusiveAndBeforeOpeningIncludesServiceWait() async throws {
        let (feed, now, departure) = try context()
        var value = restricted(feed, patternID: "1-P96")
        value.patterns[0].frequencies = [.init(start: 10 * 3600, end: 11 * 3600, headway: 1200, exactTimes: 0)]
        let planner = try BuswayPlanner(feed: value, walking: FixedBuswayWalking(), now: now)
        let early = try #require(try await planner.bus(from: pin(feed, "P00017"), to: pin(feed, "G00034"), departure: departure))
        #expect(early.ride?.boardAt == departure.addingTimeInterval(4800))
        #expect(early.waitingSeconds == 4680)
        let late = try await planner.bus(from: pin(feed, "P00017"), to: pin(feed, "G00034"), departure: departure.addingTimeInterval(2 * 3600))
        #expect(late == nil)
    }

    @Test func previousServiceDaySupportsAfterMidnightFrequency() async throws {
        let (feed, now, departure) = try context()
        var value = restricted(feed, patternID: "1-P96")
        value.patterns[0].frequencies = [.init(start: 23 * 3600, end: 26 * 3600, headway: 600, exactTimes: 0)]
        let planner = try BuswayPlanner(feed: value, walking: FixedBuswayWalking(), now: now)
        let midnight = TripClock.calendar.startOfDay(for: departure)
        let trip = try #require(try await planner.bus(from: pin(feed, "P00017"), to: pin(feed, "G00034"), departure: midnight.addingTimeInterval(3600)))
        #expect(trip.ride?.serviceDay == midnight.addingTimeInterval(-86400))
        #expect(trip.waitingSeconds == 600)
    }

    @Test func staleFeedInactiveCalendarMissingPlatformsAndUnavailableWalkAreExplicit() async throws {
        let (feed, now, departure) = try context()
        #expect(throws: (any Error).self) { try BuswayPlanner(feed: feed, walking: FixedBuswayWalking(), now: now.addingTimeInterval(8 * 86400)) }
        var value = feed
        value.services = value.services.map { service in var s = service; s.endDate = "20260101"; s.startDate = "20250101"; return s }
        let inactive = try BuswayPlanner(feed: value, walking: FixedBuswayWalking(), now: now)
        #expect(try await inactive.bus(from: pin(feed, "P00017"), to: pin(feed, "G00034"), departure: departure) == nil)
        let failed = try BuswayPlanner(feed: feed, walking: FixedBuswayWalking(unavailable: true), now: now)
        #expect(try await failed.bus(from: pin(feed, "P00017"), to: pin(feed, "G00034"), departure: departure) == nil)
        let outside = PlacePin(id: "outside", name: "outside", address: "Jakarta", latitude: -6.3, longitude: 106.9)
        #expect(try await inactive.bus(from: outside, to: pin(feed, "G00034"), departure: departure) == nil)
    }

    @Test func walkingLimitAndCancellationPropagate() async throws {
        let (feed, now, departure) = try context()
        let planner = try BuswayPlanner(feed: feed, walking: FixedBuswayWalking(seconds: 1201), now: now)
        #expect(try await planner.directWalk(from: pin(feed, "G00031"), to: pin(feed, "G00034"), departure: departure) == nil)
        #expect(try await planner.bus(from: pin(feed, "P00017"), to: pin(feed, "G00034"), departure: departure) == nil)
        let cancelled = try BuswayPlanner(feed: feed, walking: FixedBuswayWalking(cancelled: true), now: now)
        await #expect(throws: CancellationError.self) { try await cancelled.bus(from: pin(feed, "P00017"), to: pin(feed, "G00034"), departure: departure) }
    }

    @Test func buswayReplayScalesPreservesProofAndSurvivesStorage() async throws {
        let (_, now, _) = try context()
        for ids in [["bm01"], ["bm01", "bm04", "bm08"], ["bm01", "bm02", "bm03", "bm05", "bm08", "bm13"]] {
            let pipeline = try BlokMReplay.pipeline()
            var input = BlokMExperiment.request(now: now)
            input.transport = .transjakartaBRT; input.requiredCandidateIDs = ids; input.desiredCount = ids.count
            let review = try await pipeline.recommend(input, now: now)
            let prepared = try await pipeline.prepare(review, selectedIDs: ids, now: now)
            let result = try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: now)
            #expect(result.feasible)
            #expect(result.evidenceMode == "synthetic_replay")
            #expect(Set(result.stops.map(\.id)) == Set(ids))
            #expect(result.legs.allSatisfy { $0.busway != nil })
            #expect(result.legs.contains { $0.busway?.ride != nil })
            if ids.count > 1 { #expect(result.legs.contains { $0.mode == "walking" }) }
            let decoded = try IntegrationJSON.decoder().decode(IntegratedPlan.self, from: IntegrationJSON.encoder().encode(result))
            try PlanAudit.validate(decoded)
            var session = IntegrationSession(); session.proposal = result; try session.apply(now: now)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TJTests-\(UUID())")
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = TripStore(directory: folder); try await store.save(session)
            #expect(try await store.load().session.accepted?.id == result.id)
            let export = try await store.export(result)
            let markdown = try String(contentsOf: export.appendingPathComponent("REPORT.md"), encoding: .utf8)
            #expect(markdown.contains("CC BY 4.0"))
            #expect(markdown.contains("Koridor 1"))
            var tampered = result; tampered.legs[0].busway = nil
            #expect(throws: (any Error).self) { try PlanAudit.validate(tampered) }
            tampered = result; tampered.legs[0].busway?.ride?.directionID = "forged"
            #expect(throws: (any Error).self) { try PlanAudit.validate(tampered) }
            tampered = result; tampered.legs[0].busway?.ride?.boardAt.addTimeInterval(60)
            #expect(throws: (any Error).self) { try PlanAudit.validate(tampered) }
        }
    }

    @Test func personalizedCoffeeWifiChoiceSurvivesBuswayPlanning() async throws {
        let (_, now, _) = try context()
        let pipeline = try BlokMReplay.pipeline()
        var input = BlokMExperiment.request(now: now)
        input.desiredCount = 1
        input.profile.prefer = [.coffee, .wifi]
        let carReview = try await pipeline.recommend(input, now: now)
        input.transport = .transjakartaBRT
        let review = try await pipeline.recommend(input, now: now)
        let ids = review.suggestions.filter(\.recommended).map(\.id)
        #expect(ids == ["bm08"])
        #expect(ids == carReview.suggestions.filter(\.recommended).map(\.id))
        let prepared = try await pipeline.prepare(review, selectedIDs: ids, now: now)
        let plan = try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: now)
        #expect(plan.feasible)
        #expect(plan.request.profile == input.profile)
        #expect(plan.stops.map(\.id) == ids)
        #expect(plan.legs.contains { $0.busway?.ride != nil })
    }

    @Test func buswayRevisionAndImpossibleDeadlineUseExistingAcceptanceFlow() async throws {
        let (_, now, _) = try context()
        let pipeline = try BlokMReplay.pipeline()
        func run(_ input: TripRequest, base: UUID? = nil) async throws -> IntegratedPlan {
            let review = try await pipeline.recommend(input, now: now)
            let prepared = try await pipeline.prepare(review, selectedIDs: input.requiredCandidateIDs, now: now)
            return try await pipeline.plan(prepared, review: review, baseAcceptedID: base, now: now)
        }
        var input = BlokMExperiment.request(now: now)
        input.transport = .transjakartaBRT; input.requiredCandidateIDs = ["bm01", "bm04", "bm08"]
        let base = try await run(input)
        input.revision += 1; input.id = UUID(); input.durationByVenue["bm01"] = input.duration("bm01") + 30
        let revised = try await run(input, base: base.id)
        #expect(revised.feasible)
        #expect(revised.stops.first { $0.id == "bm01" }?.duration == 90)
        #expect(revised.finish! > base.finish!)
        var session = IntegrationSession(); session.accepted = base; session.proposal = revised
        try session.apply(now: now); #expect(session.accepted?.id == revised.id)
        input.durationByVenue = [:]; input.requiredCandidateIDs = ["bm01"]; input.deadline = input.departure.addingTimeInterval(3600)
        let impossible = try await run(input)
        #expect(!impossible.feasible)
        session = IntegrationSession(); session.proposal = impossible
        #expect(throws: (any Error).self) { try session.apply(now: now) }
    }

    @Test func missingMapKitCallbackTimesOutAndLateCallbackCannotCompleteNextRequest() async throws {
        let (feed, _, departure) = try context()
        let provider = MapKitBuswayWalking()
        provider.maximumAttempts = 1
        provider.requestTimeout = .milliseconds(10)
        var late: (@Sendable (MKDirections.ETAResponse?, (any Error)?) -> Void)?
        provider.startRequest = { _, callback in late = callback }
        let value = try await provider.walk(from: pin(feed, "P00017"), to: pin(feed, "G00034"), departure: departure)
        #expect(value == nil)
        #expect(provider.failures.count == 1)
        let prior = late
        provider.requestTimeout = .seconds(10)
        provider.startRequest = { _, _ in
            prior?(nil, URLError(.badServerResponse))
            provider.cancel()
        }
        await #expect(throws: CancellationError.self) {
            try await provider.walk(from: pin(feed, "G00034"), to: pin(feed, "P00017"), departure: departure)
        }
        #expect(provider.failures.count == 1)
    }

    @Test func taskCancellationCompletesEvenWithoutMapKitCallback() async throws {
        let (feed, _, departure) = try context()
        let provider = MapKitBuswayWalking()
        provider.startRequest = { _, _ in }
        let task = Task { try await provider.walk(from: pin(feed, "P00017"), to: pin(feed, "G00034"), departure: departure) }
        while provider.requests == 0 { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(provider.failures.isEmpty)
    }

    @Test func legacyRequestsDecodeWithCarDefault() throws {
        let (_, now, _) = try context()
        let input = BlokMExperiment.request(now: now)
        let bytes = try IntegrationJSON.encoder().encode(input)
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(object["transport"] == nil)
        let decoded = try IntegrationJSON.decoder().decode(TripRequest.self, from: bytes)
        #expect(decoded.effectiveTransport == .automobile)
        let eta = NativeTripETA(id: "old", mode: .automobile, seconds: 60, status: "available", note: "legacy")
        #expect(try IntegrationJSON.decoder().decode(NativeTripETA.self, from: IntegrationJSON.encoder().encode(eta)).busway == nil)
    }
}

@MainActor private final class FixedBuswayWalking: BuswayWalking {
    var requests = 0
    let synthetic = true
    let failures: [String] = []
    let seconds: Double
    let unavailable: Bool
    let cancelled: Bool
    let allowedStops: Set<String>?
    init(seconds: Double = 120, unavailable: Bool = false, cancelled: Bool = false, allowedStops: Set<String>? = nil) {
        self.allowedStops = allowedStops
        self.seconds = seconds; self.unavailable = unavailable; self.cancelled = cancelled
    }
    func cancel() {}
    func walk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayWalk? {
        requests += 1
        if cancelled { throw CancellationError() }
        if unavailable { return nil }
        if let allowedStops, [from, to].contains(where: { $0.source == "Published TransJakarta GTFS boarding coordinate" && !allowedStops.contains($0.id) }) { return nil }
        return .init(from: from, to: to, seconds: seconds, distanceMeters: seconds, provider: "synthetic_walking")
    }
}
