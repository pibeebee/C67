import Foundation
import XCTest
@testable import PlaceContextEngine

@MainActor final class RevisionPlanningTests: XCTestCase {
    let now = PlaceContextDemo.now
    func request(_ ids: [String]) throws -> ContextPlanRequest {
        let stops = try ids.map { id -> ContextPlanStop in
            let data = PlaceContextDemo.fixture(id: id)
            let snapshot = PlaceSnapshot(place: try JSONDecoder().decode(GooglePlace.self, from: data), fetchedAt: now, fieldMask: "SYNTHETIC", source: "SYNTHETIC")
            var request = VisitContextRequest(placeID: id, day: PlaceContextDemo.day)
            request.identityConfirmed = true; request.durationMinutes = 30; request.startStepMinutes = 5
            return .init(snapshot: snapshot, request: request)
        }
        let day = ContextClock.day(PlaceContextDemo.day)!
        var input = ContextPlanRequest(originID: "origin", returnID: "origin", departure: day.addingTimeInterval(9 * 3600), deadline: day.addingTimeInterval(17 * 3600), stops: stops)
        input.order = .fixed; input.allVisitSlots = true
        return input
    }
    struct Travel: ContextTravelProvider {
        var transitWait = 0.0
        func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
            .init(seconds: 300 + transitWait, departure: departure, source: "SYNTHETIC", details: .init(mode: "transjakarta", walkingSeconds: 60, transitWaitingSeconds: transitWait))
        }
    }
    func testFixedOrderAndOptionalSubsequenceArePreserved() async throws {
        let input = try request(["synthetic-park", "synthetic-museum"])
        let result = try await OptionalItineraryPlanner.plan(input, requiredIDs: Set(input.stops.map { $0.request.placeID }), provider: Travel(), now: now)
        XCTAssertEqual(result.visits.map(\.placeID), input.stops.map { $0.request.placeID })
        var withClosed = input
        withClosed.stops[0].request.availableStart = 540; withClosed.stops[0].request.availableEnd = 600; withClosed.stops[0].request.durationMinutes = 120
        let optional = try await OptionalItineraryPlanner.plan(withClosed, requiredIDs: ["synthetic-museum"], provider: Travel(), now: now)
        XCTAssertEqual(optional.visits.map(\.placeID), ["synthetic-museum"])
    }
    func testTransitWaitingIncludesReturnWithoutDoubleCountingElapsed() async throws {
        var input = try request(["synthetic-museum"]); input.maximumTotalWaitingMinutes = 15
        let denied = try await ContextItineraryPlanner.plan(input, provider: Travel(transitWait: 600), now: now)
        XCTAssertTrue(denied.visits.isEmpty)
        input.maximumTotalWaitingMinutes = 60
        let result = try await ContextItineraryPlanner.plan(input, provider: Travel(transitWait: 600), now: now)
        XCTAssertFalse(result.visits.isEmpty)
        XCTAssertGreaterThanOrEqual(result.totalWaitingSeconds, 1200)
        XCTAssertEqual(result.elapsedSeconds!, result.travelSeconds + result.waitingSeconds + result.dwellSeconds, accuracy: 0.001)
    }
    func testLegacyJSONDefaultsToOptimizedOrderAndNoTransportDetails() throws {
        let input = try request(["synthetic-museum"])
        let encoded = try ContextJSON.encoder().encode(input)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "order")
        let decoded = try ContextJSON.decoder().decode(ContextPlanRequest.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.order, .optimized)
        let time = try JSONDecoder().decode(ContextTravelTime.self, from: Data(#"{"seconds":60,"departure":0,"source":"old"}"#.utf8))
        XCTAssertNil(time.details)
    }
}
