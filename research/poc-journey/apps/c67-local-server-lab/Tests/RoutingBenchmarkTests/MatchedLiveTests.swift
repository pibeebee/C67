import Foundation
import MapKit
import XCTest
import RoutingBenchmark

@MainActor final class MatchedLiveTests: XCTestCase {
    func query() -> RoutingQuery {
        .init(from: .init(id: "a", revision: "1", point: .init(-6.2, 106.8)), to: .init(id: "b", revision: "1", point: .init(-6.201, 106.801)), mode: .walking, departure: RoutingFixtures.now, geometry: true)
    }
    func value() -> NativeRouteValue { .init(seconds: 120, meters: 150, points: [query().from.point!, query().to.point!]) }
    func testNativeTimeoutWithoutCallbackAndCapCountsDispatch() async throws {
        let provider = AppleNativeRoutingProvider(limit: 1, spacing: .zero)
        provider.timeout = .milliseconds(5); provider.start = { _, _ in }
        do { _ = try await provider.route(query()); XCTFail("Timeout required") }
        catch { XCTAssertEqual(error as? RoutingFailure, .deadlineExceeded) }
        do { _ = try await provider.route(query()); XCTFail("Cap required") }
        catch { XCTAssertEqual(error as? RoutingFailure, .budgetExhausted) }
        XCTAssertEqual(provider.requests, 1)
    }
    func testNativeCancellationAndLateCallbackCannotCompleteNextRequest() async throws {
        let provider = AppleNativeRoutingProvider(spacing: .zero)
        var callback: (@Sendable (Result<NativeRouteValue, RoutingFailure>) -> Void)?
        provider.start = { _, completion in callback = completion }
        let first = Task { try await provider.route(query()) }
        while callback == nil { await Task.yield() }
        let late = callback!; first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled") } catch { XCTAssertTrue(error is CancellationError) }
        callback = nil
        let second = Task { try await provider.route(query()) }
        while callback == nil { await Task.yield() }
        late(.failure(.unavailable))
        callback?(.success(value())); callback?(.failure(.unavailable))
        let result = try await second.value
        XCTAssertEqual(result?.seconds, 120); XCTAssertEqual(provider.requests, 2)
    }
    func testNativeRejectsRemoteSnappingAndReentrantDispatch() async throws {
        let provider = AppleNativeRoutingProvider(spacing: .zero)
        var callback: (@Sendable (Result<NativeRouteValue, RoutingFailure>) -> Void)?
        provider.start = { _, completion in callback = completion }
        let first = Task { try await provider.route(query()) }
        while callback == nil { await Task.yield() }
        do { _ = try await provider.route(query()); XCTFail("Reentrant") }
        catch { XCTAssertEqual(error as? RoutingFailure, .invalidInput) }
        callback?(.success(.init(seconds: 10, meters: 30, points: [.init(-6.3, 106.8), .init(-6.3, 106.801)])))
        do { _ = try await first.value; XCTFail("Remote snap") }
        catch { XCTAssertEqual(error as? RoutingFailure, .invalidResponse) }
    }
    func testGeometryDiagnosticDoesNotPretendToBeDoorAccuracy() throws {
        let a = [RoutingPoint(-6.2, 106.8), RoutingPoint(-6.201, 106.8)]
        XCTAssertEqual(RouteGeometryComparison.medianGap(a, a), 0)
        XCTAssertGreaterThan(try XCTUnwrap(RouteGeometryComparison.medianGap(a, a.map { .init($0.latitude, $0.longitude + 0.001) })), 100)
        XCTAssertNil(RouteGeometryComparison.medianGap([], a))
    }
    func testQueryFingerprintIncludesModeRevisionDepartureAndGeometry() throws {
        let q = query(), original = try MatchedRoadCampaign.fingerprint(q)
        for index in 0 ..< 4 {
            var changed = q
            switch index {
            case 0: changed.mode = .automobile
            case 1: changed.to.revision = "2"
            case 2: changed.departure.addTimeInterval(60)
            default: changed.geometry = false
            }
            XCTAssertNotEqual(try MatchedRoadCampaign.fingerprint(changed), original)
        }
        XCTAssertEqual(try MatchedRoadCampaign.fingerprint(q), original)
    }
    func testMatchedCampaignRepetitionsDirectionsModesAndNoRawExport() async throws {
        let manifest = RoutingManifest(venues: RoutingFixtures.venues)
        let queries = try MatchedRoadCampaign.queries(manifest: manifest, repetitions: 3, smoke: false, departure: RoutingFixtures.now)
        XCTAssertEqual(queries.count, 192)
        XCTAssertEqual(Set(queries.map { $0.0 }).count, 192)
        XCTAssertEqual(queries.filter { $0.1.mode == .walking }.count, 96)
        let apple = SyntheticRoutingProvider(backend: .appleAccess, points: [:])
        let valhalla = SyntheticRoutingProvider(backend: .valhallaAccess, points: [:])
        var checkpoints = 0
        let output = try await MatchedRoadCampaign.run(manifest: manifest, apple: apple, valhalla: valhalla, smoke: true) { _ in checkpoints += 1 }
        XCTAssertEqual(output.rows.count, 4); XCTAssertEqual(checkpoints, 2)
        for comparison in output.comparisons {
            let rows = output.rows.filter { $0.pairID == comparison.pairID }
            XCTAssertEqual(Set(rows.map(\.querySHA256)).count, 1)
            XCTAssertEqual(Set(rows.map(\.order)), [0, 1]); XCTAssertTrue(comparison.bothAvailable)
        }
        let data = try JSONEncoder().encode(output)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("polyline")); XCTAssertFalse(text.contains("latitude")); XCTAssertFalse(text.contains("snappedTo"))
    }
    func testMissingPairNeverExportsETAOrSpeedRatios() async throws {
        let manifest = RoutingManifest(venues: RoutingFixtures.venues)
        let apple = SyntheticRoutingProvider(backend: .appleAccess, points: [:])
        apple.unavailableIDs = [manifest.venues[1].id]
        let valhalla = SyntheticRoutingProvider(backend: .valhallaAccess, points: [:])
        let output = try await MatchedRoadCampaign.run(manifest: manifest, apple: apple, valhalla: valhalla, smoke: true) { _ in }
        XCTAssertTrue(output.comparisons.allSatisfy { !$0.bothAvailable && $0.valhallaToAppleETARatio == nil && $0.valhallaToAppleServiceRatio == nil })
    }

}
