import XCTest
import Foundation
import ContextPilotAdapters
import PlannerEngine
import PlaceContextEngine

@MainActor final class ContextPilotTests: XCTestCase {
    let now = PlaceContextDemo.now
    final class Spy: LabETAProvider {
        var metrics = LabProviderMetrics(); var wrongDeparture = false; var forbidden = false
        func values(_ queries: [LabETAQuery]) async throws -> [LabETAValue] {
            metrics.calls += 1; metrics.cells += queries.count; metrics.requests.append(queries)
            if forbidden { return queries.map { .init(query: $0, status: "unavailable", note: "Provider HTTP 403; retry-after=absent") } }
            var q = queries[0]
            if wrongDeparture { q.departure = q.departure.addingTimeInterval(60) }
            return [.init(query: q, seconds: 600, distance: 1000)]
        }
    }
    func identities() -> [PilotIdentity] {
        ["origin", "park"].enumerated().map { i, id in
            var pin = PlacePin(id: "apple-" + id, name: id, address: "Jakarta", latitude: -6.2 + Double(i) / 100, longitude: 106.83)
            pin.source = "Apple Maps Server API"
            return .init(internalID: id, googlePlaceID: id == "park" ? "different-google-id" : nil, applePin: pin, evidence: "independent Apple match", confirmedAt: now)
        }
    }
    func testAdapterUsesAppleCoordinatesAndExactDeparture() async throws {
        let spy = Spy(); let a = try AppleContextTravelAdapter(identities: identities(), provider: spy, now: now)
        let departure = now.addingTimeInterval(86400)
        let value = try await a.travel(from: "origin", to: "park", departure: departure)
        XCTAssertEqual(value?.seconds, 600); XCTAssertEqual(value?.departure, departure)
        let q = try XCTUnwrap(spy.metrics.requests.first?.first)
        XCTAssertEqual(q.toLatitude, -6.19, accuracy: 0.000001); XCTAssertEqual(q.toID, "park")
        XCTAssertEqual(q.departure, departure)
    }
    func testMismatchedDepartureIsUnavailable() async throws {
        let spy = Spy(); spy.wrongDeparture = true
        let a = try AppleContextTravelAdapter(identities: identities(), provider: spy, now: now)
        let value = try await a.travel(from: "origin", to: "park", departure: now)
        XCTAssertNil(value)
    }
    func testMissingMappingFailsBeforeProvider() async throws {
        let spy = Spy(); let a = try AppleContextTravelAdapter(identities: identities(), provider: spy, now: now)
        do { _ = try await a.travel(from: "unknown", to: "park", departure: now); XCTFail("Missing mapping accepted") } catch {}
        XCTAssertEqual(spy.metrics.calls, 0)
    }
    func testStaleOrDuplicateIdentityRejected() throws {
        var ids = identities(); ids[0].confirmedAt = now.addingTimeInterval(-86401)
        XCTAssertThrowsError(try AppleContextTravelAdapter(identities: ids, provider: Spy(), now: now))
        XCTAssertThrowsError(try AppleContextTravelAdapter(identities: identities() + identities(), provider: Spy(), now: now))
    }
    func input(required: Bool)throws -> ContextPlanRequest {
        let id = "synthetic-park"
        let place = try JSONDecoder().decode(GooglePlace.self, from: PlaceContextDemo.fixture(id: id))
        let snapshot = PlaceSnapshot(place: place, fetchedAt: now, fieldMask: "SYNTHETIC")
        var request = VisitContextRequest(placeID: id, day: PlaceContextDemo.day); request.identityConfirmed = true
        request.preferredTime = .init(earliest: 900, latest: 960, required: required)
        let base = ContextClock.day(request.day)!
        var input = ContextPlanRequest(originID: "origin", returnID: "origin", departure: base.addingTimeInterval(11 * 3600), deadline: base.addingTimeInterval(18 * 3600), stops: [.init(snapshot: snapshot, request: request)])
        input.maximumTotalWaitingMinutes = 30; input.allVisitSlots = true
        return input
    }
    func testSoftTimeCannotOverrideHardWaitingCap() async throws {
        for policy in ContextSearchPolicy.allCases {
            var i = try input(required: false); i.policy = policy
            let r = try await ContextItineraryPlanner.plan(i, provider: PlaceContextDemo.FixedTravel(), now: now)
            XCTAssertFalse(r.visits.isEmpty); XCTAssertLessThanOrEqual(r.waitingSeconds, 1800)
            XCTAssertGreaterThan(r.penaltyByPriority[0], 0)
        }
    }
    func testConflictingRequiredTimeAndWaitingCapReturnsNoCandidate() async throws {
        let r = try await ContextItineraryPlanner.plan(input(required: true), provider: PlaceContextDemo.FixedTravel(), now: now)
        XCTAssertTrue(r.visits.isEmpty); XCTAssertEqual(r.status, "no_candidate_within_search")
    }
    func testOlderRequestDecodesWithCompatibleDefaults() throws {
        let data = try ContextJSON.encoder().encode(input(required: false))
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["maximumTotalWaitingMinutes", "policy", "allVisitSlots"] { object.removeValue(forKey: key) }
        let value = try ContextJSON.decoder().decode(ContextPlanRequest.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(value.maximumTotalWaitingMinutes); XCTAssertEqual(value.policy, .beam); XCTAssertFalse(value.allVisitSlots)
    }
    func testFourCellBudgetReservesContinuationAndReturn() async throws {
        var i = try input(required: false)
        let original = i.stops[0]
        i.stops = (0 ..< 3).map { index in
            var stop = original; stop.request.placeID = "stop-\(index)"; stop.snapshot.place.id = stop.request.placeID
            stop.request.preferredTime = nil; return stop
        }
        i.maxTravelCalls = 4
        for policy in ContextSearchPolicy.allCases {
            i.policy = policy
            let r = try await ContextItineraryPlanner.plan(i, provider: PlaceContextDemo.FixedTravel(), now: now)
            XCTAssertEqual(r.visits.count, 3); XCTAssertEqual(r.legs.count, 4); XCTAssertEqual(r.travelCalls, 4)
        }
    }

    func testForbiddenProviderStopsInsteadOfRepeatingUnavailableLegs() async throws {
        let spy = Spy(); spy.forbidden = true
        let adapter = try AppleContextTravelAdapter(identities: identities(), provider: spy, now: now)
        do { _ = try await adapter.travel(from: "origin", to: "park", departure: now); XCTFail("403 must stop") }
        catch { XCTAssertTrue(error.localizedDescription.contains("403")) }
        XCTAssertEqual(spy.metrics.calls, 1)
    }

}
