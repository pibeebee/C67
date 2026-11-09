import Foundation
import XCTest
import ContextPilotAdapters
import PlannerEngine
@testable import TripIntegration

@MainActor final class BuswayContextAdapterTests: XCTestCase {
    final class Walking: LabETAProvider {
        var metrics = LabProviderMetrics()
        var mismatch = false
        func values(_ queries: [LabETAQuery]) async throws -> [LabETAValue] {
            metrics.calls += 1
            return queries.map { q in
                var query = q; if mismatch { query.toID = "wrong" }
                return .init(query: query, seconds: 120, distance: 10)
            }
        }
    }
    func testRESTWalkingRejectsMismatchedIdentityAndPropagatesCancellation() async throws {
        let provider = Walking(); let walking = RESTBuswayWalking(provider: provider, synthetic: true)
        let a = TripIntegration.PlacePin(id: "a", name: "a", address: "Jakarta", latitude: -6.2, longitude: 106.8)
        let b = TripIntegration.PlacePin(id: "b", name: "b", address: "Jakarta", latitude: -6.21, longitude: 106.8)
        let valid = try await walking.walk(from: a, to: b, departure: .now)
        XCTAssertEqual(valid?.seconds, 120)
        provider.mismatch = true
        let invalid = try await walking.walk(from: a, to: b, departure: .now)
        XCTAssertNil(invalid)
        walking.cancel()
        do { _ = try await walking.walk(from: a, to: b, departure: .now); XCTFail("Cancellation required") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
    }
    func testSharedAdapterCarriesTransitEvidenceWithoutAutomobileFallback() async throws {
        var feed = try BuswayFeed.load(); feed.patterns = feed.patterns.filter { $0.id == "1-P97" }
        let now = feed.source.checkedAt.addingTimeInterval(1)
        let departure = TripIntegration.TripClock.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        func identity(_ id: String) -> PilotIdentity {
            let stop = feed.stops.first { $0.id == id }!
            var pin = PlannerEngine.PlacePin(id: id, name: stop.name, address: "Jakarta", latitude: stop.latitude, longitude: stop.longitude)
            pin.source = "Apple Maps Server API"
            return .init(internalID: id, googlePlaceID: nil, applePin: pin, evidence: "SYNTHETIC confirmation", confirmedAt: now)
        }
        let adapter = try BuswayContextAdapter(identities: [identity("G00031"), identity("P00017")], provider: Walking(), feed: feed, now: now, synthetic: true)
        let outward = try await adapter.travel(from: "G00031", to: "P00017", departure: departure)
        XCTAssertEqual(outward?.details?.mode, "transjakarta")
        XCTAssertEqual(outward?.details?.sourceSHA256, feed.source.sourceSHA256)
        XCTAssertEqual(outward?.details?.attributionURL, feed.source.attributionURL)
        XCTAssertEqual(outward?.details?.licenseURL, feed.source.licenseURL)
        XCTAssertTrue(outward?.details?.segments.contains { $0.kind == "bus" } == true)
        let reverse = try await adapter.travel(from: "P00017", to: "G00031", departure: departure)
        XCTAssertNil(reverse)
    }
    func testTransferAdapterPreservesBoardingTimesAndNonBRTLeg() async throws {
        var feed = try BuswayFeed.load()
        feed.schemaVersion = 2; feed.routeID = "network"; feed.category = "TJ"
        feed.stops = feed.stops.filter { ["G00031", "G00021", "P00017"].contains($0.id) }
        feed.services = [.init(id: "test", startDate: "20260101", endDate: "20261231", weekdays: Array(1 ... 7))]
        feed.patterns = [.init(id: "1-test", serviceID: "test", headsign: "SYNTHETIC BRT", directionID: "1", shapeID: "test", calls: [.init(stopID: "G00031", sequence: 1, arrivalOffset: 0, departureOffset: 0), .init(stopID: "G00021", sequence: 2, arrivalOffset: 600, departureOffset: 600)], frequencies: [.init(start: 0, end: 86400, headway: 600, exactTimes: 0)])]
        feed.patterns[0].routeID = "1"; feed.patterns[0].category = "BRT"
        var second = feed.patterns[0]; second.id = "6-test"; second.routeID = "6"; second.category = "Angkutan Umum Integrasi"
        second.calls[0].stopID = "G00021"; second.calls[1].stopID = "P00017"
        feed.patterns.append(second)
        feed.transfers = [.init(fromStopID: "G00021", toStopID: "G00021", minimumSeconds: 120, evidence: "SYNTHETIC interchange")]
        let now = feed.source.checkedAt.addingTimeInterval(1)
        func identity(_ id: String) -> PilotIdentity {
            let stop = feed.stops.first { $0.id == id }!
            var pin = PlannerEngine.PlacePin(id: id, name: stop.name, address: "Jakarta", latitude: stop.latitude, longitude: stop.longitude); pin.source = "Apple Maps Server API"
            return .init(internalID: id, googlePlaceID: nil, applePin: pin, evidence: "SYNTHETIC confirmation", confirmedAt: now)
        }
        let adapter = try BuswayContextAdapter(identities: [identity("G00031"), identity("P00017")], provider: Walking(), feed: feed, now: now, synthetic: true)
        let result = try await adapter.travel(from: "G00031", to: "P00017", departure: now)
        XCTAssertEqual(result?.details?.segments.map(\.kind), ["walking", "bus", "walking", "bus", "walking"])
        XCTAssertTrue(result?.details?.segments.filter { $0.kind == "bus" }.allSatisfy { $0.departure != nil && $0.arrival != nil } == true)
        XCTAssertGreaterThan(result?.details?.transitWaitingSeconds ?? 0, 1200)
    }

}
