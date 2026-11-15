import Foundation
import Testing
@testable import TripSenseCore

@MainActor private final class TestRoutes: RouteProviding {
    var calls: [String] = []
    var failure = false
    var seconds: Double = 600
    func route(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg {
        calls.append(to.id)
        if failure { throw PlanningError.unavailableRoute }
        return .init(originID: from.id, destinationID: to.id, mode: mode, departure: departure, distance: 500, travelTime: seconds)
    }
}
@MainActor private struct TestHours: OpeningHoursProviding {
    var value: OpeningHours
    func hours(for place: Place) -> OpeningHours { value }
}

@Suite @MainActor struct SchedulerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var places: [Place] { DemoFixture.places }
    var choices: [Recommendation] { places.prefix(2).map { .init($0.id, reason: "fixture") } }
    func preferences(duration: Double = 18000, theme: Theme = .mixed) -> TripPreferences {
        .init(start: start, duration: duration, theme: theme)
    }
    private func scheduler(routes: TestRoutes = TestRoutes(), hours: OpeningHours = .unknown) -> Scheduler {
        .init(routes: routes, hours: TestHours(value: hours), diagnostics: Diagnostics())
    }

    @Test func rejectsUnrelatedModelChoiceAndUsesRetrievedThemeMatch() throws {
        let proposed = [Recommendation("demo-cafe", reason: "Invented historical ambiance")]
        let selected = try CandidateSelector.select(places: places, proposed: proposed, theme: .history, count: 1)
        #expect(selected.map(\.placeID) == ["demo-museum"])
        #expect(selected[0].reason.contains("Native category match"))
        #expect(throws: PlanningError.invalidIDs) {
            try CandidateSelector.select(places: places, proposed: [.init("invented", reason: "bad")], theme: .history, count: 1)
        }
    }
    @Test func extraValidModelChoicesAreBoundedByDesiredCount() throws {
        let proposed = places.map { Recommendation($0.id, reason: "fixture") }
        let selected = try CandidateSelector.select(places: places, proposed: proposed, theme: .mixed, count: 2)
        #expect(selected.count == 2)
    }
    @Test func mixedSelectionKeepsMuseumAndCoffeeVariety() throws {
        let pool = [places[0], places[1], places[3]]
        let selected = try CandidateSelector.select(places: pool, proposed: pool.map { .init($0.id, reason: "fixture") }, theme: .mixed, count: 2)
        #expect(selected.map(\.placeID) == ["demo-museum", "demo-cafe"])
    }
    @Test func sameThemeSelectionExcludesUnrelatedFixtures() {
        let selected = DemoFixture.recommendations(theme: .history, count: 4)
        #expect(selected.map(\.placeID) == ["demo-museum"])
        let museum = Scheduler.score(place: places[0], from: preferences().origin, origin: preferences().origin, theme: .history, seen: [])
        let cafe = Scheduler.score(place: places[3], from: preferences().origin, origin: preferences().origin, theme: .history, seen: [])
        #expect(museum > cafe)
    }
    @Test func mixedThemeIncludesHistoryCultureNatureAndFood() {
        let ids = Set(DemoFixture.recommendations(theme: .mixed, count: 4).map(\.placeID))
        let themes = places.filter { ids.contains($0.id) }.reduce(into: Set<Theme>()) { $0.formUnion($1.themes) }
        #expect(themes == [.history, .culture, .nature, .food])
        let fresh = Scheduler.score(place: places[3], from: preferences().origin, origin: preferences().origin, theme: .mixed, seen: [.culture])
        let seen = Scheduler.score(place: places[3], from: preferences().origin, origin: preferences().origin, theme: .mixed, seen: [.food])
        #expect(fresh == seen + 40)
    }
    @Test func ordersNearbyPlacesAndUsesActualRouteTimes() async throws {
        let near = Place(id: "near", name: "Near", coordinate: preferences().origin, category: "Museum", themes: [.history])
        let far = Place(id: "far", name: "Far", coordinate: .init(-6.25, 106.9), category: "Museum", themes: [.history])
        let routes = TestRoutes()
        let result = try await scheduler(routes: routes).build(preferences: preferences(), places: [far, near],
                                                               recommendations: [.init("far", reason: "fixture"), .init("near", reason: "fixture")])
        #expect(routes.calls == ["near", "far"])
        #expect(result.travelTime == 1200)
        #expect(result.stops[0].arrival == start.addingTimeInterval(900))
        #expect(result.stops.last!.departure <= start.addingTimeInterval(18000))
    }
    @Test func verifiedHoursRejectClosedVisit() async {
        await #expect(throws: PlanningError.hoursConflict(choices[0].placeID)) {
            _ = try await scheduler(hours: .verified(windows: [.init(opens: start.addingTimeInterval(-3600), closes: start)], source: "test source"))
                .build(preferences: preferences(), places: places, recommendations: [choices[0]])
        }
    }
    @Test func fixtureHoursRemainExplicitAndWaitUntilOpen() async throws {
        let result = try await scheduler(hours: .demo(windows: [.init(opens: start.addingTimeInterval(1800), closes: start.addingTimeInterval(7200))]))
            .build(preferences: preferences(), places: places, recommendations: [choices[0]])
        #expect(result.stops[0].arrival == start.addingTimeInterval(1800))
        #expect(result.stops[0].hours.label.contains("DEMO ONLY"))
    }
    @Test func unknownHoursDoNotImplyOpen() async throws {
        let result = try await scheduler().build(preferences: preferences(), places: places, recommendations: [choices[0]])
        #expect(result.stops[0].hours.windows == nil)
        #expect(result.stops[0].hours.label.contains("Unknown"))
    }
    @Test func insufficientDurationRejected() async {
        await #expect(throws: PlanningError.insufficientTime) {
            _ = try await scheduler().build(preferences: preferences(duration: 600), places: places, recommendations: [choices[0]])
        }
    }
    @Test func duplicateAndInvalidIDsRejectedBeforeRouting() async {
        let routes = TestRoutes()
        for selections in [[choices[0], choices[0]], [Recommendation("invented", reason: "bad")]] {
            await #expect(throws: PlanningError.invalidIDs) {
                _ = try await scheduler(routes: routes).build(preferences: preferences(), places: places, recommendations: selections)
            }
        }
        #expect(routes.calls.isEmpty)
    }
    @Test func emptySearchResultsCannotBecomeSchedule() async {
        await #expect(throws: PlanningError.noPlaces) {
            _ = try await scheduler().build(preferences: preferences(), places: [], recommendations: [])
        }
    }
    @Test func routeErrorNeverFallsBackToStraightLine() async {
        let routes = TestRoutes(); routes.failure = true
        await #expect(throws: PlanningError.unavailableRoute) {
            _ = try await scheduler(routes: routes).build(preferences: preferences(), places: places, recommendations: [choices[0]])
        }
    }
    @Test func modelUnavailabilityExplicitlyFails() {
        #expect(throws: PlanningError.unavailableModel) { try ModelPlanner.requireAvailability(false) }
        #expect(throws: Never.self) { try ModelPlanner.requireAvailability(true) }
    }
    @Test func removalRecalculatesRemainingLegs() async throws {
        let routes = TestRoutes()
        let result = try await scheduler(routes: routes).build(preferences: preferences(), places: places, recommendations: choices)
        routes.calls.removeAll()
        let remaining = result.stops.dropFirst().map { Recommendation($0.id, reason: $0.reason) }
        let revised = try await scheduler(routes: routes).build(preferences: preferences(), places: places, recommendations: remaining)
        #expect(revised.stops.count == 1)
        #expect(revised.stops[0].leg.originID == "origin")
        #expect(routes.calls.count == 1)
    }
    @Test func invalidCoordinatesAndNaNRejected() async {
        var p = preferences(); p.origin.latitude = .nan
        await #expect(throws: PlanningError.invalidInput) {
            _ = try await scheduler().build(preferences: p, places: places, recommendations: choices)
        }
    }
    @Test func categoryTagsDoNotUseModelClaimAsFact() {
        #expect(MapServices.themes(category: "MKPOICategoryMuseum", name: "Museum") == [.history, .culture])
        #expect(MapServices.themes(category: "Unknown", name: "Unclassified") == [])
    }
}

@Suite struct LiveIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRIPSENSE_LIVE_TEST"] == "1"))
    @MainActor func realModelToolCallReturnsRealMapKitResults() async throws {
        try ModelPlanner.requireAvailability(ModelPlanner.availability == "available")
        let report = await FeasibilityExperiment.run()
        #expect(report.contains("Actual successful tool calls: 1") || report.contains("Actual successful tool calls: 2"))
        #expect(!report.contains("Actual MapKit names: []"))
        print(report)
    }
}
