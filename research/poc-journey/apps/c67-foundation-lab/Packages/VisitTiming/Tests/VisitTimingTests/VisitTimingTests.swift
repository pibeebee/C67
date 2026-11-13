import Foundation
import Testing

@testable import VisitTiming

struct PublishedJakartaCases {
    let catalog = try! TimingCatalog.load()
    // Evaluation clock is frozen after the source retrieval; scenario dates stay unchanged.
    let now = ISO8601DateFormatter().date(from: "2026-11-05T02:00:00Z")!
    func evaluate(
        _ venue: String, _ date: String, _ available: MinuteRange = .init(360, 1440),
        duration: Int = 60, goal: TimingGoal = .openingOnly
    ) throws -> TimingRun {
        try VisitTimingEngine().evaluate(
            .init(
                venueID: venue, date: date, available: available,
                durationMinutes: duration, goal: goal), catalog: catalog, now: now)
    }
    @Test func actualCatalogProvenance() throws {
        #expect(catalog.venues.count == 11)
        #expect(catalog.sources.count == 4)
        #expect(catalog.sources.allSatisfy { $0.note.contains("SHA256") })
        try catalog.validate()
    }
    @Test func gbkMiddayIsOutsidePublishedSessions() throws {
        let result = try evaluate("gbk", "2026-11-06", .init(600, 900))
        #expect(result.status == "no_window")
        #expect(result.options.isEmpty)
    }
    @Test func gbkWholeVisitCannotCrossMiddayClosure() throws {
        let result = try evaluate("gbk", "2026-11-06", .init(540, 1020), duration: 120)
        #expect(result.options.allSatisfy { VenueClock.label($0.start) >= "15.00" })
        #expect(result.validStartRanges == [.init(900, 900)])
    }
    @Test func gbkHasTwoSeparateStartRanges() throws {
        let result = try evaluate("gbk", "2026-11-06")
        #expect(result.validStartRanges == [.init(360, 540), .init(900, 1020)])
    }
    @Test func ragunanMondayIsExplicitlyClosed() throws {
        #expect(try evaluate("ragunan", "2026-11-09").status == "closed_regular")
    }
    @Test func ragunanCannotStayAfterSixteen() throws {
        let result = try evaluate("ragunan", "2026-11-07", .init(930, 1080))
        #expect(result.status == "no_window")
    }
    @Test func fridayCikiniNewEntryIsPaused() throws {
        let result = try evaluate("cikini", "2026-11-06", .init(690, 780), duration: 30)
        #expect(result.status == "no_window")
    }
    @Test func fridayPauseIsNotVenueClosure() throws {
        let result = try evaluate("cikini", "2026-11-06", .init(660, 840), duration: 120)
        #expect(result.status == "regular_hours_options")
        #expect(result.options.first.map { VenueClock.label($0.start) } == "11.00")
        #expect(result.options.first.map { VenueClock.label($0.end) } == "13.00")
    }
    @Test func fridayCheckinResumesAtThirteen() throws {
        #expect(try evaluate("cikini", "2026-11-06", .init(780, 840)).options.count == 1)
    }
    @Test func jatiWeekendClosesAtFourteenThirty() throws {
        let result = try evaluate("jatinegara", "2026-11-08", .init(840, 960))
        #expect(result.status == "no_window")
        let short = try evaluate("jatinegara", "2026-11-08", .init(840, 960), duration: 30)
        #expect(short.options.first.map { VenueClock.label($0.end) } == "14.30")
    }
    @Test func petojoFridayHasEntryPauseButJatinegaraDoesNotClaimOne() throws {
        #expect(
            try evaluate("petojo", "2026-11-06", .init(690, 780), duration: 30).status == "no_window")
        #expect(
            try evaluate("jatinegara", "2026-11-06", .init(690, 780), duration: 30).options.count > 0)
    }
    @Test(arguments: ["tanjung-duren", "gandaria", "koja"])
    func omittedWeekendHoursRemainUnknown(_ venue: String) throws {
        let result = try evaluate(venue, "2026-11-08")
        #expect(result.status == "hours_unknown")
        #expect(result.options.isEmpty)
    }
    @Test func macanClosureNoticeOverridesRegularTable() throws {
        let result = try evaluate("macan", "2026-11-06", .init(600, 1080))
        #expect(result.status == "suspended")
        #expect(result.options.isEmpty)
        #expect(result.venue.schedule.first { $0.weekday == 5 }?.lastEntry == 1050)
    }
    @Test func noOutdoorContextInventedForLibrary() throws {
        #expect(try evaluate("cikini", "2026-11-06", goal: .daylight).status == "context_unknown")
    }
    @Test func missingForecastDoesNotMeanZeroRain() throws {
        let result = try evaluate("gbk", "2026-11-06", goal: .lowerRain)
        #expect(result.status == "context_unavailable")
        #expect(result.options.isEmpty)
        #expect(!result.validStartRanges.isEmpty)
    }
    @Test func unpublishedBestTimeRemainsUnknown() throws {
        let result = try evaluate("nyi-ageng", "2026-11-06")
        #expect(result.status == "regular_hours_options")
        #expect(result.options.allSatisfy { $0.maxRainChance == nil })
        #expect(result.warnings.contains { $0.contains("asumsi") })
    }
    @Test func jakartaDateIsIndependentOfDeviceTimeZone() throws {
        let day = try VenueClock.day("2026-11-06")
        #expect(day.ISO8601Format() == "2026-11-05T17:00:00Z")
        #expect(VenueClock.dateString(day) == "2026-11-06")
    }
    @Test func staleFactsBlockCurrentSuggestions() throws {
        let run = try VisitTimingEngine().evaluate(
            .init(venueID: "gbk", date: "2026-11-20"),
            catalog: catalog, now: now.addingTimeInterval(15 * 86400))
        #expect(run.status == "needs_recheck")
        #expect(run.options.isEmpty)
    }
    @Test func historicalDayIsNotReconstructedFromNewSnapshot() throws {
        #expect(try evaluate("gbk", "2026-11-04").status == "needs_recheck")
    }
    @Test func invalidCalendarDateRejected() {
        #expect(throws: (any Error).self) { try VenueClock.day("2026-02-30") }
    }
    @Test func unknownVenueAndSourceRejected() throws {
        #expect(throws: (any Error).self) { try evaluate("invented", "2026-11-06") }
        var invalid = catalog
        invalid.venues[0].sourceIDs = ["invented"]
        #expect(throws: (any Error).self) { try invalid.validate() }
    }
    @Test func storageKeepsUnreadableFileAndRestoresValidRuns() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = TimingStore(directory: path)
        let original = try evaluate("gbk", "2026-11-06")
        try await store.save(original)
        try Data("invalid json".utf8).write(to: path.appendingPathComponent("broken.json"))
        let saved = try await store.history()
        #expect(saved.runs.count == 1 && saved.unreadable == 1)
        #expect(saved.runs.first?.id == original.id)
        #expect(FileManager.default.fileExists(atPath: path.appendingPathComponent("broken.json").path))
        let export = try await store.export(original)
        #expect(FileManager.default.fileExists(atPath: export.appendingPathComponent("REPORT.md").path))
    }
}

/// Fault-injection tests mutate acquired data, never represent a live weather observation.
struct EnvironmentContractChecks {
    @Test func partialHourGapNullAndInvalidRainAreUnknown() {
        let start = Date(timeIntervalSince1970: 0)
        var value = TimingEnvironment(
            provider: "FAULT INJECTION", fetchedAt: start, validUntil: start,
            date: "1970-01-01", venueID: "gbk", latitude: 0, longitude: 0, locationName: "test",
            locationSource: "engineering fixture",
            hours: [
                .init(start: start, rainChance: 0.2, temperatureC: 30)
            ], sunrise: nil, sunset: nil, attributionURL: URL(string: "https://example.invalid")!,
            attribution: "engineering fixture", errors: [])
        #expect(
            VisitTimingEngine.weatherCoverage(
                value, start: start.addingTimeInterval(1800),
                end: start.addingTimeInterval(5400)
            ).rain == nil)
        value.hours[0].rainChance = nil
        #expect(
            VisitTimingEngine.weatherCoverage(value, start: start, end: start.addingTimeInterval(900))
                .rain == nil)
        value.hours[0].rainChance = 2
        #expect(
            VisitTimingEngine.weatherCoverage(value, start: start, end: start.addingTimeInterval(900))
                .rain == nil)
    }
}

struct AcquiredForecastReplay {
    func acquired(_ id: String) throws -> TimingRun {
        let path = Bundle.module.url(
            forResource: "\(id)-actual-2026-11-05", withExtension: "json",
            subdirectory: "Fixtures")!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TimingRun.self, from: Data(contentsOf: path))
    }
    func result(_ id: String, goal: TimingGoal, mutate: (inout TimingEnvironment) -> Void = { _ in })
        throws -> TimingRun
    {
        let original = try acquired(id)
        var environment = original.environment!
        let now = environment.fetchedAt.addingTimeInterval(1)
        mutate(&environment)
        return try VisitTimingEngine().evaluate(
            .init(venueID: id, date: "2026-11-05", available: .init(360, 1320), goal: goal),
            catalog: TimingCatalog.load(), environment: environment, now: now)
    }
    @Test func actualGbkRainOptionsStayInPublishedSessions() throws {
        let run = try result("gbk", goal: .lowerRain)
        #expect(run.status == "context_ranked" && !run.options.isEmpty)
        for option in run.options {
            let start = VenueClock.label(option.start)
            let end = VenueClock.label(option.end)
            #expect((start >= "06.00" && end <= "10.00") || (start >= "15.00" && end <= "18.00"))
            let measured = VisitTimingEngine.weatherCoverage(
                run.environment, start: option.start, end: option.end)
            #expect(option.maxRainChance == measured.rain)
        }
        #expect(run.options.map { $0.maxRainChance! } == run.options.map { $0.maxRainChance! }.sorted())
    }
    @Test func actualGbkDaylightEndsBeforeSunset() throws {
        let run = try result("gbk", goal: .daylight)
        #expect(run.status == "context_ranked")
        #expect(
            run.options.allSatisfy {
                $0.start >= run.environment!.sunrise! && $0.end <= run.environment!.sunset!
            })
    }
    @Test func actualGbkSunsetPreferenceFitsClosingTime() throws {
        let run = try result("gbk", goal: .nearSunset)
        #expect(run.status == "context_ranked")
        #expect(
            run.options.allSatisfy {
                $0.start >= run.environment!.sunset!.addingTimeInterval(-3600)
                    && VenueClock.label($0.end) <= "18.00"
            })
    }
    @Test func actualRagunanSunsetCannotFitBeforeSixteen() throws {
        let run = try result("ragunan", goal: .nearSunset)
        #expect(run.status == "context_unavailable")
        #expect(run.options.isEmpty)
        #expect(VenueClock.label(run.environment!.sunset!) > "16.00")
    }
    @Test func wrongVenueExpiredAndMissingDataAreNotReused() throws {
        // Explicit mutations for engineering faults; not new live weather observations.
        for mutation in [
            { (e: inout TimingEnvironment) in e.venueID = "ragunan" },
            { (e: inout TimingEnvironment) in e.validUntil = e.fetchedAt },
            { (e: inout TimingEnvironment) in e.hours = [] },
        ] {
            let run = try result("gbk", goal: .lowerRain, mutate: mutation)
            #expect(run.status == "context_unavailable")
            #expect(run.options.isEmpty)
        }
    }
}
