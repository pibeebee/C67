import C67PlannerV5
import Foundation
import Testing

@Suite("Planner extreme synthetic comparison", .serialized)
struct PlannerExtremeTests {
    private typealias Fixture = PlannerExtremeFixture
    private typealias Stop = Fixture.Stop
    private typealias Series = PlannerV51WeatherSeries

    @Test func sixStopsWithTwoReservationsAndRequiredReturn() async throws {
        let fixture = Self.stress(weather: true)
        let reference = fixture.oracle()
        let canonical = try #require(fixture.replay(fixture.stops.map(\.id), departure: fixture.start))
        #expect(canonical.visits.last?.end == 658)
        #expect(!reference.isEmpty)
        for engine in PlannerExtremeEngine.allCases {
            let observation = try await fixture.measure(engine)
            Self.verify(observation, fixture: fixture, reference: reference)
            Self.report(observation, engine: engine, fixture: fixture, reference: reference)
        }
    }

    @Test func bufferRankingAgainstAllFeasibleOrders() async throws {
        let fixture = Fixture(name: "competing-reservations", stops: [
            Stop(number: 1, sessionStart: 565, checkIn: 560),
            Stop(number: 2),
            Stop(number: 3, sessionStart: 595)
        ], wait: 60, extraTravel: 11, eta: { from, to, _ in from == 1 && to == 3 ? 16 : 5 })
        let reference = fixture.oracle()
        let minimumDrive = try #require(reference.map(\.driving).min())
        let ranks = reference.filter { $0.driving <= minimumDrive + fixture.extraTravel }.map(fixture.bufferRank)
        let best = try #require(ranks.min { $0 < $1 })
        #expect(best == (11, 11))
        #expect(ranks.contains { $0 == (15, 26) })
        for engine in PlannerExtremeEngine.allCases {
            let observation = try await fixture.measure(engine)
            Self.verify(observation, fixture: fixture, reference: reference)
            let schedule = try #require(observation.schedule)
            if engine == .v51 {
                #expect(fixture.bufferRank(schedule) == best)
                #expect(observation.result?.schedule?.checkIns.map(\.shortfallMinutes) == [0, 11])
            }
            Self.report(observation, engine: engine, fixture: fixture, reference: reference)
        }
    }

    @Test func totalShortfallBreaksTieOnWorstReservation() async throws {
        let fixture = Fixture(name: "equal-worst-check-in-shortfall", stops: [
            Stop(number: 1, sessionStart: 565, checkIn: 560),
            Stop(number: 2, closes: 595),
            Stop(number: 3, sessionStart: 595)
        ], wait: 60, extraTravel: 5, eta: { from, to, _ in
            if from == 2 && (to == 1 || to == 3) { return 0 }
            if from == 1 && to == 3 { return 10 }
            return 5
        })
        let reference = fixture.oracle()
        let scores = reference.map(fixture.bufferRank)
        #expect(scores.count == 2)
        #expect(scores.contains { $0 == (10, 10) })
        #expect(scores.contains { $0 == (10, 15) })
        #expect(Set(reference.map(\.driving)) == [15, 20])
        let observation = try await fixture.measure(.v51)
        let schedule = try #require(observation.schedule)
        #expect(fixture.bufferRank(schedule) == (10, 10))
    }

    @Test func inclusivityAtCheckInWaitAndReturnBoundaries() async throws {
        let checkIn = Stop(number: 1, sessionStart: 550, checkIn: 545)
        let waitingStops = [Stop(number: 1, sessionStart: 550), Stop(number: 2, sessionStart: 570)]
        let cases: [(Fixture, Fixture, PlannerV5Issue, String)] = [
            (Fixture(name: "check-in-at-cutoff", stops: [checkIn], wait: 5, locked: true),
             Fixture(name: "check-in-one-minute-late", stops: [checkIn], wait: 5, locked: true,
                     eta: { from, _, _ in from == 0 ? 6 : 5 }), .checkIn(checkIn.id), "session_arrival_missed"),
            (Fixture(name: "exact-wait-limit", stops: waitingStops, wait: 10, locked: true),
             Fixture(name: "wait-one-minute-over", stops: waitingStops, wait: 9, locked: true),
             .waiting(waitingStops[1].id), "hard_target_missed"),
            (Fixture(name: "return-at-cutoff", stops: [Stop(number: 1)], finish: 560, locked: true),
             Fixture(name: "return-one-minute-late", stops: [Stop(number: 1)], finish: 560, locked: true,
                     eta: { _, to, _ in to == 0 ? 6 : 5 }), .deadline, "return_deadline_exceeded")
        ]
        for (atLimit, pastLimit, issue, legacyCode) in cases {
            let reference = atLimit.oracle()
            #expect(reference.count == 1)
            #expect(pastLimit.oracle().isEmpty)
            for engine in PlannerExtremeEngine.allCases {
                let accepted = try await atLimit.measure(engine)
                let rejected = try await pastLimit.measure(engine)
                #expect(accepted.schedule == reference.first,
                        "\(engine.rawValue) \(atLimit.name): \(accepted.outcome)")
                #expect(rejected.schedule == nil, "\(engine.rawValue) \(pastLimit.name)")
                if let result = rejected.result {
                    #expect(result.status == .conflicts)
                    #expect(result.issues.contains(issue))
                } else {
                    #expect(rejected.legacyIssueCodes.contains(legacyCode), "\(rejected.outcome)")
                }
            }
        }
    }

    @Test func integratesShortHeatSpikeAndUsesHalfOpenWeatherIntervals() async throws {
        let outdoor = Stop(number: 1, duration: 30)
        let indoor = Stop(number: 2)
        let temp = Self.series(.apparentTemperature,
                               [(545, 555, 28), (555, 560, 43), (560, 575, 30), (575, 580, 60)], threshold: 30)
        let uv = Self.series(.uvIndex, [(545, 550, 9), (550, 575, 3)])
        let sun = Self.series(.directIrradiance, [(545, 565, 600), (565, 575, 300)])
        let forecast = [temp, uv, sun]
        let fixture = Fixture(name: "short-heat-spike", stops: [outdoor, indoor], locked: true, context: [
            outdoor.id: Self.outdoor(forecast),
            indoor.id: .init(exposure: .indoor, exposureSource: .traveller, outdoorWeather: forecast)
        ])
        let reference = try #require(fixture.oracle().first)
        for engine in PlannerExtremeEngine.allCases {
            let observation = try await fixture.measure(engine)
            let schedule = try #require(observation.schedule)
            #expect(schedule == reference)
            let visit = try #require(schedule.visits.first)
            #expect(fixture.weatherScore(temp, during: visit) == 65)
            #expect(fixture.weatherScore(uv, during: visit) == 4)
            #expect(fixture.weatherScore(sun, during: visit) == 500)
            if engine == .v51 {
                let visits = try #require(observation.result?.schedule?.outdoorVisits)
                #expect(visits.map(\.placeID) == [outdoor.id])
                let readings = try #require(visits.first?.readings)
                #expect(readings.first { $0.kind == .apparentTemperature }?.average == 31.5)
                #expect(readings.first { $0.kind == .apparentTemperature }?.excessIntegral == 65)
                #expect(readings.first { $0.kind == .uvIndex }?.average == 4)
                #expect(readings.first { $0.kind == .directIrradiance }?.average == 500)
            }
        }
    }

    @Test func reportsConflictingWeatherAcrossTwoOutdoorActivities() async throws {
        let park = Stop(number: 1)
        let coveredMarket = Stop(number: 2)
        let weather = [
            Self.series(.apparentTemperature, [(545, 555, 28), (560, 570, 40)]),
            Self.series(.uvIndex, [(545, 555, 2), (560, 570, 9)]),
            Self.series(.directIrradiance, [(545, 555, 200), (560, 570, 850)])
        ]
        let fixture = Fixture(name: "two-outdoor-tradeoff", stops: [park, coveredMarket], context: [
            park.id: Self.outdoor(weather),
            coveredMarket.id: Self.outdoor(weather, exposure: .sheltered)
        ])
        let reference = fixture.oracle()
        #expect(reference.count == 2)
        for engine in PlannerExtremeEngine.allCases {
            let observation = try await fixture.measure(engine)
            let schedule = try #require(observation.schedule)
            #expect(reference.contains(schedule))
            if engine != .v51 { continue }
            let result = try #require(observation.result)
            #expect(schedule.visits.map(\.id) == [park.id, coveredMarket.id])
            #expect(result.alternative?.visits.map(\.placeID) == [coveredMarket.id, park.id])
            let changes = try #require(result.alternativeComparison?.weather)
            let parkUV = changes.first { $0.placeID == park.id && $0.kind == .uvIndex }
            let marketUV = changes.first { $0.placeID == coveredMarket.id && $0.kind == .uvIndex }
            #expect(parkUV?.scoreDelta == 7)
            #expect(marketUV?.scoreDelta == -7)
            #expect(!changes.contains { $0.placeID == coveredMarket.id && $0.kind == .directIrradiance })
        }
    }

    @Test func invalidUVCoverageDoesNotEraseComparableTemperature() async throws {
        let indoor = Stop(number: 1)
        let park = Stop(number: 2)
        let temp = Self.series(.apparentTemperature, [(545, 555, 29), (560, 570, 39)])
        let clean = Self.series(.uvIndex, [(545, 555, 3), (560, 570, 7)])
        let variants: [(String, [Series], Double?)] = [
            ("interior-gap", [Self.series(.uvIndex, [(545, 550, 3), (551, 555, 3), (560, 570, 7)])], nil),
            ("overlap", [Self.series(.uvIndex, [(545, 551, 3), (550, 555, 3), (560, 570, 7)])], nil),
            ("mixed-sources", [clean, Self.series(.uvIndex, [(560, 570, 7)], source: "Synthetic B")], nil),
            ("outside-gap", [clean], -4)
        ]
        for (name, readings, expectedUV) in variants {
            let fixture = Fixture(name: name, stops: [indoor, park], context: [
                park.id: Self.outdoor([temp] + readings)
            ])
            let observation = try await fixture.measure(.v51)
            let result = try #require(observation.result)
            #expect(observation.schedule?.visits.first?.id == park.id)
            let changes = try #require(result.comparisonWithFastest?.weather)
            let uv = try #require(changes.first { $0.kind == .uvIndex })
            #expect(uv.scoreDelta == expectedUV, "\(name)")
            #expect(changes.first { $0.kind == .apparentTemperature }?.scoreDelta == -10)
        }
    }

    @Test func incompleteETAAndRouteBudgetKeepSchedulesVerifiable() async throws {
        let stops = [Stop(number: 1), Stop(number: 2)]
        let recoverable = Fixture(name: "directional-outage", stops: stops, eta: { from, to, minute in
            from == 0 && to == 1 && minute == 540 ? nil : 5
        })
        let unavailable = Fixture(name: "all-first-legs-unavailable", stops: stops, eta: { from, _, _ in from == 0 ? nil : 5 })
        // Six one-minute legs and 60 minutes of visiting put the return departure 66 minutes after start.
        // The only complete itinerary leaves at 09:01, between the 30-minute departure seeds.
        let saturated = Fixture(name: "quote-budget", stops: (1 ... 6).map { Stop(number: $0) },
                                finish: 930, flexible: true, locked: true, eta: { _, to, minute in
            if to == 0 { return minute == 607 ? 1 : nil }
            return 1
        })
        let recoveryReference = recoverable.oracle()
        let budgetReference = saturated.oracle()
        #expect(recoveryReference.count == 1)
        #expect(unavailable.oracle().isEmpty)
        #expect(budgetReference.map(\.departure) == [541])
        for engine in PlannerExtremeEngine.allCases {
            let recovered = try await recoverable.measure(engine)
            #expect(recovered.schedule == recoveryReference.first)
            let failed = try await unavailable.measure(engine)
            #expect(failed.schedule == nil)
            if let result = failed.result {
                #expect(result.status == .incomplete)
                #expect(result.limit == .unavailableETA)
            } else {
                #expect(failed.legacyIssueCodes.contains("eta:route_unavailable"))
            }
            Self.report(recovered, engine: engine, fixture: recoverable, reference: recoveryReference)
            Self.report(failed, engine: engine, fixture: unavailable, reference: [])
            let bounded = try await saturated.measure(engine)
            Self.verify(bounded, fixture: saturated, reference: budgetReference)
            Self.report(bounded, engine: engine, fixture: saturated, reference: budgetReference)
            if let result = bounded.result {
                #expect(bounded.quotes == 72)
                #expect(result.limit == .routeQuotes)
                #expect(result.status == .incomplete)
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["C67_RUN_EXTREME_BENCHMARKS"] == "1"))
    func measuresThreeEnginesWithDenseForecastAndDelayedETA() async throws {
        var delayed = Self.stress(weather: true)
        delayed.delay = true
        let engines = PlannerExtremeEngine.allCases
        for fixture in [Self.stress(weather: false), Self.stress(weather: true), delayed] {
            let reference = fixture.oracle()
            #expect(!reference.isEmpty)
            var observations: [PlannerExtremeEngine: [Fixture.Observation]] = [:]
            for round in 0 ... 30 {
                for offset in engines.indices {
                    let engine = engines[(round + offset) % engines.count]
                    let observation = try await fixture.measure(engine)
                    Self.verify(observation, fixture: fixture, reference: reference)
                    if round > 0 { observations[engine, default: []].append(observation) }
                }
            }
            for engine in engines {
                let rows = try #require(observations[engine])
                try #require(rows.count == 30)
                let elapsed = rows.map { Self.milliseconds($0.elapsed) }.sorted()
                let median = (elapsed[14] + elapsed[15]) / 2
                let success = rows.compactMap(\.schedule).count
                let outcomes = Set(rows.map(\.outcome)).sorted()
                let quotes = Set(rows.map(\.quotes)).sorted()
                print("EXTREME BENCHMARK \(fixture.name) delay=\(fixture.delay) \(engine.rawValue) feasible=\(success)/30 "
                      + "median_ms=\(median) p95_ms=\(elapsed[28]) quotes=\(quotes) outcomes=\(outcomes)")
                Self.report(rows[0], engine: engine, fixture: fixture, reference: reference)
            }
        }
    }

    private static func stress(weather: Bool) -> Fixture {
        let stops = [
            Stop(number: 1, duration: 12), Stop(number: 2, duration: 12, sessionStart: 575, checkIn: 570),
            Stop(number: 3, duration: 12), Stop(number: 4, duration: 12, lastEntry: 610),
            Stop(number: 5, duration: 12, sessionStart: 631, checkIn: 630), Stop(number: 6, duration: 10)
        ]
        var fixture = Fixture(name: weather ? "six-dense-forecast" : "six-no-forecast", stops: stops,
                              finish: 675, wait: 16, flexible: true, first: 1, extraTravel: 6, eta: { from, to, minute in
            if from == 4 && to == 5 && (620 ..< 625).contains(minute) { return 8 }
            if to == from + 1 || to == 0 { return 5 }
            let rush = (minute / 5 + from + to).isMultiple(of: 3)
            return 7 + (from * 3 + to) % 4 + (rush ? 12 : 0)
        })
        if weather {
            for stop in [stops[2], stops[5]] {
                let kinds: [PlannerV51WeatherKind] = [.apparentTemperature, .directIrradiance, .uvIndex]
                let forecasts = kinds.enumerated().map { index, kind in
                    let bins = stride(from: fixture.start, to: fixture.finish, by: 5).map { minute in
                        let cycle = Double((minute / 5 + stop.number * (index + 1)) % 7)
                        let values = [28 + cycle * 2, 140 + cycle * 130, 1 + cycle * 1.5]
                        return (minute, minute + 5, values[index])
                    }
                    return series(kind, bins, threshold: kind == .apparentTemperature ? 32 : nil)
                }
                fixture.context[stop.id] = outdoor(forecasts)
            }
        }
        return fixture
    }

    private static func outdoor(_ forecast: [Series], exposure: PlannerV51SunExposure = .direct) -> PlannerV5VisitContext {
        .init(exposure: .outdoor, exposureSource: .traveller, sunExposure: exposure,
              sunExposureSource: .traveller, outdoorWeather: forecast)
    }

    private static func series(_ kind: PlannerV51WeatherKind, _ bins: [(Int, Int, Double)],
                               threshold: Double? = nil, source: String = "Synthetic A") -> Series {
        .init(kind: kind, source: source, samples: bins.map { start, end, value in
            .init(interval: .init(start: Fixture.date(start), end: Fixture.date(end)), value: value)
        }, threshold: threshold)
    }

    private static func verify(_ observation: Fixture.Observation, fixture: Fixture, reference: [Fixture.Schedule]) {
        #expect(observation.quotes <= 72)
        if let schedule = observation.schedule {
            #expect(fixture.replay(schedule.visits.map(\.id), departure: schedule.departure) == schedule,
                    "\(fixture.name)")
        } else if !reference.isEmpty, let result = observation.result {
            #expect(result.status == .incomplete, "\(fixture.name)")
        }
    }

    private static func report(_ observation: Fixture.Observation, engine: PlannerExtremeEngine,
                               fixture: Fixture, reference: [Fixture.Schedule]) {
        let fastest = reference.map(\.driving).min()
        let bestBuffer = fastest.flatMap { fastest in
            reference.filter { $0.driving <= fastest + fixture.extraTravel }.map(fixture.bufferRank).min { $0 < $1 }
        }
        let schedule = observation.schedule
        let driveGap = schedule.flatMap { schedule in fastest.map { schedule.driving - $0 } }
        let deficits = schedule.map(fixture.bufferShortfalls)
        let bufferGap = schedule.flatMap { schedule -> String? in
            guard let fastest, let bestBuffer, schedule.driving <= fastest + fixture.extraTravel else { return nil }
            let rank = fixture.bufferRank(schedule)
            return "worst=\(rank.0 - bestBuffer.0),total=\(rank.1 - bestBuffer.1)"
        }
        let weather = schedule?.visits.flatMap { visit in
            (fixture.context[visit.id]?.outdoorWeather ?? []).map { reading in
                "\(visit.id)/\(reading.kind)=\(label(fixture.weatherScore(reading, during: visit)))"
            }
        }
        print("EXTREME QUALITY \(fixture.name) \(engine.rawValue) outcome=\(observation.outcome) "
              + "oracle_feasible=\(reference.count) quotes=\(observation.quotes) drive=\(label(schedule?.driving)) "
              + "drive_gap=\(label(driveGap)) shortfalls=\(label(deficits)) best_buffer_rank=\(label(bestBuffer)) "
              + "buffer_gap=\(label(bufferGap)) weather=\(label(weather))")
    }

    private static func label<T>(_ value: T?) -> String {
        value.map { String(describing: $0) } ?? "unknown"
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
    }
}
