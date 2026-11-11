import XCTest
import DynamicTripContracts
import PlaceContextEngine
import PlannerEngine
@testable import DynamicTripEngine

@MainActor final class SunsetOpportunityTests: XCTestCase {
    func testBeachIdentityRejectsNearbyTenants() {
        let place = SunsetVenueEvidence.placeID
        XCTAssertEqual(SunsetVenueEvidence.beachNameMatch(placeID: place, appleName: "Pantai Indah", separationMeters: 41), true)
        XCTAssertEqual(SunsetVenueEvidence.beachNameMatch(placeID: place, appleName: "Warung Pantai Indah", separationMeters: 20), false)
        XCTAssertEqual(SunsetVenueEvidence.beachNameMatch(placeID: place, appleName: "Pantai Indah", separationMeters: 101), false)
        XCTAssertEqual(SunsetVenueEvidence.beachNameMatch(placeID: "ChIJlbPSLzweai4RnJzpPilccgg",
                                                          appleName: "Bakso Super Pantai Festival Ancol", separationMeters: 20), false)
    }

    func testWeatherMustCoverWholeWindowWithoutHighRainOrCloud() throws {
        let sunset = try XCTUnwrap(ContextClock.day("2026-11-12")).addingTimeInterval(17 * 3600 + 35 * 60)
        let sunsetHour = sunset.addingTimeInterval(-35 * 60)
        let earlier = WeatherHour(start: sunsetHour.addingTimeInterval(-3600), rainChance: 0.1, cloudCover: 0.3)
        var later = WeatherHour(start: sunsetHour, rainChance: 0.1, cloudCover: 0.4)
        func offered(_ rows: [WeatherHour]) -> VisitOpportunity? {
            SunsetOpportunityPolicy.window(placeID: SunsetVenueEvidence.placeID, sunset: sunset, hours: rows,
                                           checkedAt: sunset.addingTimeInterval(-3600))
        }
        let moment = try XCTUnwrap(offered([later, earlier]))
        XCTAssertEqual(moment.end.timeIntervalSince(moment.start), 45 * 60)
        XCTAssertNil(offered([later]), "A forecast gap at the beginning is unknown")
        later.cloudCover = nil
        XCTAssertNil(offered([earlier, later]))
        later.cloudCover = 0.9
        XCTAssertNil(offered([earlier, later]))
        later.cloudCover = 0.4
        later.rainChance = 0.7
        XCTAssertNil(offered([earlier, later]))
    }

    func testAlternativeKeepsRequiredStopsAndRespectsBudgetAndExplicitPreference() async throws {
        let now = try XCTUnwrap(ContextClock.day("2026-11-11"))
        let day = "2026-11-12"
        let midnight = try XCTUnwrap(ContextClock.day(day))
        func time(_ hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }
        func stop(_ id: String, close: Int = 20) throws -> ContextPlanStop {
            let periods = (0 ... 6).map { day in
                ["open": ["day": day, "hour": 14, "minute": 0], "close": ["day": day, "hour": close, "minute": 0]]
            }
            let values: [String: Any] = ["id": id, "displayName": ["text": id], "businessStatus": "OPERATIONAL",
                                         "timeZone": ["id": "Asia/Jakarta"], "regularOpeningHours": ["periods": periods]]
            let snapshot = PlaceSnapshot(place: try JSONDecoder().decode(GooglePlace.self,
                                                                         from: JSONSerialization.data(withJSONObject: values)), fetchedAt: now, fieldMask: "SYNTHETIC")
            var request = VisitContextRequest(placeID: id, day: day)
            request.identityConfirmed = true
            request.availableStart = 15 * 60 + 30
            request.availableEnd = 19 * 60
            request.startStepMinutes = 15
            request.durationMinutes = 60
            return .init(snapshot: snapshot, request: request)
        }

        var input = ContextPlanRequest(originID: "origin", returnID: "origin", departure: time(15.5), deadline: time(19),
                                       stops: [try stop("beach"), try stop("museum")])
        input.maximumTotalWaitingMinutes = 30
        input.allVisitSlots = true
        input.maxTravelCalls = 48
        let moment = VisitOpportunity(id: "synthetic-sunset", placeID: "beach",
                                      start: time(17), end: time(17.75), minimumMinutes: 20,
                                      sourceName: "SYNTHETIC", sourceURL: URL(string: "https://example.invalid")!, forecastCheckedAt: now)
        let required: Set<String> = ["beach", "museum"]

        let provider = MomentTravel()
        let result = try await OpportunityItineraryPlanner.plan(input, requiredIDs: required, moments: [moment], provider: provider, now: now)
        let alternate = try XCTUnwrap(result.alternative)
        XCTAssertEqual(result.baseline.visits.map(\.placeID), ["beach", "museum"])
        XCTAssertEqual(alternate.visits.map(\.placeID), ["museum", "beach"])
        XCTAssertFalse(moment.matches(result.baseline))
        XCTAssertTrue(moment.matches(alternate))
        XCTAssertLessThanOrEqual(alternate.waitingSeconds, 30 * 60)
        XCTAssertLessThanOrEqual(try XCTUnwrap(alternate.finish), input.deadline)
        XCTAssertEqual(result.baseline.travelCalls, provider.calls)
        XCTAssertLessThanOrEqual(provider.calls, input.maxTravelCalls)

        input.maximumTotalWaitingMinutes = 5
        let tight = try await OpportunityItineraryPlanner.plan(input, requiredIDs: required, moments: [moment],
                                                               provider: MomentTravel(), now: now)
        XCTAssertNil(tight.alternative)
        XCTAssertEqual(tight.baseline.visits.count, 2)
        input.maximumTotalWaitingMinutes = 30

        input.stops[0] = try stop("beach", close: 17)
        let closed = try await OpportunityItineraryPlanner.plan(input, requiredIDs: required, moments: [moment],
                                                                provider: MomentTravel(), now: now)
        XCTAssertNil(closed.alternative)
        XCTAssertEqual(closed.baseline.visits.count, 2)

        input.stops[0] = try stop("beach")
        input.stops[0].request.preferredTime = .init(earliest: 15 * 60 + 45, latest: 16 * 60)
        let explicit = try await OpportunityItineraryPlanner.plan(input, requiredIDs: required, moments: [moment],
                                                                  provider: MomentTravel(), now: now)
        XCTAssertNil(explicit.alternative)
        XCTAssertNil(explicit.baselineMoment)
        XCTAssertEqual(explicit.baseline.visits.first?.placeID, "beach")
    }
}

@MainActor private final class MomentTravel: ContextTravelProvider {
    private(set) var calls = 0
    func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
        calls += 1
        return .init(seconds: from == "origin" && to == "museum" ? 1200 : 900,
                     departure: departure, source: "SYNTHETIC timing")
    }
}
