import Foundation
import XCTest
import PlaceContextEngine
import DynamicTripEngine
import DynamicTripContracts

/// Reproductions of blind spots, not assertions that the behavior is desirable.
@MainActor final class SyntheticUserDiagnosticsTests: XCTestCase {
    func testDocumentGridDrivenOptionalOmission()async throws {
        let fixture = try await ContextExperiments.run("dry")
        var request = fixture.input
        let day = ContextClock.day(request.stops[0].request.day)!
        request.departure = day.addingTimeInterval(11 * 3600); request.deadline = day.addingTimeInterval(16 * 3600)
        request.maximumTotalWaitingMinutes = 15; request.maxTravelCalls = 128; request.allVisitSlots = true
        request.stops = Array(request.stops.prefix(2))
        for index in request.stops.indices {
            request.stops[index].request.availableStart = 660; request.stops[index].request.availableEnd = 960
            request.stops[index].request.durationMinutes = 60; request.stops[index].request.startStepMinutes = 15
            request.stops[index].request.preferredTime = nil; request.stops[index].request.avoidRain = false
            request.stops[index].request.seeksQuiet = false; request.stops[index].request.maximumComfortTemperatureC = nil
        }
        let required = Set([request.stops[0].request.placeID])
        let coarse = try await OptionalItineraryPlanner.plan(request, requiredIDs: required, provider: DiagnosticTravel(), now: fixture.now)
        for index in request.stops.indices {request.stops[index].request.startStepMinutes = 5}
        let fine = try await OptionalItineraryPlanner.plan(request, requiredIDs: required, provider: DiagnosticTravel(), now: fixture.now)
        XCTAssertEqual(coarse.visits.count, 1, "Current grid15 loses an optional visit in this constructed case")
        XCTAssertEqual(fine.visits.count, 2); XCTAssertEqual(fine.waitingSeconds, 0)
        XCTAssertTrue(coarse.contexts.allSatisfy{ !$0.options.isEmpty}, "Opening context itself is not the cause")
        if let dir = ProcessInfo.processInfo.environment["SYNTHETIC_USER_DIAGNOSTICS_OUTPUT"] {
            struct Artifact: Encodable {var mode = "synthetic fixed300s per leg; not observed live traffic"; var grid15: ContextItineraryResult; var grid5: ContextItineraryResult}
            try ContextJSON.encoder().encode(Artifact(grid15: coarse, grid5: fine)).write(to: URL(fileURLWithPath: dir).appendingPathComponent("diagnostic-grid.json"), options: .atomic)
        }
    }
    func testDocumentIdentityGuardScopeLimitations()throws {
        let tenantAllowed = DynamicAppleCandidate.compatibleNames(google: "Blok M Plaza", apple: "Hong Tang Plaza Blok M", address: "Jl. Bulungan No.76, Jakarta")
        let libraryAllowed = DynamicAppleCandidate.compatibleNames(google: "Perpustakaan Jakarta dan Pusat Dokumen Sastra HB Jassin/ Cikini", apple: "Jakarta Provincial Library", address: "Taman Ismail Marzuki Jl. Cikini Raya No.73, Jakarta")
        // Passing means the observed shortcomings were reproduced, not that identities are correct.
        XCTAssertTrue(tenantAllowed); XCTAssertFalse(libraryAllowed)
        if let dir = ProcessInfo.processInfo.environment["SYNTHETIC_USER_DIAGNOSTICS_OUTPUT"] {
            let data = try JSONSerialization.data(withJSONObject: ["mallTenantAllowed": tenantAllowed, "libraryAliasAllowed": libraryAllowed, "interpretation": "Current name policy admits extra tenant scope and rejects an alias; manual/source confirmation remains necessary"], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("diagnostic-identity.json"), options: .atomic)
        }
    }
}
@MainActor private final class DiagnosticTravel: ContextTravelProvider {
    func travel(from: String, to: String, departure: Date)async throws -> ContextTravelTime?{.init(seconds: 300, departure: departure, source: "synthetic-fixed300s")}
}
