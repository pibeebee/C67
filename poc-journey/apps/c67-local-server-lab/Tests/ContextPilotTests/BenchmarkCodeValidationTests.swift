import Foundation
import XCTest
import PlaceContextEngine
import PlannerEngine

@MainActor final class BenchmarkCodeValidationTests: XCTestCase {
    private let now = PlaceContextDemo.now

    private func request(stopCount: Int) throws -> ContextPlanRequest {
        let day = PlaceContextDemo.day
        let base = ContextClock.day(day)!
        let stops = try (0 ..< stopCount).map { index in
            let id = "validation-stop-\(index)"
            let place = try JSONDecoder().decode(GooglePlace.self, from: PlaceContextDemo.fixture(id: id))
            var visit = VisitContextRequest(placeID: id, day: day)
            visit.identityConfirmed = true
            visit.availableStart = 540
            visit.availableEnd = 1080
            visit.preferredTime = .init(earliest: 1020, latest: 1020)
            return ContextPlanStop(snapshot: .init(place: place, fetchedAt: now, fieldMask: "SYNTHETIC"), request: visit)
        }
        var result = ContextPlanRequest(originID: "origin", returnID: "origin", departure: base.addingTimeInterval(9 * 3600), deadline: base.addingTimeInterval(18 * 3600), stops: stops)
        result.beamWidth = 256
        result.maxTravelCalls = 512
        result.maximumTotalWaitingMinutes = 0
        result.allVisitSlots = true
        return result
    }

    func testThreeOrderCutoffReportsTruncation() async throws {
        var input = try request(stopCount: 3)
        input.policy = .selectiveOrders
        let result = try await ContextItineraryPlanner.plan(input, provider: PlaceContextDemo.FixedTravel(), now: now)
        XCTAssertEqual(result.visits.count, 3)
        XCTAssertTrue(result.searchTruncated, "Only three of six possible orders were evaluated")
    }

    func testVisitOptionShortlistReportsTruncation() async throws {
        var input = try request(stopCount: 1)
        input.allVisitSlots = false
        input.maximumTotalWaitingMinutes = nil
        input.policy = .firstFeasible
        let result = try await ContextItineraryPlanner.plan(input, provider: PlaceContextDemo.FixedTravel(), now: now)
        XCTAssertEqual(result.visits.count, 1)
        XCTAssertTrue(result.searchTruncated, "Only a shortlist of available visit slots was evaluated")
    }

    func testIncompleteBatchPreservesOtherValidDestination() throws {
        let departure = now.addingTimeInterval(86400)
        let valid = LabETAQuery(fromID: "origin", toID: "a", fromLatitude: -6.2, fromLongitude: 106.8, toLatitude: -6.21, toLongitude: 106.81, mode: "automobile", departure: departure)
        var incomplete = valid
        incomplete.toID = "b"
        incomplete.toLatitude = -6.22
        let payload = Data(#"{"etas":[{"destination":{"latitude":-6.21,"longitude":106.81},"transportType":"Automobile","distanceMeters":1000,"expectedTravelTimeSeconds":120},{"destination":{"latitude":-6.22,"longitude":106.81},"transportType":"Automobile"}]}"#.utf8)
        let output = try LabRESTETA.parse(payload, queries: [valid, incomplete])
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(output[0].seconds, 120)
        XCTAssertNil(output[1].seconds)
        XCTAssertEqual(output[1].status, "unavailable")
        XCTAssertTrue(output[1].note.contains("distanceMeters"))
    }
    private final class DirectedTravel: ContextTravelProvider {
        let ids = ["origin", "museum", "gallery", "mandiri", "history", "park"]
        let costs: [[Double]] = [
            [0, 1200, 480, 240, 240, 900],
            [240, 0, 480, 240, 360, 480],
            [1200, 720, 0, 1200, 240, 480],
            [240, 900, 900, 0, 1200, 900],
            [1200, 900, 600, 240, 0, 720],
            [1200, 360, 900, 900, 240, 0]
        ]
        let peak: Date
        var calls = 0

        init(peak: Date) { self.peak = peak }

        func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
            calls += 1
            let seconds = costs[ids.firstIndex(of: from)!][ids.firstIndex(of: to)!]
            return .init(seconds: seconds + (departure >= peak ? 180 : 0), departure: departure, source: "SYNTHETIC directed regression")
        }
    }

    func testCachedPrefixRemainsUsableWithTwelveCallBudget() async throws {
        let day = "2026-11-08"
        let base = ContextClock.day(day)!
        let provider = DirectedTravel(peak: base.addingTimeInterval(14 * 3600))
        let stops = try provider.ids.dropFirst().map { id in
            let bounds = id == "gallery" ? [[480, 720], [780, 930]] : (id == "park" ? [[360, 1200]] : [[540, 1080]])
            let periods = (0 ... 6).flatMap { weekday in
                bounds.map { interval in
                    ["open": ["day": weekday, "hour": interval[0] / 60, "minute": interval[0] % 60],
                     "close": ["day": weekday, "hour": interval[1] / 60, "minute": interval[1] % 60]]
                }
            }
            var object = try JSONSerialization.jsonObject(with: PlaceContextDemo.fixture(id: id)) as! [String: Any]
            object["regularOpeningHours"] = ["periods": periods]
            let place = try JSONDecoder().decode(GooglePlace.self, from: JSONSerialization.data(withJSONObject: object))
            var visit = VisitContextRequest(placeID: id, day: day)
            visit.identityConfirmed = true
            visit.availableStart = 555
            visit.availableEnd = 1140
            visit.durationMinutes = id == "museum" ? 90 : 60
            return ContextPlanStop(snapshot: .init(place: place, fetchedAt: base, fieldMask: "SYNTHETIC"), request: visit)
        }
        var input = ContextPlanRequest(originID: "origin", returnID: "origin", departure: base.addingTimeInterval(555 * 60), deadline: base.addingTimeInterval(19 * 3600), stops: stops)
        input.maximumTotalWaitingMinutes = 30
        input.maxTravelCalls = 12
        input.policy = .firstFeasible
        input.allVisitSlots = true
        let result = try await ContextItineraryPlanner.plan(input, provider: provider, now: base)
        XCTAssertEqual(result.visits.count, 5)
        XCTAssertEqual(result.legs.count, 6)
        XCTAssertEqual(provider.calls, 12)
        XCTAssertEqual(result.travelCalls, provider.calls)
        XCTAssertLessThanOrEqual(result.waitingSeconds, 1800)
    }

}
