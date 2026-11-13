import Foundation
import Testing

@testable import VisitTiming

struct TimingInvariantTests {
    private func starts(_ run: TimingRun) -> Set<Int> {
        Set(run.validStartRanges.flatMap { Array(stride(from: $0.start, through: $0.end, by: 15)) })
    }

    @Test(.timeLimit(.minutes(1)))
    func completePublishedRuleMatrixAgainstBruteForceDomain() throws {
        let f = try ExtremeFixture()
        let dates = [
            "2026-11-06", "2026-11-07", "2026-11-08", "2026-11-09",
            "2026-11-10", "2026-11-11", "2026-11-12",
        ]
        let ranges = [MinuteRange(0, 1440), .init(540, 840), .init(840, 1080)]
        let calendar = try VenueClock.calendar("Asia/Jakarta")
        var count = 0
        for venue in f.catalog.venues {
            for date in dates {
                let day = try VenueClock.day(date)
                let weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
                let schedule = venue.schedule.first { $0.weekday == weekday }
                for duration in [15, 30, 60, 180, 360] {
                    for range in ranges {
                        let request = TimingRequest(
                            venueID: venue.id, date: date, available: range,
                            durationMinutes: duration)
                        let run = try VisitTimingEngine().evaluate(request, catalog: f.catalog, now: f.now)
                        // Independently enumerate the entire day's quarter-hour domain; no engine helper is used.
                        let expected = Set(
                            stride(from: 0, through: 1440 - duration, by: 15).filter { minute in
                                guard !venue.suspended, let schedule,
                                      range.start <= minute, minute + duration <= range.end
                                else { return false }
                                return schedule.sessions.contains {
                                    $0.start <= minute && minute + duration <= $0.end
                                }
                                    && (schedule.lastEntry.map { minute <= $0 } ?? true)
                                    && !schedule.entryPauses.contains { $0.start <= minute && minute < $0.end }
                            })
                        try #require(
                            starts(run) == expected,
                            "\(venue.id) \(date) duration \(duration) availability \(range.label)")
                        try #require(run.options.count <= 3)
                        try run.validate()
                        for option in run.options {
                            let minute = Int(option.start.timeIntervalSince(day) / 60)
                            try #require(expected.contains(minute))
                            try #require(option.end.timeIntervalSince(option.start) == Double(duration * 60))
                        }
                        count += 1
                    }
                }
            }
        }
        #expect(count == 1155)
        print("EXTREME_PUBLISHED_MATRIX_CASES=\(count)")
    }

    @Test
    func increasingDurationAndNarrowingAvailabilityNeverIntroduceNewStarts() throws {
        let f = try ExtremeFixture()
        var comparisons = 0
        for venue in f.catalog.venues {
            for date in ["2026-11-06", "2026-11-07", "2026-11-08", "2026-11-09"] {
                let full = TimingRequest(
                    venueID: venue.id, date: date, available: .init(0, 1440),
                    durationMinutes: 15)
                let baseline = starts(
                    try VisitTimingEngine().evaluate(full, catalog: f.catalog, now: f.now))
                for duration in [30, 60, 180, 360] {
                    var larger = full
                    larger.durationMinutes = duration
                    let actual = starts(
                        try VisitTimingEngine().evaluate(larger, catalog: f.catalog, now: f.now))
                    try #require(actual.isSubset(of: baseline))
                    comparisons += 1
                }
                for range in [MinuteRange(540, 600), .init(600, 900), .init(900, 1080)] {
                    var narrower = full
                    narrower.available = range
                    let actual = starts(
                        try VisitTimingEngine().evaluate(narrower, catalog: f.catalog, now: f.now))
                    try #require(actual.isSubset(of: baseline))
                    comparisons += 1
                }
            }
        }
        #expect(comparisons == 308)
        print("EXTREME_MONOTONIC_COMPARISONS=\(comparisons)")
    }

    @Test func crossingMidnightCannotReviveYesterdaysSlots() throws {
        var f = try ExtremeFixture()
        f.now = try VenueClock.day("2026-11-06")
        let run = try f.evaluate(.init(venueID: "gbk", date: "2026-11-05"))
        #expect(run.status == "no_window")
        #expect(run.options.isEmpty && run.validStartRanges.isEmpty)
    }

    @Test func advancingTodayClockOnlyRemovesPossibleStarts() throws {
        var f = try ExtremeFixture()
        let day = try VenueClock.day("2026-11-05")
        var previous = Set(0 ... 1440)
        for minute in stride(from: 540, through: 1440, by: 15) {
            f.now = day.addingTimeInterval(Double(minute * 60))
            let run = try f.evaluate(
                .init(
                    venueID: "gbk", date: "2026-11-05",
                    available: .init(360, 1080), durationMinutes: 15))
            let actual = starts(run)
            try #require(actual.isSubset(of: previous))
            previous = actual
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteEvaluationClockIsRejected(_ interval: Double) throws {
        var f = try ExtremeFixture()
        f.now = Date(timeIntervalSince1970: interval)
        #expect(throws: (any Error).self) { try f.evaluate() }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.01, 1.01])
    func invalidRainCannotBecomeDryWeatherOrEraseValidSolarData(_ rain: Double) throws {
        let f = try ExtremeFixture()
        var weather = f.acquired
        for i in weather.hours.indices { weather.hours[i].rainChance = rain }
        let lowerRain = try f.evaluate(weather: weather)
        #expect(lowerRain.status == "context_unavailable")
        #expect(lowerRain.options.isEmpty)
        let daylight = try f.evaluate(
            .init(
                venueID: "gbk", date: "2026-11-05",
                available: .init(900, 1080), goal: .daylight), weather: weather)
        #expect(daylight.status == "context_ranked")
        #expect(daylight.options.allSatisfy { $0.maxRainChance == nil })
        #expect(throws: Never.self) { try f.encoded(daylight) }
    }

    @Test func missingMiddleHourCannotBeInterpolatedAsDry() throws {
        let f = try ExtremeFixture()
        var weather = f.acquired
        weather.hours.removeAll { VenueClock.label($0.start) == "16.00" }
        let request = TimingRequest(
            venueID: "gbk", date: "2026-11-05",
            available: .init(900, 1080), durationMinutes: 120, goal: .lowerRain)
        let run = try f.evaluate(request, weather: weather)
        #expect(run.status == "context_unavailable")
        #expect(run.options.isEmpty)
    }

    @Test(arguments: ["2024-02-29", "2000-02-29", "2028-02-29", "2026-12-31", "2027-01-01"])
    func validLeapAndYearBoundaryDatesRoundTrip(_ text: String) throws {
        #expect(VenueClock.dateString(try VenueClock.day(text)) == text)
    }

    @Test(arguments: ["2100-02-29", "2026-13-01", "2026-01-00", "2026-12-32"])
    func invalidGregorianBoundariesAreRejected(_ text: String) {
        #expect(throws: (any Error).self) { try VenueClock.day(text) }
    }

    @Test(arguments: [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude])
    func finiteButUnencodableEvaluationClockIsRejected(_ interval: Double) throws {
        var f = try ExtremeFixture()
        f.now = Date(timeIntervalSince1970: interval)
        #expect(throws: (any Error).self) { try f.evaluate() }
    }

    @Test(arguments: [Double.greatestFiniteMagnitude, 1_793_838_600_000.0])
    func corruptExtremeOrMillisecondTimestampCannotPoisonHistory(_ interval: Double) async throws {
        let f = try ExtremeFixture()
        var weather = f.acquired
        weather.hours = [
            .init(
                start: Date(timeIntervalSince1970: interval),
                rainChance: 0, temperatureC: 30)
        ]
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = TimingStore(directory: path)
        let run = try f.evaluate(weather: weather)
        #expect(run.environment?.hours.isEmpty == true)
        try await store.save(run)
        let history = try await store.history()
        #expect(history.runs.count == 1 && history.unreadable == 0)
    }
}
