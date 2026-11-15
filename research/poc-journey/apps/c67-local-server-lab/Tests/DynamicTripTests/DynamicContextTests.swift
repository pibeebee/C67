import Foundation
import XCTest
import PlaceContextEngine
import DynamicTripContracts
@testable import DynamicTripEngine

@MainActor final class DynamicContextTests: XCTestCase {
    func testWeatherChangesOrderAndRetainsFullVisits() async throws {
        let morning = try await ContextExperiments.run("rain_morning")
        let afternoon = try await ContextExperiments.run("rain_afternoon")
        XCTAssertEqual(morning.output.itinerary.visits.count, 3)
        XCTAssertEqual(afternoon.output.itinerary.visits.count, 3)
        XCTAssertNotEqual(morning.output.itinerary.visits.map(\.placeID), afternoon.output.itinerary.visits.map(\.placeID))
        for output in [morning, afternoon] {
            XCTAssertLessThanOrEqual(output.output.itinerary.waitingSeconds, 1800)
            for visit in output.output.itinerary.visits { XCTAssertEqual(visit.visit.end.timeIntervalSince(visit.visit.start), 3600) }
        }
    }
    func testEarlyClosingPlaceComesFirstAndClosedPlaceBlocks() async throws {
        let early = try await ContextExperiments.run("early_close")
        XCTAssertEqual(early.output.itinerary.visits.first?.placeID, "museum")
        let closed = try await ContextExperiments.run("closed")
        XCTAssertEqual(closed.output.itinerary.status, "needs_context")
        XCTAssertEqual(closed.output.itinerary.travelCalls, 0)
    }
    func testMissingForecastAndExposureStayUnknown() async throws {
        for id in ["weather_missing", "weather_stale", "exposure_unknown"] {
            let value = try await ContextExperiments.run(id)
            XCTAssertEqual(value.output.itinerary.status, "candidate_with_unknown_preferences")
            XCTAssertTrue(value.output.itinerary.visits.contains { !$0.visit.unknowns.isEmpty })
        }
    }
    func testFinerStartGridChangesFiveStopWaitingFeasibility() async throws {
        let quarterHour = try await ContextExperiments.run("five_grid15")
        let fiveMinutes = try await ContextExperiments.run("five_grid5")
        XCTAssertTrue(quarterHour.output.itinerary.visits.isEmpty)
        XCTAssertEqual(fiveMinutes.output.itinerary.visits.count, 5)
        XCTAssertLessThanOrEqual(fiveMinutes.output.itinerary.waitingSeconds, 1800)
        XCTAssertEqual(fiveMinutes.output.itinerary.dwellSeconds, 5 * 3600)
    }
    func testLegacyVisitRequestKeepsFifteenMinuteGrid() throws {
        let request = try ContextJSON.decoder().decode(VisitContextRequest.self, from: Data(#"{"placeID":"sample","day":"2026-11-08"}"#.utf8))
        XCTAssertEqual(request.startStepMinutes, 15)
        var invalid = request; invalid.startStepMinutes = 7
        XCTAssertThrowsError(try invalid.validate())
    }
}
