import Foundation
import Testing

@testable import VisitTiming

/// All mutations in this file are engineering fault injections, not new venue/weather facts.
/// The untouched catalog and acquired forecast retain their original source dates.
struct ExtremeFixture {
    var catalog = try! TimingCatalog.load()
    var acquired: TimingEnvironment
    var now: Date
    init() throws {
        let url = Bundle.module.url(
            forResource: "gbk-actual-2026-11-05", withExtension: "json",
            subdirectory: "Fixtures")!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(TimingRun.self, from: Data(contentsOf: url))
        acquired = try #require(run.environment)
        now = acquired.fetchedAt.addingTimeInterval(1)
    }
    func evaluate(_ request: TimingRequest? = nil, weather: TimingEnvironment? = nil) throws
        -> TimingRun
    {
        try VisitTimingEngine().evaluate(
            request
                ?? .init(
                    venueID: "gbk", date: "2026-11-05", available: .init(900, 1080),
                    goal: .lowerRain),
            catalog: catalog, environment: weather ?? acquired, now: now)
    }
    func encoded(_ value: TimingRun) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(value)
    }
    var gbkIndex: Int { catalog.venues.firstIndex { $0.id == "gbk" }! }
}

struct ExtremeDateAndSourceTests {
    @Test(arguments: [
        "2026--11-5", "2026-11-+5", "2026-1-005", "2026-11-05\n",
        "２０２６-１１-０５", "2026-02-29", "2026-04-31", "2026-00-05",
    ])
    func nonCanonicalOrImpossibleDatesRejected(_ text: String) {
        #expect(throws: (any Error).self) { try VenueClock.day(text) }
    }
    @Test func alternateDateCannotBypassPastTimeGuard() throws {
        var f = try ExtremeFixture()
        f.now = try VenueClock.day("2026-11-05").addingTimeInterval(20 * 3600)
        #expect(throws: (any Error).self) {
            try f.evaluate(.init(venueID: "gbk", date: "2026-11-+5", available: .init(360, 1080)))
        }
    }
    @Test(arguments: [Int.min, -15, 0, 1, 14, 16, 359, 361, Int.max])
    func malformedDurationsRejectedWithoutOverflow(_ duration: Int) throws {
        let f = try ExtremeFixture()
        #expect(throws: (any Error).self) {
            try f.evaluate(.init(venueID: "gbk", date: "2026-11-06", durationMinutes: duration))
        }
    }
    @Test(arguments: [
        MinuteRange(-1, 900), .init(Int.min, 1440), .init(0, Int.max),
        .init(900, 900), .init(901, 900), .init(0, 1441),
    ])
    func malformedAvailabilityRejected(_ range: MinuteRange) throws {
        let f = try ExtremeFixture()
        #expect(throws: (any Error).self) {
            try f.evaluate(.init(venueID: "gbk", date: "2026-11-06", available: range))
        }
    }
    @Test func oneMillisecondAfterStartCannotOfferPastSlot() throws {
        var f = try ExtremeFixture()
        let nine = try VenueClock.day("2026-11-05").addingTimeInterval(9 * 3600)
        let request = TimingRequest(
            venueID: "gbk", date: "2026-11-05",
            available: .init(540, 600), durationMinutes: 15)
        f.now = nine
        #expect(try f.evaluate(request).options.first?.start == nine)
        f.now = nine.addingTimeInterval(0.001)
        #expect(try f.evaluate(request).options.first?.start == nine.addingTimeInterval(900))
    }
    @Test(arguments: [
        "unlinked-exposure", "missing-exposure", "unlinked-notice",
        "empty-notice", "closed-with-admission", "empty-id", "invalid-url", "unknown-exposure",
        "foreign-time-zone",
    ])
    func invalidProvenanceAndContradictoryRulesRejected(_ kind: String) throws {
        var f = try ExtremeFixture()
        switch kind {
        case "unlinked-exposure": f.catalog.venues[f.gbkIndex].exposureSourceID = "macan"
        case "missing-exposure": f.catalog.venues[f.gbkIndex].exposureSourceID = nil
        case "unlinked-notice":
            f.catalog.venues[f.gbkIndex].suspended = true
            f.catalog.venues[f.gbkIndex].notice = "FAULT INJECTION"
            f.catalog.venues[f.gbkIndex].noticeSourceID = "macan"
        case "empty-notice":
            f.catalog.venues[f.gbkIndex].suspended = true
            f.catalog.venues[f.gbkIndex].noticeSourceID = "gbk"
            f.catalog.venues[f.gbkIndex].notice = " "
        case "closed-with-admission": f.catalog.venues[f.gbkIndex].schedule[0].lastEntry = 600
        case "empty-id": f.catalog.sources[0].id = " "
        case "invalid-url": f.catalog.sources[0].url = URL(string: "https:relative-path")!
        case "foreign-time-zone": f.catalog.venues[f.gbkIndex].timeZone = "Asia/Tokyo"
        default: f.catalog.venues[f.gbkIndex].exposure = "invented"
        }
        #expect(throws: (any Error).self) { try f.catalog.validate() }
    }
    @Test func sourceExpiryBoundaryIsExact() throws {
        var f = try ExtremeFixture()
        let source = try #require(f.catalog.sources.first { $0.id == "gbk" })
        f.now = source.checkedAt.addingTimeInterval(7 * 86400)
        let request = TimingRequest(venueID: "gbk", date: "2026-11-12")
        #expect(try f.evaluate(request).status == "regular_hours_options")
        f.now = f.now.addingTimeInterval(0.001)
        #expect(try f.evaluate(request).status == "needs_recheck")
    }
    @Test func sessionOrderCannotChangeAllowedStartRanges() throws {
        var f = try ExtremeFixture()
        let request = TimingRequest(venueID: "gbk", date: "2026-11-06", available: .init(360, 1080))
        let expected = try f.evaluate(request)
        for i in f.catalog.venues[f.gbkIndex].schedule.indices {
            f.catalog.venues[f.gbkIndex].schedule[i].sessions.reverse()
        }
        let actual = try f.evaluate(request)
        #expect(actual.validStartRanges == expected.validStartRanges)
        #expect(actual.options.map(\.start) == expected.options.map(\.start))
    }
}

struct ExtremeForecastTests {
    @Test(arguments: ["duplicate", "overlap"])
    func ambiguousHourlyIntervalsDoNotProduceRainRanking(_ kind: String) throws {
        let f = try ExtremeFixture()
        var weather = f.acquired
        var duplicate = try #require(weather.hours.first { VenueClock.label($0.start) == "15.00" })
        duplicate.rainChance = 0
        if kind == "overlap" { duplicate.start = duplicate.start.addingTimeInterval(1800) }
        weather.hours.append(duplicate)
        let run = try f.evaluate(weather: weather)
        #expect(run.status == "context_unavailable")
        #expect(run.options.isEmpty)
    }
    @Test func lowerRainIsOrderedBeforeEarlierTimeEvenForTinyDifferences() throws {
        let f = try ExtremeFixture()
        var weather = f.acquired
        for i in weather.hours.indices {
            weather.hours[i].rainChance =
                VenueClock.label(weather.hours[i].start) == "15.00" ? 0.2501 : 0.25
        }
        let run = try f.evaluate(weather: weather)
        #expect(run.options.first?.maxRainChance == 0.25)
        #expect(run.options.map { $0.maxRainChance! } == run.options.map { $0.maxRainChance! }.sorted())
    }
    @Test(arguments: [(0.0, 0.0), (91.0, 106.8), (-6.2, 181.0), (-6.2, -73.0)])
    func coordinatesOutsideJakartaAreRejected(_ coordinate: (Double, Double)) throws {
        let f = try ExtremeFixture()
        var weather = f.acquired
        weather.latitude = coordinate.0
        weather.longitude = coordinate.1
        let run = try f.evaluate(weather: weather)
        #expect(run.environment == nil)
        #expect(run.status == "context_unavailable")
    }
    @Test func contradictoryForecastChronologyIsRejected() throws {
        let f = try ExtremeFixture()
        var weather = f.acquired
        weather.fetchedAt = f.now.addingTimeInterval(60)
        weather.validUntil = f.now.addingTimeInterval(30)
        #expect(try f.evaluate(weather: weather).environment == nil)
    }
    @Test func expiryIsExclusiveAndApplicationLifetimeIsCapped() throws {
        var f = try ExtremeFixture()
        var weather = f.acquired
        f.now = weather.validUntil
        #expect(try f.evaluate(weather: weather).status == "context_unavailable")
        f.now = weather.fetchedAt.addingTimeInterval(1)
        weather.validUntil = weather.fetchedAt.addingTimeInterval(86400)
        let value = try #require(f.evaluate(weather: weather).environment)
        #expect(value.validUntil <= value.fetchedAt.addingTimeInterval(900))
    }
    @Test func solarContradictionDoesNotEraseIndependentHourlyRain() throws {
        let f = try ExtremeFixture()
        var weather = f.acquired
        weather.sunrise = weather.sunset!.addingTimeInterval(3600)
        let solar = try f.evaluate(
            .init(
                venueID: "gbk", date: "2026-11-05",
                available: .init(900, 1080), goal: .nearSunset), weather: weather)
        #expect(solar.status == "context_unavailable")
        #expect(try f.evaluate(weather: weather).status == "context_ranked")
    }
    @Test func nonFiniteMeasurementsRemainSerializableAndUnknown() throws {
        let f = try ExtremeFixture()
        var weather = f.acquired
        for i in weather.hours.indices { weather.hours[i].temperatureC = .nan }
        weather.sunrise = Date(timeIntervalSince1970: .infinity)
        let run = try f.evaluate(weather: weather)
        #expect(run.status == "context_ranked")
        #expect(run.options.allSatisfy { $0.maxTemperatureC == nil })
        #expect(throws: Never.self) { try f.encoded(run) }
    }
    @Test func staleWeatherIsRemovedEvenWhenVenueReturnsEarly() throws {
        let f = try ExtremeFixture()
        for venue in ["macan", "koja", "ragunan"] {
            var weather = f.acquired
            weather.venueID = venue
            weather.validUntil = f.now.addingTimeInterval(-1)
            let run = try f.evaluate(
                .init(
                    venueID: venue,
                    date: venue == "ragunan" ? "2026-11-09" : "2026-11-08"), weather: weather)
            #expect(run.options.isEmpty)
            #expect(
                run.environment == nil,
                "Invalid weather must not appear as current context on early returns.")
        }
    }
    @Test func permutationOfUnambiguousHoursPreservesResults() throws {
        let f = try ExtremeFixture()
        var weather = f.acquired
        let original = try f.evaluate()
        weather.hours.reverse()
        let reversed = try f.evaluate(weather: weather)
        #expect(original.options.map(\.start) == reversed.options.map(\.start))
        #expect(original.options.map(\.maxRainChance) == reversed.options.map(\.maxRainChance))
    }
}

struct ExtremeStorageTests {
    @Test(arguments: ["schema", "policy", "reference", "option", "identity"])
    func syntacticallyValidButCorruptHistoryIsNotTrusted(_ kind: String) async throws {
        let f = try ExtremeFixture()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = TimingStore(directory: path)
        let valid = try f.evaluate()
        try await store.save(valid)
        var bad = try f.evaluate()
        bad.id = UUID()
        switch kind {
        case "schema": bad.schemaVersion = 999
        case "policy": bad.policyVersion = "unknown-future-policy"
        case "reference": bad.venue.sourceIDs = ["invented"]
        case "option": bad.options[0].end = bad.options[0].start.addingTimeInterval(-1)
        default: bad.request.venueID = "different-venue"
        }
        let file = path.appendingPathComponent("\(bad.id).json")
        try f.encoded(bad).write(to: file)
        let result = try await store.history()
        #expect(result.runs.count == 1 && result.unreadable == 1)
        #expect(result.runs.first?.id == valid.id)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
    @Test func identityCollisionCannotOverwriteEarlierExperiment() async throws {
        let f = try ExtremeFixture()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = TimingStore(directory: path)
        let valid = try f.evaluate()
        try await store.save(valid)
        let file = path.appendingPathComponent("\(valid.id).json")
        let before = try Data(contentsOf: file)
        try await store.save(valid)  // Exact repeat must be idempotent.
        var changed = valid
        changed.warnings.append("FAULT INJECTION: different result, same run ID")
        await #expect(throws: (any Error).self) { try await store.save(changed) }
        #expect(try Data(contentsOf: file) == before)
    }
    @Test func twoHundredConcurrentSavesAndReadsLoseNoRuns() async throws {
        let f = try ExtremeFixture()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = TimingStore(directory: path)
        let base = try f.evaluate()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< 200 {
                var run = base
                run.id = UUID()
                run.warnings.append("FAULT INJECTION: concurrency sample \(i)")
                group.addTask { try await store.save(run) }
                if i % 10 == 0 { group.addTask { _ = try await store.history() } }
            }
            try await group.waitForAll()
        }
        let history = try await store.history()
        #expect(history.runs.count == 200)
        #expect(Set(history.runs.map(\.id)).count == 200)
        #expect(history.unreadable == 0)
        _ = try await store.export(try #require(history.runs.first))
        #expect(try await store.history().runs.count == 200)
    }
}
