import Foundation
import Testing
@testable import TripSenseCore

@MainActor private final class MatrixRoutes: RouteProviding {
    var values: [String: Double] = [:]
    var detailValues: [String: Double] = [:]
    var missing: Set<String> = []
    var broken: Set<String> = []
    var detailFailures: Set<String> = []
    var throttled = false
    var detailDepartures: [Date] = []
    var estimateCount = 0
    func estimate(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg {
        estimateCount += 1
        let key = "\(from.id)>\(to.id)"
        if throttled { throw PlanningError.throttled }
        if missing.contains(key) { throw PlanningError.unavailableRoute }
        if broken.contains(key) { throw URLError(.notConnectedToInternet) }
        return .init(originID: from.id, destinationID: to.id, mode: mode, departure: departure,
                     distance: (values[key] ?? 100) * 2, travelTime: values[key] ?? 100)
    }
    func route(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg {
        detailDepartures.append(departure)
        let key = "\(from.id)>\(to.id)"
        if broken.contains(key) || detailFailures.contains(key) { throw URLError(.notConnectedToInternet) }
        if missing.contains(key) { throw PlanningError.unavailableRoute }
        let seconds = detailValues[key] ?? values[key] ?? 100
        return .init(originID: from.id, destinationID: to.id, mode: mode, departure: departure, distance: seconds * 2, travelTime: seconds)
    }
}

@MainActor private struct FixedHours: OpeningHoursProviding {
    let value: OpeningHours
    func hours(for place: Place) -> OpeningHours { value }
}

@MainActor private struct SlowRoutes: RouteProviding {
    func estimate(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg {
        try await Task.sleep(for: .seconds(30))
        throw PlanningError.unavailableRoute
    }
    func route(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg {
        throw PlanningError.unavailableRoute
    }
}

@Suite @MainActor struct OptimizationTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var places: [Place] {
        ["a", "b", "c"].enumerated().map { .init(id: $0.element, name: $0.element, coordinate: .init(-6.17 + Double($0.offset) / 1000, 106.82), category: "Museum", themes: [.history]) }
    }
    func preferences(count: Int = 3, duration: Double = 10000, requireHours: Bool = false) -> TripPreferences {
        .init(start: start, duration: duration, theme: .history, count: count, visitDuration: 60, buffer: 10, requireHours: requireHours)
    }
    func choices(_ p: [Place]) -> [Recommendation] { p.map { .init($0.id, reason: "test") } }
    private func optimizer(_ routes: MatrixRoutes, hours: any OpeningHoursProviding = UnknownHoursProvider()) -> RouteOptimizer {
        .init(routes: routes, hours: hours, diagnostics: Diagnostics())
    }
    @Test func exhaustiveOrderBeatsGreedyAndCountsDirectedMatrix() async throws {
        let routes = MatrixRoutes()
        routes.values = ["origin>a": 1, "origin>b": 2, "origin>c": 30, "a>b": 80, "a>c": 80,
                         "b>a": 2, "b>c": 50, "c>a": 50, "c>b": 50]
        routes.values["a>c"] = 2
        let trip = try await optimizer(routes).optimize(.init(preferences: preferences(), places: places, recommendations: choices(places)))
        #expect(trip.stops.map(\.id) == ["b", "a", "c"])
        #expect(trip.travelTime == 6)
        #expect(trip.report?.evaluatedOrders == 6)
        #expect(routes.estimateCount == 9)
        #expect(trip.report?.matrixComplete == true)
        #expect(trip.report?.baselineTravelTime != nil)
        #expect(routes.detailDepartures.contains(start.addingTimeInterval(72)))
    }
    @Test func candidateSelectionPreservesLockedAndChoosesFasterAlternative() async throws {
        let routes = MatrixRoutes()
        routes.values = ["origin>a": 1, "origin>b": 2, "origin>c": 90, "a>b": 1, "b>a": 1, "a>c": 3, "c>a": 3, "b>c": 80, "c>b": 80]
        let trip = try await optimizer(routes).optimize(.init(preferences: preferences(count: 2), places: places,
                                                              recommendations: choices(places), lockedIDs: ["c"]))
        #expect(Set(trip.stops.map(\.id)) == ["a", "c"])
        #expect(trip.stops.count == 2)
    }
    @Test func directedUnavailableLegCanBeAvoidedButNetworkFailureStopsOptimization() async throws {
        let routes = MatrixRoutes(); routes.missing = ["a>b"]
        let trip = try await optimizer(routes).optimize(.init(preferences: preferences(), places: places, recommendations: choices(places)))
        #expect(!zip(trip.stops, trip.stops.dropFirst()).contains { $0.id == "a" && $1.id == "b" })
        routes.broken = ["b>c"]
        await #expect(throws: PlanningError.incompleteMatrix) {
            _ = try await optimizer(routes).optimize(.init(preferences: preferences(), places: places, recommendations: choices(places)))
        }
    }
    @Test func throttlingIsReportedInsteadOfClaimingNoRoute() async {
        let routes = MatrixRoutes(); routes.throttled = true
        await #expect(throws: PlanningError.throttled) {
            _ = try await optimizer(routes).optimize(.init(preferences: preferences(), places: places, recommendations: choices(places)))
        }
    }
    @Test func unknownHoursAllowedByDefaultAndExcludedInStrictMode() async throws {
        let routes = MatrixRoutes()
        let result = try await optimizer(routes).optimize(.init(preferences: preferences(count: 1), places: places, recommendations: choices(places)))
        #expect(result.stops[0].hours.windows == nil)
        await #expect(throws: PlanningError.insufficientTime) {
            _ = try await optimizer(routes).optimize(.init(preferences: preferences(count: 1, requireHours: true), places: places, recommendations: choices(places)))
        }
    }
    @Test func invalidIDsAndTooManyLockedAreRejected() async {
        let routes = MatrixRoutes()
        await #expect(throws: PlanningError.invalidIDs) {
            _ = try await optimizer(routes).optimize(.init(preferences: preferences(count: 1), places: places, recommendations: choices(places), lockedIDs: ["a", "b"]))
        }
        await #expect(throws: PlanningError.invalidIDs) {
            _ = try await optimizer(routes).optimize(.init(preferences: preferences(), places: places, recommendations: [.init("fake", reason: "bad")]))
        }
        #expect(routes.estimateCount == 0)
    }

    @Test func oneThroughSixStopsMatchIndependentHeapEnumeration() async throws {
        let universe = ["a", "b", "c", "d", "e", "f"].enumerated().map {
            Place(id: $0.element, name: $0.element, coordinate: .init(-6.17 + Double($0.offset) / 1000, 106.82), category: "Museum", themes: [.history])
        }
        for n in 1 ... 6 {
            let pool = Array(universe.prefix(n)); let routes = MatrixRoutes()
            let names = ["origin"] + pool.map(\.id)
            for (i, from) in names.enumerated() {
                for (j, to) in pool.map(\.id).enumerated() where from != to {
                    routes.values["\(from)>\(to)"] = Double(((i * 19 + j * 7 + i * j * 3) % 47) + 1)
                }
            }
            // Heap's iterative permutation generator is independent of the optimizer's DFS.
            var order = pool.map(\.id); var counters = Array(repeating: 0, count: n); var index = 0
            func cost(_ ids: [String]) -> Double {
                var prior = "origin"; var sum = 0.0
                for id in ids { sum += routes.values["\(prior)>\(id)"]!; prior = id }
                return sum
            }
            var minimum = cost(order)
            while index < n {
                if counters[index] < index {
                    order.swapAt(index % 2 == 0 ? 0 : counters[index], index)
                    minimum = min(minimum, cost(order)); counters[index] += 1; index = 0
                } else { counters[index] = 0; index += 1 }
            }
            let result = try await optimizer(routes).optimize(.init(preferences: preferences(count: n), places: pool, recommendations: choices(pool)))
            #expect(result.travelTime == minimum)
            #expect(result.report?.matrixRequests == n * n)
        }
    }
    @Test func cancellationStopsAnInFlightEstimate() async throws {
        let optimizer = RouteOptimizer(routes: SlowRoutes(), hours: UnknownHoursProvider(), diagnostics: Diagnostics())
        let request = OptimizationRequest(preferences: preferences(count: 1), places: places, recommendations: choices(places))
        let task = Task { try await optimizer.optimize(request) }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
    @Test func sixPlacesExhausts720OrdersAndFindsKnownOptimum() async throws {
        let routes = MatrixRoutes()
        let six = ["a", "b", "c", "d", "e", "f"].enumerated().map {
            Place(id: $0.element, name: $0.element, coordinate: .init(-6.17 + Double($0.offset) / 1000, 106.82), category: "Museum", themes: [.history])
        }
        routes.values["origin>a"] = 1
        for pair in zip(six, six.dropFirst()) { routes.values["\(pair.0.id)>\(pair.1.id)"] = 1 }
        let trip = try await optimizer(routes).optimize(.init(preferences: preferences(count: 6), places: six, recommendations: choices(six)))
        #expect(trip.stops.map(\.id) == ["a", "b", "c", "d", "e", "f"])
        #expect(trip.travelTime == 6)
        #expect(trip.report?.evaluatedOrders == 720)
        #expect(trip.report?.matrixRequests == 36)
        #expect((trip.report?.detailRequests ?? 100) <= 30)
    }
    @Test func insufficientTimeAndClosedHoursAreNotPresentedAsFeasible() async {
        let routes = MatrixRoutes()
        await #expect(throws: PlanningError.insufficientTime) {
            _ = try await optimizer(routes).optimize(.init(preferences: preferences(count: 2, duration: 30), places: places, recommendations: choices(places)))
        }
        let hours = FixedHours(value: .verified(windows: [.init(opens: start.addingTimeInterval(-500), closes: start)], source: "test"))
        await #expect(throws: PlanningError.insufficientTime) {
            _ = try await optimizer(routes, hours: hours).optimize(.init(preferences: preferences(count: 1), places: places, recommendations: choices(places)))
        }
    }
    @Test func failedFinalRouteUsesAnotherValidatedSchedule() async throws {
        let routes = MatrixRoutes()
        routes.values = ["origin>a": 1, "origin>b": 2, "a>b": 1, "b>a": 2]
        routes.detailFailures = ["origin>a"]
        let pair = Array(places.prefix(2))
        let result = try await optimizer(routes).optimize(.init(preferences: preferences(count: 2), places: pair, recommendations: choices(pair)))
        #expect(result.stops.map(\.id) == ["b", "a"])
        #expect(result.report?.failures.isEmpty == false)
        #expect(result.report?.validatedAlternatives == 1)
    }
    @Test func realDepartureValidationCanChangeWinner() async throws {
        let routes = MatrixRoutes()
        routes.values = ["origin>a": 1, "origin>b": 2, "a>b": 1, "b>a": 2]
        routes.detailValues = ["a>b": 99]
        let pair = Array(places.prefix(2))
        let result = try await optimizer(routes).optimize(.init(preferences: preferences(count: 2), places: pair, recommendations: choices(pair)))
        #expect(result.stops.map(\.id) == ["b", "a"])
        #expect(result.report?.snapshotTravelTime == 2)
        #expect(result.travelTime == 4)
    }
}
