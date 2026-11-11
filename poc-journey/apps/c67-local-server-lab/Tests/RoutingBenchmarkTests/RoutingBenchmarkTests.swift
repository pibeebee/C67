import Foundation
import XCTest
import PlaceContextEngine
import RoutingBenchmark
import TripIntegration

@MainActor final class RoutingBenchmarkTests: XCTestCase {
    let point = RoutingPoint(-6.2, 106.8)
    func endpoint(_ id: String = "a", revision: String = "1") -> RoutingEndpoint { .init(id: id, revision: revision, point: point) }
    func query() -> RoutingQuery { .init(from: endpoint(), to: endpoint("b"), mode: .walking, departure: RoutingFixtures.now) }
    final class HTTP: PlacesHTTPTransport {
        var calls: [URLRequest] = []
        var status = 200
        var object: Any = [:]
        var timeout = false
        func send(_ request: URLRequest) async throws -> PlacesHTTPResponse {
            calls.append(request)
            if timeout { throw URLError(.timedOut) }
            return .init(status: status, data: try JSONSerialization.data(withJSONObject: object))
        }
    }
    func testBudgetReservesFailedCallsAndRejectsBeforeDispatch() throws {
        let budget = try RoutingBudget(requestLimit: 2, elementLimit: 3)
        try budget.reserve(elements: 2)
        XCTAssertThrowsError(try budget.reserve(elements: 2))
        XCTAssertEqual(budget.requests, 1)
        try budget.reserve(elements: 1)
        XCTAssertThrowsError(try budget.reserve())
        XCTAssertEqual(budget.elements, 3)
        XCTAssertThrowsError(try RoutingBudget(requestLimit: 201))
    }
    func testGoogleLiveIsDisabledEvenIfAKeyIsPresent() async throws {
        let rows = try await RoutingLiveCampaign.run(manifest: .init(venues: Array(RoutingFixtures.venues.prefix(2))), environment: ["GOOGLE_ROUTES_API_KEY": "synthetic-key-must-not-trigger-network"], probe: false)
        let google = rows.filter { $0.backend == RouteBackend.googlePlaceID.rawValue }
        XCTAssertFalse(google.isEmpty)
        XCTAssertTrue(google.allSatisfy { $0.outcome == RoutingFailure.disabledByScope.rawValue && $0.calls == 0 && $0.evidenceMode == "LIVE_PREFLIGHT" })
    }
    func testAccessMustBePublicFreshAndCorrectForMode() throws {
        var venue = RoutingFixtures.venues[0]
        XCTAssertThrowsError(try venue.endpoint(backend: .valhallaAccess, mode: .walking, now: RoutingFixtures.now))
        let good = try venue.endpoint(backend: .valhallaAccess, mode: .walking, now: RoutingFixtures.now, synthetic: true)
        XCTAssertEqual(good.revision, "door-0:1")
        venue.accesses[0].publicAccess = false
        XCTAssertThrowsError(try venue.endpoint(backend: .valhallaAccess, mode: .walking, now: RoutingFixtures.now, synthetic: true))
        XCTAssertNoThrow(try venue.endpoint(backend: .valhallaAccess, mode: .automobile, now: RoutingFixtures.now, synthetic: true))
        venue.accesses[1].checkedAt = RoutingFixtures.now.addingTimeInterval(-31 * 86400)
        XCTAssertThrowsError(try venue.endpoint(backend: .valhallaAccess, mode: .automobile, now: RoutingFixtures.now, synthetic: true))
    }
    func testPOIPinCannotBecomeAnEntranceAndDistanceDoesNotCertifyConnectivity() throws {
        var venue = RoutingFixtures.venues[0]; venue.accesses = []
        XCTAssertThrowsError(try venue.endpoint(backend: .valhallaAccess, mode: .walking, now: RoutingFixtures.now))
        let result = try RoutingResult(query: query(), seconds: 30, meters: 10, snappedTo: point, source: "SYNTHETIC", traffic: "none")
        XCTAssertEqual(AccessEvaluation.status(venue: venue, result: result, selectionSource: nil), "unverified")
        venue.reference = .init(id: "ref", point: point, kind: .pedestrianEntrance, modes: [.walking], publicAccess: true, sourceURL: "https://example.invalid/reference", checkedAt: RoutingFixtures.now, status: .sourceSupported)
        XCTAssertEqual(AccessEvaluation.status(venue: venue, result: result, selectionSource: venue.reference!.sourceURL), "same_source_consistency_only")
        XCTAssertEqual(AccessEvaluation.status(venue: venue, result: result, selectionSource: "https://example.invalid/other"), "near_reference_connectivity_unverified")
    }
    func testGoogleUsesPlaceIDAndOmitsDriveTrafficForWalking() async throws {
        let http = HTTP(); http.object = ["routes": [["duration": "120s", "distanceMeters": 100, "legs": [["startLocation": ["latLng": ["latitude": -6.2, "longitude": 106.8]], "endLocation": ["latLng": ["latitude": -6.2, "longitude": 106.8]]]]]]]
        let provider = try GoogleRoutingProvider(key: "SYNTHETIC-KEY", budget: .init(), http: http)
        var request = query(); request.to = .init(id: "b", revision: "google", point: nil, googlePlaceID: "ChIJsynthetic")
        let result = try await provider.route(request)
        XCTAssertEqual(result?.seconds, 120)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: http.calls[0].httpBody!) as? [String: Any])
        XCTAssertEqual((body["destination"] as? [String: String])?["placeId"], "ChIJsynthetic")
        XCTAssertNil(body["routingPreference"]); XCTAssertNil(body["departureTime"])
        XCTAssertFalse(http.calls[0].url!.absoluteString.contains("SYNTHETIC-KEY"))
    }
    func testGooglePartialMatrixKeepsMissingAndFailedCellsUnknown() async throws {
        let http = HTTP(); http.object = [["originIndex": 0, "destinationIndex": 0, "status": [:], "condition": "ROUTE_EXISTS", "duration": "60s"], ["originIndex": 0, "destinationIndex": 1, "status": ["code": 5]]]
        let budget = try RoutingBudget()
        let provider = try GoogleRoutingProvider(key: "synthetic", budget: budget, http: http)
        let values = try await provider.matrix(sources: [endpoint()], targets: [endpoint("b"), endpoint("c"), endpoint("d")], mode: .walking, departure: RoutingFixtures.now)
        XCTAssertEqual(values[0][0], 60); XCTAssertNil(values[0][1]); XCTAssertNil(values[0][2])
        XCTAssertEqual(budget.elements, 3)
        http.object = [["originIndex": 0, "destinationIndex": 0], ["originIndex": 0, "destinationIndex": 0]]
        do { _ = try await provider.matrix(sources: [endpoint()], targets: [endpoint()], mode: .walking, departure: RoutingFixtures.now); XCTFail("Duplicate indices") } catch { XCTAssertEqual(error as? RoutingFailure, .invalidResponse) }
    }
    func testAuthenticationAndQuotaAreNotRetriedAndConsumeBudget() async throws {
        for status in [403, 429, 500] {
            let http = HTTP(); http.status = status
            let budget = try RoutingBudget(requestLimit: 1)
            let provider = try GoogleRoutingProvider(key: "synthetic", budget: budget, http: http)
            do { _ = try await provider.route(query()); XCTFail("Failure required") } catch {}
            do { _ = try await provider.route(query()); XCTFail("Budget required") } catch { XCTAssertEqual(error as? RoutingFailure, .budgetExhausted) }
            XCTAssertEqual(http.calls.count, 1); XCTAssertEqual(budget.requests, 1)
        }
    }
    func testTimeoutIsClassifiedWithoutRawURLOrRetry() async throws {
        let http = HTTP(); http.timeout = true
        let budget = try RoutingBudget()
        let provider = try GoogleRoutingProvider(key: "synthetic-secret-never-exported", budget: budget, http: http)
        do { _ = try await provider.route(query()); XCTFail("Timeout") }
        catch { XCTAssertEqual(error as? RoutingFailure, .deadlineExceeded) }
        XCTAssertEqual(http.calls.count, 1); XCTAssertEqual(budget.requests, 1)
    }
    final class LateProvider: RoutingProvider {
        let name = "SYNTHETIC late provider"
        var continuation: CheckedContinuation<RoutingResult?, Never>?
        var pendingQuery: RoutingQuery?
        func route(_ query: RoutingQuery) async throws -> RoutingResult? {
            pendingQuery = query
            return await withCheckedContinuation { continuation = $0 }
        }
    }
    func testUncooperativeLateResultIsRejectedAfterGenerationChanges() async throws {
        let base = LateProvider()
        let owner = RoutingMemo(base: base)
        let pending = Task { try await owner.route(query()) }
        while base.continuation == nil { await Task.yield() }
        owner.invalidate()
        let result = try RoutingResult(query: try XCTUnwrap(base.pendingQuery), seconds: 30, meters: 10, source: "SYNTHETIC", traffic: "none")
        base.continuation?.resume(returning: result)
        do { _ = try await pending.value; XCTFail("Stale generation") }
        catch { XCTAssertEqual(error as? RoutingFailure, .staleResult) }
        XCTAssertEqual(owner.hits, 0)
    }
    func testMemoIncludesRevisionModeDepartureAndCoalescesRequests() async throws {
        let base = SyntheticRoutingProvider(backend: .appleAccess, points: [:]); base.delay = .milliseconds(5)
        let memo = RoutingMemo(base: base)
        let q = query()
        async let a = memo.route(q)
        async let b = memo.route(q)
        _ = try await (a, b)
        XCTAssertEqual(base.calls, 1)
        var revised = q; revised.to.revision = "2"; _ = try await memo.route(revised)
        revised.mode = .automobile; _ = try await memo.route(revised)
        revised.departure.addTimeInterval(1); _ = try await memo.route(revised)
        XCTAssertEqual(base.calls, 4)
    }
    func testInvalidatedOrCancelledWorkCannotPopulateMemo() async throws {
        let base = SyntheticRoutingProvider(backend: .appleAccess, points: [:]); base.delay = .milliseconds(25)
        let memo = RoutingMemo(base: base)
        let pending = Task { try await memo.route(query()) }
        try await Task.sleep(for: .milliseconds(2)); memo.invalidate()
        do { _ = try await pending.value; XCTFail("Stale result required") } catch {}
        XCTAssertEqual(memo.hits, 0)
        _ = try await memo.route(query()); XCTAssertEqual(base.calls, 2)
    }
    func testFixedOrderAndClosedOptionalArePreservedByFinalists() async throws {
        var request = try RoutingFixtures.request(ids: ["synthetic-2", "synthetic-0", "synthetic-1"], fixed: true)
        request.stops[1].request.availableStart = 540; request.stops[1].request.availableEnd = 550
        let provider = PlaceContextDemo.FixedTravel()
        let result = try await FinalistRoutingPlanner.plan(request, required: ["synthetic-2", "synthetic-1"], provider: provider, points: [:], now: RoutingFixtures.now)
        XCTAssertEqual(result.visits.map(\.placeID), ["synthetic-2", "synthetic-1"])
        let rejected = try await FinalistRoutingPlanner.plan(request, required: Set(request.stops.map { $0.request.placeID }), provider: provider, points: [:], now: RoutingFixtures.now)
        XCTAssertTrue(rejected.visits.isEmpty)
    }
    func testReturnDeadlineAndEmptyDraftCannotBeBypassed() async throws {
        var request = try RoutingFixtures.request(ids: ["synthetic-0"], fixed: true)
        request.deadline = request.departure.addingTimeInterval(40 * 60)
        let result = try await FinalistRoutingPlanner.plan(request, required: ["synthetic-0"], provider: PlaceContextDemo.FixedTravel(), points: [:], now: RoutingFixtures.now)
        XCTAssertTrue(result.visits.isEmpty)
        request.stops = []
        do { _ = try await FinalistRoutingPlanner.plan(request, required: [], provider: PlaceContextDemo.FixedTravel(), points: [:], now: RoutingFixtures.now); XCTFail("Empty draft") } catch {}
    }
    func testWrongPriorCanMissBetterScheduleWithoutClaimingAnOptimum() async throws {
        var input = try RoutingFixtures.request(ids: (0 ..< 4).map { "synthetic-\($0)" })
        input.beamWidth = 64; input.maxTravelCalls = 512; input.allVisitSlots = false
        let required = Set(input.stops.map(\.request.placeID))
        let baseline = try await OptionalItineraryPlanner.plan(input, requiredIDs: required, provider: RoutingFixtures.WrongPriorTravel(), now: RoutingFixtures.now)
        let fast = try await FinalistRoutingPlanner.plan(input, required: required, provider: RoutingFixtures.WrongPriorTravel(), points: [:], now: RoutingFixtures.now)
        XCTAssertEqual(fast.visits.count, 4)
        XCTAssertGreaterThan(try XCTUnwrap(fast.elapsedSeconds), try XCTUnwrap(baseline.elapsedSeconds))
        XCTAssertTrue(fast.searchTruncated)
    }
    func testUnavailableTravelIsNeverZeroAndBudgetRemainsBounded() async throws {
        let base = SyntheticRoutingProvider(backend: .valhallaAccess, points: [:]); base.unavailableIDs = ["b"]
        let memo = RoutingMemo(base: base, limit: 1)
        let first = try await memo.route(query()); let second = try await memo.route(query())
        XCTAssertNil(first); XCTAssertNil(second); XCTAssertEqual(base.calls, 1)
        var revised = query(); revised.to.id = "c"
        do { _ = try await memo.route(revised); XCTFail("Budget") } catch { XCTAssertEqual(error as? RoutingFailure, .budgetExhausted) }
    }
    func testValhallaRejectsRemoteHostAndMalformedOrUncorrelatedShape() async throws {
        XCTAssertThrowsError(try ValhallaRoutingProvider(baseURL: URL(string: "http://example.com")!))
        let http = HTTP(); http.object = ["trip": ["status": 0, "units": "kilometers", "summary": ["time": 30, "length": 0.1], "legs": [["shape": "?"]]]]
        let provider = try ValhallaRoutingProvider(baseURL: URL(string: "http://127.0.0.1:8002")!, http: http)
        do { _ = try await provider.route(query()); XCTFail("Invalid polyline") } catch { XCTAssertEqual(error as? RoutingFailure, .invalidResponse) }
        XCTAssertEqual(http.calls.count, 1)
    }
    func testReportedPercentilesExcludeInvalidValuesAndRetainSampleMeaning() {
        XCTAssertEqual(RoutingStatistics.percentile([1, 2, 3, 4, 5], fraction: 0.5), 3)
        XCTAssertEqual(RoutingStatistics.percentile([1, 2, 3, 4, 5], fraction: 0.95), 5)
        XCTAssertNil(RoutingStatistics.percentile([], fraction: 0.95))
    }
    func testSharedTransitDirectTransferDirectionAndNoCarFallback() async throws {
        let rows = try await RoutingTransitFixtures.run()
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.allSatisfy { $0.outcome == "expected_match" && $0.arithmeticValid })
    }
    func testTransitRejectsStaleFeedAndNewWalkingEvidenceKeepsValidation() async throws {
        let feed = try RoutingTransitFixtures.feed(transfer: false)
        let now = feed.source.checkedAt.addingTimeInterval(1)
        let base = SyntheticRoutingProvider(backend: .valhallaAccess, points: [:])
        let walking = try RoutingWalkingAdapter(provider: base, provenance: "synthetic_walking")
        XCTAssertThrowsError(try RoutingTransitAdapter(endpoints: RoutingTransitFixtures.endpoints(feed), feed: feed, walking: walking, now: now.addingTimeInterval(8 * 86400)))
        XCTAssertThrowsError(try RoutingWalkingAdapter(provider: base, provenance: "unattributed_unknown"))
        let service = try BuswayRoutingService(feed: feed, walking: walking, now: now)
        let start = try XCTUnwrap(feed.stops.first { $0.id == "G00031" })
        let finish = try XCTUnwrap(feed.stops.first { $0.id == "P00017" })
        let routed = try await service.route(from: start.pin, to: finish.pin, departure: now)
        var journey = try XCTUnwrap(routed)
        journey.access.provider = "valhalla_osm_walking"; journey.egress?.provider = "google_routes_walking"
        XCTAssertNoThrow(try journey.validate())
        journey.access.provider = "unattributed_unknown"
        XCTAssertThrowsError(try journey.validate())
    }
}
