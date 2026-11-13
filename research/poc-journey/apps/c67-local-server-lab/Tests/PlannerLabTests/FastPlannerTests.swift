import Foundation
import XCTest
@testable import PlannerEngine
import PlannerContracts

@MainActor final class FastPlannerTests: XCTestCase {
    func draft() -> NativeTripDraft {
        var d = NativeTripDraft.jakarta(now: LabMatrix.now)
        d.departure = TripClock.date("2026-11-07T00:00:00Z")
        d.finishBy = TripClock.date("2026-11-07T12:00:00Z")
        d.origin = .init(id: "origin", title: "Bundaran HI", query: "origin", latitude: -6.195, longitude: 106.823)
        d.end = d.origin; d.returnsToOrigin = true
        d.stops = (0 ..< 3).map { i in
            .init(point: .init(id: "s\(i)", title: "Stop\(i)", query: "stop\(i)",
                               latitude: -6.2 - Double(i) * 0.01, longitude: 106.83 + Double(i) * 0.01), role: .visit,
                  dwellOverride: 60, exposure: .indoor,
                  opening: .init(opensMinute: 420, closesMinute: 1140))
        }
        return d
    }
    func services() -> NativeTripAppleServices {
        let s = NativeTripAppleServices(logs: NativeTripLogStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("DFault-\(UUID())")))
        s.integrationForecasts = []
        s.integrationVisitStart = { _, arrival in
            let epoch = arrival.timeIntervalSince1970
            return Date(timeIntervalSince1970: ceil(epoch / 900) * 900)
        }
        return s
    }
    func testSurrogateNeverBecomesReturnedETAAndEachDepartureFollowsActualVisit() async throws {
        let d = draft(); let s = services(); var observed: [Date] = []
        s.integrationETA = { a, b, mode, date in
            observed.append(date)
            return .init(id: a.id + ">" + b.id, mode: mode, seconds: 123,
                         distance: a.distance(to: b), expectedDeparture: date,
                         expectedArrival: date.addingTimeInterval(123), status: "available", note: "TEST provider actual123")
        }
        let report = try await LabFastPlanner.plan(d, services: s, progress: { _ in })
        let chosen = try XCTUnwrap(report.fastest)
        XCTAssertTrue(chosen.feasible); XCTAssertEqual(report.requests, 4)
        XCTAssertTrue(chosen.legs.allSatisfy { $0.chosen?.seconds == 123 && $0.chosen?.note == "TEST provider actual123" })
        XCTAssertEqual(observed.first, d.departure)
        for (a, b) in zip(chosen.legs, chosen.legs.dropFirst()) { XCTAssertEqual(a.leave, b.departure) }
    }
    func testMisestimatedEdgeTriggersRepairInsteadOfReturningInvalidSchedule() async throws {
        let d = draft(); let s = services()
        let first = LabFastPlanner.permutations(d.stops).map { LabFastPlanner.estimate($0, draft: d, visitStart: s.integrationVisitStart, forecasts: []) }.min(by: LabFastPlanner.ranked)!.order[0].id
        s.integrationETA = { a, b, mode, date in
            let seconds = a.id == "origin" && b.id == first ? 20 * 3600.0 : 120.0
            return .init(id: a.id + ">" + b.id, mode: mode, seconds: seconds, distance: 1000,
                         expectedDeparture: date, expectedArrival: date.addingTimeInterval(seconds), status: "available", note: "TEST asymmetric provider")
        }
        let report = try await LabFastPlanner.plan(d, services: s, progress: { _ in })
        XCTAssertEqual(report.candidates.count, 2)
        XCTAssertFalse(report.candidates[0].feasible)
        XCTAssertTrue(try XCTUnwrap(report.fastest).feasible)
        XCTAssertNotEqual(report.fastest?.order.first, first)
    }
    func testUnavailableProviderNeverBecomesInfeasibilityProofOrZeroTravel() async throws {
        let s = services()
        s.integrationETA = { a, b, m, date in .init(id: a.id + ">" + b.id, mode: m, status: "unavailable", note: "TEST provider failure") }
        let report = try await LabFastPlanner.plan(draft(), services: s, progress: { _ in })
        XCTAssertEqual(report.requests, 1); XCTAssertEqual(report.candidates.count, 1)
        XCTAssertFalse(try XCTUnwrap(report.fastest).feasible)
        XCTAssertNil(report.fastest?.legs.first?.chosen)
    }
    func testFailedSchedulesStopAtThreeValidationsAndPreserveAllDestinations() async throws {
        let s = services()
        s.integrationETA = { a, b, m, date in .init(id: a.id + ">" + b.id, mode: m, seconds: 20 * 3600, distance: 1000,
                                                    expectedDeparture: date, expectedArrival: date.addingTimeInterval(20 * 3600), status: "available", note: "TEST impossible travel") }
        let report = try await LabFastPlanner.plan(draft(), services: s, progress: { _ in })
        XCTAssertEqual(report.candidates.count, 3)
        XCTAssertTrue(report.candidates.allSatisfy { !$0.feasible && Set($0.order) == Set(["s0", "s1", "s2"]) })
    }
    func testFullStayPolicyCanRejectAllCandidatesWithoutRemovingStops() async throws {
        let s = services(); s.integrationVisitStart = { _, _ in nil }
        s.integrationETA = { a, b, m, date in .init(id: a.id + ">" + b.id, mode: m, seconds: 120, distance: 1000,
                                                    expectedDeparture: date, expectedArrival: date.addingTimeInterval(120), status: "available", note: "TEST") }
        let report = try await LabFastPlanner.plan(draft(), services: s, progress: { _ in })
        XCTAssertFalse(try XCTUnwrap(report.fastest).feasible)
        XCTAssertTrue(report.candidates.allSatisfy { !$0.conflicts.isEmpty })
    }
    func testFirstFeasibleCanLoseQualityWhenPriorIsWrongAndDoesNotClaimOptimality() async throws {
        let d = draft(); let s = services()
        let estimated = LabFastPlanner.permutations(d.stops).map { LabFastPlanner.estimate($0, draft: d,
                                                                                           visitStart: s.integrationVisitStart, forecasts: []) }.min(by: LabFastPlanner.ranked)!.order
        let expensiveFirst = estimated[0].id
        s.integrationETA = { a, b, m, date in
            let seconds = a.id == "origin" && b.id == expensiveFirst ? 3600.0 : 60.0
            return .init(id: a.id + ">" + b.id, mode: m, seconds: seconds, distance: 1000,
                         expectedDeparture: date, expectedArrival: date.addingTimeInterval(seconds), status: "available", note: "TEST asymmetric road")
        }
        let report = try await LabFastPlanner.plan(d, services: s, progress: { _ in })
        let first = try XCTUnwrap(report.fastest)
        XCTAssertTrue(first.feasible)
        var alternative = estimated; alternative.swapAt(0, 1)
        let other = try await NativeTripEngine.evaluate(alternative, draft: d, services: s, forecasts: [], progress: { _ in })
        XCTAssertTrue(other.feasible)
        XCTAssertGreaterThan(first.elapsedMinutes, other.elapsedMinutes)
        XCTAssertEqual(report.candidates.count, 1, "First feasible is intentionally bounded, not an optimum claim")
        XCTAssertTrue(report.optimizerNote?.contains("can lose objective quality") == true)
    }
    func testEnumeratesAllSixStopOrdersWithinDeclaredBound() {
        let stops = draft().stops
        let six = (0 ..< 6).map { i -> NativeTripStop in var x = stops[i % 3]; x.point.id = "unique\(i)"; return x }
        let result = LabFastPlanner.permutations(six)
        XCTAssertEqual(result.count, 720); XCTAssertEqual(Set(result.map { $0.map(\.id) }).count, 720)
    }
}
