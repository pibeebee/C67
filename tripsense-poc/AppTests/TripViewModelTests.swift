import XCTest
@testable import TripSensePOC

@MainActor final class TripViewModelTests: XCTestCase {
    func testFixtureGenerationAndRemovalRecalculate() async throws {
        let model = TripViewModel()
        model.demo = true; model.theme = .mixed; model.count = 4
        model.generate()
        for _ in 0 ..< 100 where model.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.itinerary?.stops.count, 4)
        XCTAssertTrue(model.isDemoResult)
        let stop = try XCTUnwrap(model.itinerary?.stops.first)
        model.remove(stop)
        for _ in 0 ..< 100 where model.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.itinerary?.stops.count, 3)
        XCTAssertFalse(model.itinerary!.stops.contains { $0.id == stop.id })
    }
    func testLockedCandidateIsPreservedAfterReoptimization() async throws {
        let model = TripViewModel()
        model.demo = true; model.theme = .mixed; model.count = 3
        model.generate()
        for _ in 0 ..< 100 where model.busy { try await Task.sleep(for: .milliseconds(10)) }
        let excluded = try XCTUnwrap(model.candidatePlaces.first { candidate in
            !((model.itinerary?.stops ?? []).contains { $0.id == candidate.id })
        })
        model.setLocked(excluded.id, locked: true)
        model.reoptimize()
        for _ in 0 ..< 100 where model.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(model.error)
        XCTAssertTrue(model.itinerary?.stops.contains { $0.id == excluded.id } ?? false)
    }
    func testCancellationDoesNotApplyStaleResult() async throws {
        let model = TripViewModel()
        model.demo = true
        model.generate(); model.cancel()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(model.itinerary)
        XCTAssertFalse(model.busy)
    }
}
