import MapKit
import TripIntegration
import XCTest
@testable import C67JourneyShowcase

@MainActor final class JourneyRoadRoutesTests: XCTestCase {
    private func segment() -> JourneyRoadSegment {
        .init(from: .init(id: "a", name: "A", address: "Jakarta", latitude: -6.195, longitude: 106.823),
              to: .init(id: "b", name: "B", address: "Jakarta", latitude: -6.196, longitude: 106.824), walking: true)
    }
    private func points(_ segment: JourneyRoadSegment) -> [BuswayMapPoint] {
        [.init(latitude: segment.from.latitude, longitude: segment.from.longitude),
         .init(latitude: segment.from.latitude, longitude: segment.to.longitude),
         .init(latitude: segment.to.latitude, longitude: segment.to.longitude)]
    }
    private func settled(_ predicate: () -> Bool) async throws {
        let limit = Date.now.addingTimeInterval(3)
        while !predicate(), Date.now < limit { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(predicate())
    }

    func testTwoMapsShareOneRequestAndReuseItsPolyline() async throws {
        let input = segment(), first = UUID(), second = UUID()
        var calls = 0
        let store = JourneyRoadRoutes(replay: true) { input in calls += 1; return self.points(input) }
        store.subscribe(first, segments: [input]); store.subscribe(second, segments: [input])
        try await settled { store.paths[input.id] != nil }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.paths[input.id]?.count, 3)
        store.release(first)
        XCTAssertNotNil(store.paths[input.id])
        store.release(second)
        store.subscribe(UUID(), segments: [input])
        XCTAssertEqual(calls, 1)
        store.cancel()
    }

    func testFailureKeepsGeometryAbsentAndExplicitRetryCanRecover() async throws {
        let input = segment(), owner = UUID()
        var calls = 0
        let store = JourneyRoadRoutes(replay: true) { input in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return self.points(input)
        }
        store.subscribe(owner, segments: [input])
        try await settled { store.failures[input.id] != nil }
        XCTAssertNil(store.paths[input.id])
        store.retry(owner, segments: [input])
        try await settled { store.paths[input.id] != nil }
        XCTAssertEqual(calls, 2)
        store.cancel()
    }

    func testReleaseDiscardsLateResponseFromUncooperativeRequest() async throws {
        let input = segment(), owner = UUID()
        var pending: CheckedContinuation<[BuswayMapPoint], Never>?
        let store = JourneyRoadRoutes(replay: true) { _ in
            await withCheckedContinuation { pending = $0 }
        }
        store.subscribe(owner, segments: [input])
        try await settled { pending != nil }
        store.release(owner)
        pending?.resume(returning: points(input))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(store.paths[input.id])
        XCTAssertNil(store.failures[input.id])
    }

    func testWrongEndpointsAndInvalidCoordinatesAreRejected() {
        let input = segment()
        XCTAssertThrowsError(try JourneyRoadRoutes.validate([.init(latitude: 0, longitude: 0), .init(latitude: 1, longitude: 1)], for: input))
        XCTAssertThrowsError(try JourneyRoadRoutes.validate([.init(latitude: .nan, longitude: 106.8)], for: input))
        XCTAssertNoThrow(try JourneyRoadRoutes.validate(points(input), for: input))
    }

    func testMissingNativeCallbackTimesOutAndLateCallbackCannotFinishAnotherRequest() async throws {
        let input = segment(), operation = JourneyRoadOperation()
        operation.timeout = .milliseconds(5)
        var late: (@Sendable (Result<[BuswayMapPoint], any Error>) -> Void)?
        operation.start = { _, callback in late = callback }
        do { _ = try await operation.calculate(input); XCTFail("Expected a bounded timeout") }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        let prior = late
        operation.start = { _, callback in
            prior?(.success(self.points(input)))
            callback(.failure(URLError(.badServerResponse)))
        }
        do { _ = try await operation.calculate(input); XCTFail("Expected the current request's failure") }
        catch { XCTAssertEqual((error as? URLError)?.code, .badServerResponse) }
    }

    func testNativeCancellationCompletesWithoutCallback() async throws {
        let input = segment(), operation = JourneyRoadOperation()
        var started = false
        operation.start = { _, _ in started = true }
        let task = Task { try await operation.calculate(input) }
        try await settled { started }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
