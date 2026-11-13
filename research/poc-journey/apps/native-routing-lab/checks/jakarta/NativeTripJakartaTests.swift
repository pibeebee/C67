import Foundation
import XCTest

@testable import C67RoutingHarness

@MainActor final class NativeTripJakartaTests: XCTestCase {
    private func assertComplete(
        _ candidate: NativeTripCandidate, fixture: JakartaFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertTrue(candidate.complete, file: file, line: line)
        XCTAssertTrue(
            candidate.feasible, candidate.conflicts.joined(separator: "; "), file: file, line: line)
        XCTAssertEqual(candidate.order.count, fixture.draft.stops.count, file: file, line: line)
        XCTAssertEqual(Set(candidate.order), Set(fixture.draft.stops.map(\.id)), file: file, line: line)
        XCTAssertEqual(candidate.legs.count, fixture.draft.stops.count + 1, file: file, line: line)
        XCTAssertEqual(candidate.legs.last?.to.id, fixture.draft.endPoint.id, file: file, line: line)
        let finish = try XCTUnwrap(candidate.finish, file: file, line: line)
        XCTAssertEqual(
            finish.timeIntervalSince(fixture.draft.departure), candidate.elapsedMinutes * 60,
            accuracy: 0.01, file: file, line: line)
        XCTAssertLessThanOrEqual(finish, fixture.draft.endOfDay, file: file, line: line)
    }

    func testRecordedFourStopScheduleHasExpectedTravelWaitAndReturn() async throws {
        let fixture = try JakartaFixture.load()
        let p = fixture.problem()
        try p.validate()
        XCTAssertEqual(p.coverage.requiredPairs, 20)
        XCTAssertEqual(p.coverage.availablePairs, 20)
        let c = TripRoutingEvaluator(p).evaluate(fixture.indices(JakartaFixture.earlyOrder, in: p))
        XCTAssertTrue(c.feasible && c.fullTour)
        XCTAssertEqual(c.travel, 7261, accuracy: 0.001)
        XCTAssertEqual(c.waiting, 1006, accuracy: 0.001)
        XCTAssertEqual(c.dwell, 7200, accuracy: 0.001)
        XCTAssertEqual(c.finish, 15467, accuracy: 0.001)
        let kg = try XCTUnwrap(c.legs.first { p.nodes[$0.to].id == JakartaFixture.kelapaGading })
        XCTAssertEqual(kg.visit, 10800, accuracy: 0.001)  // 10:00 WIB, three hours after 07:00.
        XCTAssertEqual(kg.leave, 12600, accuracy: 0.001)
        XCTAssertEqual(c.legs.last?.to, p.origin)
    }

    func testLessTravelDoesNotBeatAnEarlierTripFinish() async throws {
        let fixture = try JakartaFixture.load()
        let p = fixture.problem()
        let evaluator = TripRoutingEvaluator(p)
        let early = evaluator.evaluate(fixture.indices(JakartaFixture.earlyOrder, in: p))
        let late = evaluator.evaluate(fixture.indices(JakartaFixture.lateOrder, in: p))
        XCTAssertEqual(late.travel, 6442, accuracy: 0.001)
        XCTAssertEqual(late.waiting, 8881, accuracy: 0.001)
        XCTAssertEqual(late.finish, 22523, accuracy: 0.001)
        XCTAssertLessThan(late.travel, early.travel)
        XCTAssertLessThan(early.finish, late.finish)
        XCTAssertTrue(TripRoutingEvaluator.better(early, late))
    }

    func testAllSevenNativeMethodsPreserveStopsAndReachTheKnownFourStopReference() async throws {
        let fixture = try JakartaFixture.load()
        let p = fixture.problem()
        XCTAssertEqual(TripRoutingAlgorithm.native.count, 7)
        for method in TripRoutingAlgorithm.native {
            var search = TripRoutingSearch(problem: p, configuration: fixture.draft.routingConfiguration)
            let result = try search.solve(method)
            let best = try XCTUnwrap(result.best, method.rawValue)
            XCTAssertTrue(best.feasible && best.fullTour, method.rawValue)
            XCTAssertEqual(Set(best.order), Set(p.targets), method.rawValue)
            XCTAssertEqual(best.finish, 15467, accuracy: 0.001, method.rawValue)
            XCTAssertLessThanOrEqual(result.evaluations, 12000, method.rawValue)
            if method == .exact { XCTAssertEqual(result.proof, "exhaustive_fixed_evaluator") }
            try JakartaFixture.append([
                "scenario": "model_\(method.rawValue)", "kind": "model", "source": "recorded_static",
                "feasible": best.feasible, "complete": best.complete,
                "order": best.order.map { p.nodes[$0].name },
                "elapsedSeconds": best.finish, "travelSeconds": best.travel, "waitingSeconds": best.waiting,
                "dwellSeconds": best.dwell, "requests": 0, "wallSeconds": result.elapsed,
                "evaluations": result.evaluations, "proof": result.proof,
            ])
        }
    }

    func testCurrentBaselinePipelineUsesElapsedObjective() async throws {
        var fixture = try JakartaFixture.load()
        fixture.draft.routingAlgorithm = "baseline"
        let services = try fixture.services()
        let started = Date()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        let seconds = Date().timeIntervalSince(started)
        let best = try XCTUnwrap(report.fastest)
        try assertComplete(best, fixture: fixture)
        XCTAssertEqual(best.elapsedMinutes * 60, 15467, accuracy: 0.01)
        XCTAssertEqual(report.requests, 30)
        try fixture.record(
            best, scenario: "baseline_four_stops", requests: report.requests, wallSeconds: seconds)
    }

    func testHybridPipelineKeepsValidatedBaselineAndRequestBudget() async throws {
        let fixture = try JakartaFixture.load()
        let services = try fixture.services()
        let started = Date()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        let seconds = Date().timeIntervalSince(started)
        let best = try XCTUnwrap(report.fastest)
        try assertComplete(best, fixture: fixture)
        XCTAssertEqual(best.order, JakartaFixture.earlyOrder)
        XCTAssertEqual(best.elapsedMinutes * 60, 15467, accuracy: 0.01)
        XCTAssertLessThanOrEqual(report.requests, 96)
        XCTAssertEqual(report.requests, services.requests.count)
        let baselineCount = NativeTripEngine.orders(fixture.draft).count
        let baselines = report.candidates.prefix(baselineCount).filter(\.feasible)
        XCTAssertFalse(baselines.isEmpty)
        XCTAssertLessThanOrEqual(
            best.elapsedMinutes, try XCTUnwrap(baselines.map(\.elapsedMinutes).min()))
        XCTAssertNil(
            report.weatherChoice,
            "No forecast is provided; a weather recommendation must not be fabricated.")
        try fixture.record(
            best, scenario: "hybrid_four_stops", requests: report.requests, wallSeconds: seconds,
            extra: ["candidateCount": report.candidates.count, "baselineCount": baselineCount])
    }

    private func adaptiveReason(_ services: NativeTripAppleServices) throws -> String {
        let event = try XCTUnwrap(
            services.events.last { $0["name"] as? String == "routing.adaptive_decision" })
        let fields = try XCTUnwrap(event["fields"] as? [String: String])
        return try XCTUnwrap(fields["reason"])
    }

    func testAdaptiveJakartaSkipsExtraRequestsWithoutChangingSchedule() async throws {
        let fixture = try JakartaFixture.load()
        XCTAssertNil(fixture.draft.routingAdaptive, "Older drafts default to adaptive hybrid.")
        let services = try fixture.services()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        let best = try XCTUnwrap(report.fastest)
        try assertComplete(best, fixture: fixture)
        XCTAssertEqual(best.order, JakartaFixture.earlyOrder)
        XCTAssertEqual(best.elapsedMinutes * 60, 15467, accuracy: 0.01)
        XCTAssertEqual(report.requests, 30)
        XCTAssertEqual(try adaptiveReason(services), "no_material_estimated_gain")
        XCTAssertTrue(services.logs.solvers.isEmpty)
        XCTAssertNil(services.logs.refined, "Screening estimates must not become a provider snapshot.")
        XCTAssertEqual(report.candidates.count, NativeTripEngine.orders(fixture.draft).count)
        XCTAssertEqual(services.requests.count, 30)
    }

    func testForcedFullHybridRemainsAvailableForComparison() async throws {
        var fixture = try JakartaFixture.load()
        fixture.draft.routingAdaptive = false
        let services = try fixture.services()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        XCTAssertEqual(report.requests, 88)
        XCTAssertEqual(report.fastest?.order, JakartaFixture.earlyOrder)
        XCTAssertEqual(try XCTUnwrap(report.fastest).elapsedMinutes * 60, 15467, accuracy: 0.01)
        XCTAssertEqual(try adaptiveReason(services), "full_search_requested")
        XCTAssertFalse(services.logs.solvers.isEmpty)
    }

    func testAdaptiveOneAndTwoDestinationsCoverAllOrdersWithoutSnapshot() async throws {
        for ids in [[JakartaFixture.monas], [JakartaFixture.monas, JakartaFixture.grandIndonesia]] {
            var fixture = try JakartaFixture.load()
            fixture.keep(ids)
            let services = try fixture.services()
            let report = try await NativeTripEngine.plan(
                fixture.draft, services: services, progress: { _ in })
            try assertComplete(try XCTUnwrap(report.fastest), fixture: fixture)
            XCTAssertEqual(try adaptiveReason(services), "all_small_orders_validated")
            XCTAssertTrue(services.logs.solvers.isEmpty)
            XCTAssertEqual(report.candidates.count, ids.count)
        }
    }

    func testAdaptiveLargeWaitingTriggersOptimization() async throws {
        var fixture = try JakartaFixture.load()
        fixture.draft.departure.addTimeInterval(-3600)
        let services = try fixture.services()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        XCTAssertEqual(try adaptiveReason(services), "large_baseline_wait")
        XCTAssertFalse(services.logs.solvers.isEmpty)
        XCTAssertLessThanOrEqual(report.requests, 96)
        try assertComplete(try XCTUnwrap(report.fastest), fixture: fixture)
    }

    func testAdaptiveNoWaitingDoesNotHideUnknownRoadShortcuts() async throws {
        var fixture = try JakartaFixture.load()
        for i in fixture.draft.stops.indices { fixture.draft.stops[i].opening = nil }
        let services = try fixture.services()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        XCTAssertEqual(try adaptiveReason(services), "unobserved_shortcut_uncertainty")
        XCTAssertFalse(services.logs.solvers.isEmpty)
        try assertComplete(try XCTUnwrap(report.fastest), fixture: fixture)
    }

    func testAdaptiveTightClosingMarginStillRunsOptimization() async throws {
        var fixture = try JakartaFixture.load()
        let index = try XCTUnwrap(
            fixture.draft.stops.firstIndex { $0.id == JakartaFixture.kelapaGading })
        fixture.draft.stops[index].opening?.closesMinute = 630
        let services = try fixture.services()
        _ = try await NativeTripEngine.plan(fixture.draft, services: services, progress: { _ in })
        XCTAssertEqual(try adaptiveReason(services), "tight_closing_margin")
        XCTAssertFalse(services.logs.solvers.isEmpty)
    }

    func testAdaptiveScreeningPreservesWeatherAndPrivateCarSearch() async throws {
        var fixture = try JakartaFixture.load()
        let services = try fixture.services()
        var candidates: [NativeTripCandidate] = []
        for order in NativeTripEngine.orders(fixture.draft) {
            candidates.append(
                try await NativeTripEngine.evaluate(
                    order, draft: fixture.draft, services: services, forecasts: [], progress: { _ in }))
        }
        let requests = services.directionRequests
        let forecast = NativeTripForecast(
            pointID: JakartaFixture.monas,
            hours: [.init(date: fixture.draft.departure, rainChance: 0.7)], status: "available",
            note: "Synthetic test")
        let weather = try NativeTripTimeAwarePlanner.decision(
            fixture.draft, candidates: candidates, forecasts: [forecast])
        XCTAssertTrue(weather.optimize)
        XCTAssertEqual(weather.reason, "weather_alternatives")
        fixture.draft.carUse = "privateCar"
        let car = try NativeTripTimeAwarePlanner.decision(
            fixture.draft, candidates: candidates, forecasts: [])
        XCTAssertTrue(car.optimize)
        XCTAssertEqual(car.reason, "private_car_strategy_uncertainty")
        XCTAssertEqual(services.directionRequests, requests, "Screening must never fetch ETA.")
    }

    func testAdaptiveTinyScreeningBudgetFallsBackToSearch() async throws {
        var fixture = try JakartaFixture.load()
        let services = try fixture.services()
        var candidates: [NativeTripCandidate] = []
        for order in NativeTripEngine.orders(fixture.draft) {
            candidates.append(
                try await NativeTripEngine.evaluate(
                    order, draft: fixture.draft, services: services, forecasts: [], progress: { _ in }))
        }
        fixture.draft.routingEvaluationLimit = 5
        let result = try NativeTripTimeAwarePlanner.decision(
            fixture.draft, candidates: candidates, forecasts: [])
        XCTAssertTrue(result.optimize)
        XCTAssertEqual(result.evaluations, 0)
    }

    func testAdaptiveEstimatedGainTriggersValidatedOptimization() async throws {
        let fixture = try JakartaFixture.load("adaptive-material-gain-synthetic")
        let services = try fixture.services()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        XCTAssertEqual(try adaptiveReason(services), "estimated_material_gain")
        XCTAssertFalse(services.logs.solvers.isEmpty)
        let baselineCount = NativeTripEngine.orders(fixture.draft).count
        let baseline = try XCTUnwrap(
            report.candidates.prefix(baselineCount).filter(\.feasible)
                .map(\.elapsedMinutes).min())
        let best = try XCTUnwrap(report.fastest)
        try assertComplete(best, fixture: fixture)
        XCTAssertLessThan(best.elapsedMinutes, baseline)
        XCTAssertLessThanOrEqual(report.requests, 96)
    }

    func testCentralJakartaSubsetReturnsToSudirman() async throws {
        var fixture = try JakartaFixture.load()
        fixture.keep([JakartaFixture.monas, JakartaFixture.grandIndonesia])
        let services = try fixture.services()
        let started = Date()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        let seconds = Date().timeIntervalSince(started)
        let best = try XCTUnwrap(report.fastest)
        try assertComplete(best, fixture: fixture)
        XCTAssertEqual(best.order, [JakartaFixture.monas, JakartaFixture.grandIndonesia])
        XCTAssertEqual(best.travelMinutes * 60, 1971, accuracy: 0.01)
        XCTAssertEqual(best.waitingMinutes, 0, accuracy: 0.001)
        XCTAssertEqual(best.elapsedMinutes * 60, 5571, accuracy: 0.01)
        try fixture.record(
            best, scenario: "central_two_stops", requests: report.requests, wallSeconds: seconds)
    }

    func testNorthJakartaSubsetWaitsUntilKelapaGadingOpens() async throws {
        var fixture = try JakartaFixture.load()
        fixture.keep([JakartaFixture.kelapaGading, JakartaFixture.kotaTua])
        let services = try fixture.services()
        let started = Date()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        let seconds = Date().timeIntervalSince(started)
        let best = try XCTUnwrap(report.fastest)
        try assertComplete(best, fixture: fixture)
        XCTAssertEqual(best.order, [JakartaFixture.kotaTua, JakartaFixture.kelapaGading])
        XCTAssertEqual(best.travelMinutes * 60, 6432, accuracy: 0.01)
        XCTAssertEqual(best.waitingMinutes * 60, 5435, accuracy: 0.01)
        XCTAssertEqual(best.elapsedMinutes * 60, 15467, accuracy: 0.01)
        let kg = try XCTUnwrap(best.legs.first { $0.to.id == JakartaFixture.kelapaGading })
        XCTAssertEqual(try XCTUnwrap(kg.visit), fixture.draft.clockDate(minutes: 600))
        try fixture.record(
            best, scenario: "north_two_stops", requests: report.requests, wallSeconds: seconds)
    }

    func testSyntheticHoursForEveryStopAreAllRespected() async throws {
        var fixture = try JakartaFixture.load()
        for index in fixture.draft.stops.indices {
            let id = fixture.draft.stops[index].id
            fixture.draft.stops[index].opening = .init(
                opensMinute: [JakartaFixture.monas, JakartaFixture.kotaTua].contains(id) ? 480 : 600,
                closesMinute: 1080, serviceDate: "2026-11-05", timeZoneID: "Asia/Jakarta",
                sourceNote: "Synthetic testing assumptions; not verified venue hours.")
        }
        let services = try fixture.services()
        let started = Date()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        let seconds = Date().timeIntervalSince(started)
        let best = try XCTUnwrap(report.fastest)
        try assertComplete(best, fixture: fixture)
        for stop in fixture.draft.stops {
            let leg = try XCTUnwrap(best.legs.first { !$0.isReturn && $0.to.id == stop.id })
            XCTAssertGreaterThanOrEqual(
                try XCTUnwrap(leg.visit), fixture.draft.clockDate(minutes: stop.opening!.opensMinute!))
            XCTAssertLessThanOrEqual(try XCTUnwrap(leg.leave), fixture.draft.clockDate(minutes: 1080))
        }
        try fixture.record(
            best, scenario: "synthetic_all_hours_four_stops", requests: report.requests,
            wallSeconds: seconds, source: "synthetic_hours_on_recorded_matrix")
    }

    func testShuffledInputStillVisitsEveryPlaceAndRespectsOpening() async throws {
        var fixture = try JakartaFixture.load()
        fixture.keep([
            JakartaFixture.kotaTua, JakartaFixture.grandIndonesia, JakartaFixture.kelapaGading,
            JakartaFixture.monas,
        ])
        let services = try fixture.services()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        let best = try XCTUnwrap(report.fastest)
        try assertComplete(best, fixture: fixture)
        XCTAssertEqual(best.order, JakartaFixture.earlyOrder)
        XCTAssertEqual(best.elapsedMinutes * 60, 15467, accuracy: 0.01)
    }

    func testCompleteDwellAtClosingBoundaryIsAcceptedButOneMinuteEarlierIsNot() async throws {
        var fixture = try JakartaFixture.load()
        let index = try XCTUnwrap(
            fixture.draft.stops.firstIndex { $0.id == JakartaFixture.kelapaGading })
        fixture.draft.stops[index].opening?.closesMinute = 630
        var p = fixture.problem()
        let order = fixture.indices(JakartaFixture.earlyOrder, in: p)
        XCTAssertTrue(TripRoutingEvaluator(p).evaluate(order).feasible)
        fixture.draft.stops[index].opening?.closesMinute = 629
        p = fixture.problem()
        let late = TripRoutingEvaluator(p).evaluate(order)
        XCTAssertTrue(late.complete && late.fullTour)
        XCTAssertFalse(late.feasible)
        XCTAssertTrue(late.conflicts.contains { $0.contains("tutup") })
    }

    func testImpossibleOpeningWindowDoesNotProduceAFeasibleItinerary() async throws {
        var fixture = try JakartaFixture.load()
        let index = try XCTUnwrap(
            fixture.draft.stops.firstIndex { $0.id == JakartaFixture.kelapaGading })
        // A 30-minute visit cannot fit 10:00–10:15.
        fixture.draft.stops[index].opening?.closesMinute = 615
        let services = try fixture.services()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        XCTAssertEqual(report.draft.stops.count, 4)
        XCTAssertFalse(report.candidates.contains(where: \.feasible))
        XCTAssertFalse(report.fastest?.feasible == true)
        XCTAssertEqual(try adaptiveReason(services), "baseline_infeasible_or_incomplete")
        XCTAssertTrue(report.candidates.contains { $0.conflicts.contains { $0.contains("tutup") } })
        XCTAssertLessThanOrEqual(report.requests, 96)
    }

    func testChangedDateRejectsStaleOpeningHoursBeforeAnyETARequest() async throws {
        var fixture = try JakartaFixture.load()
        fixture.draft.departure = fixture.draft.calendar.date(
            byAdding: .day, value: 1, to: fixture.draft.departure)!
        let services = try fixture.services()
        do {
            _ = try await NativeTripEngine.plan(fixture.draft, services: services, progress: { _ in })
            XCTFail("Stale opening-date metadata accepted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Tanggal atau zona waktu"))
        }
        XCTAssertEqual(services.directionRequests, 0)
    }

    func testMissingAllRoutesIntoKelapaGadingRemainsUnknown() async throws {
        let fixture = try JakartaFixture.load()
        var p = fixture.problem()
        let kg = try XCTUnwrap(p.nodes.firstIndex { $0.id == JakartaFixture.kelapaGading })
        p.arcs.removeAll { $0.to == kg }
        var search = TripRoutingSearch(problem: p, configuration: fixture.draft.routingConfiguration)
        let result = try search.solve(.exact)
        XCTAssertFalse(result.best?.feasible == true)
        XCTAssertEqual(result.termination, "data_incomplete")
        XCTAssertEqual(result.proof, "not_proven")
    }

    func testUnavailableTransitAndWalkingLimitDoNotInventTransport() async throws {
        var fixture = try JakartaFixture.load()
        fixture.draft.automobile = false
        fixture.draft.routingRequestLimit = 16
        let services = try fixture.services()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        XCTAssertNil(report.fastest)
        XCTAssertFalse(report.candidates.contains(where: \.complete))
        XCTAssertTrue(
            report.candidates.allSatisfy { $0.legs.allSatisfy { $0.chosen?.mode != .automobile } })
        XCTAssertLessThanOrEqual(report.requests, 16)
    }

    func testLongerDwellPropagatesAndCanReplaceOpeningWait() async throws {
        var fixture = try JakartaFixture.load()
        fixture.draft.defaultDwell = 60
        let p = fixture.problem()
        let c = TripRoutingEvaluator(p).evaluate(fixture.indices(JakartaFixture.earlyOrder, in: p))
        XCTAssertTrue(c.feasible && c.fullTour)
        XCTAssertEqual(c.travel, 7261, accuracy: 0.001)
        XCTAssertEqual(c.dwell, 14400, accuracy: 0.001)
        XCTAssertEqual(c.waiting, 0, accuracy: 0.001)
        XCTAssertEqual(c.finish, 21661, accuracy: 0.001)
    }

    func testSyntheticPeakETAUsesActualDepartureAfterDwell() async throws {
        var fixture = try JakartaFixture.load()
        fixture.draft.walking = false
        fixture.draft.transit = false
        fixture.oracle = fixture.oracle.filter { $0.mode == "automobile" }.flatMap { original in
            var before = original
            before.end = 7200
            var after = original
            after.start = 7200
            after.seconds = original.seconds.map { $0 * 2 }
            return [before, after]
        }
        let services = try fixture.services()
        let byID = Dictionary(uniqueKeysWithValues: fixture.draft.stops.map { ($0.id, $0) })
        let started = Date()
        let best = try await NativeTripEngine.evaluate(
            JakartaFixture.earlyOrder.map { byID[$0]! },
            draft: fixture.draft, services: services, forecasts: [], progress: { _ in })
        let seconds = Date().timeIntervalSince(started)
        try assertComplete(best, fixture: fixture)
        let late = try XCTUnwrap(best.legs.first { $0.from.id == JakartaFixture.kotaTua })
        XCTAssertEqual(late.departure.timeIntervalSince(fixture.draft.departure), 7812, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(late.chosen?.seconds), 3964, accuracy: 0.001)
        XCTAssertEqual(best.elapsedMinutes * 60, 19310, accuracy: 0.01)
        let p = fixture.problem()
        XCTAssertEqual(
            TripRoutingEvaluator(p).evaluate(fixture.indices(JakartaFixture.earlyOrder, in: p)).finish,
            19310, accuracy: 0.001)
        try fixture.record(
            best, scenario: "synthetic_peak_four_stops", requests: services.directionRequests,
            wallSeconds: seconds, source: "synthetic_time_change_on_recorded_matrix")
    }

    func testTripCrossingMidnightIsNotSilentlyShortened() async throws {
        var fixture = try JakartaFixture.load()
        fixture.draft.departure = fixture.draft.clockDate(minutes: 1380)
        let services = try fixture.services()
        let report = try await NativeTripEngine.plan(
            fixture.draft, services: services, progress: { _ in })
        XCTAssertEqual(report.draft.stops.count, 4)
        XCTAssertNil(report.fastest)
        XCTAssertFalse(report.candidates.contains(where: \.complete))
        XCTAssertTrue(report.candidates.contains { $0.conflicts.contains { $0.contains("satu hari") } })
        XCTAssertLessThanOrEqual(report.requests, 96)
    }
}
