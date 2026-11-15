import Foundation

@MainActor public struct Scheduler {
    let routes: any RouteProviding
    let hours: any OpeningHoursProviding
    let diagnostics: Diagnostics
    public init(routes: any RouteProviding, hours: any OpeningHoursProviding, diagnostics: Diagnostics) {
        self.routes = routes; self.hours = hours; self.diagnostics = diagnostics
    }

    // Visible heuristic: theme 100 + new-theme diversity 40 - straight-line km 10
    // - increasing distance from origin 5/km. Actual ETAs are checked after ordering.
    public static func score(place: Place, from: Coordinate, origin: Coordinate, theme: Theme, seen: Set<Theme>) -> Double {
        let relevance = theme == .mixed || place.themes.contains(theme) ? 100.0 : 0
        let diversity = theme == .mixed && !place.themes.subtracting(seen).isEmpty ? 40.0 : 0
        let backtrack = max(0, place.coordinate.distance(to: origin) - from.distance(to: origin)) / 1000
        return relevance + diversity - from.distance(to: place.coordinate) / 100 - backtrack * 5
    }

    public func build(preferences p: TripPreferences, places: [Place], recommendations: [Recommendation],
                      preserveOrder: Bool = false) async throws -> Itinerary {
        guard p.origin.isValid, p.start.timeIntervalSince1970.isFinite, p.duration.isFinite, p.duration > 0,
              p.duration <= 86400, (1 ... 6).contains(p.count), p.visitDuration.isFinite, p.visitDuration > 0,
              p.buffer.isFinite, p.buffer >= 0 else { throw PlanningError.invalidInput }
        guard !recommendations.isEmpty else { throw PlanningError.noPlaces }
        let catalog = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = recommendations.map(\.placeID)
        guard Set(ids).count == ids.count, ids.count <= p.count,
              ids.allSatisfy({ catalog[$0]?.coordinate.isValid == true }) else { throw PlanningError.invalidIDs }
        var remaining = recommendations
        var current = Place(id: "origin", name: "Starting point", coordinate: p.origin, category: "Origin", themes: [])
        var time = p.start
        var seen: Set<Theme> = []
        var stops: [ScheduledStop] = []
        while !remaining.isEmpty {
            try Task.checkCancellation()
            if !preserveOrder {
                remaining.sort {
                    let a = Self.score(place: catalog[$0.placeID]!, from: current.coordinate, origin: p.origin, theme: p.theme, seen: seen)
                    let b = Self.score(place: catalog[$1.placeID]!, from: current.coordinate, origin: p.origin, theme: p.theme, seen: seen)
                    return a == b ? $0.placeID < $1.placeID : a > b
                }
            }
            let choice = remaining.removeFirst()
            let place = catalog[choice.placeID]!
            let score = Self.score(place: place, from: current.coordinate, origin: p.origin, theme: p.theme, seen: seen)
            let leg: RouteLeg
            do { leg = try await routes.route(from: current, to: place, mode: p.mode, departure: time) }
            catch is CancellationError { throw CancellationError() }
            catch { diagnostics.record("Route failed: \(current.id) → \(place.id)"); throw PlanningError.unavailableRoute }
            try Task.checkCancellation()
            guard leg.distance.isFinite, leg.distance >= 0, leg.travelTime.isFinite, leg.travelTime >= 0,
                  leg.mode == p.mode, leg.originID == current.id, leg.destinationID == place.id else { throw PlanningError.unavailableRoute }
            var arrival = time.addingTimeInterval(leg.travelTime + p.buffer)
            let opening = hours.hours(for: place)
            if let windows = opening.windows {
                guard let slot = windows.sorted(by: { $0.opens < $1.opens }).first(where: {
                    max(arrival, $0.opens).addingTimeInterval(p.visitDuration) <= $0.closes
                }) else {
                    diagnostics.record("Scheduling conflict: \(place.id), \(opening.label)")
                    throw PlanningError.hoursConflict(place.id)
                }
                arrival = max(arrival, slot.opens)
            }
            let departure = arrival.addingTimeInterval(p.visitDuration)
            guard departure <= p.start.addingTimeInterval(p.duration) else {
                diagnostics.record("Rejected over-budget schedule at \(place.id)")
                throw PlanningError.insufficientTime
            }
            stops.append(.init(place: place, arrival: arrival, departure: departure, leg: leg, hours: opening,
                               reason: choice.reason, score: score - leg.travelTime / 60))
            diagnostics.record("Native schedule: \(place.id), score \(Int(score - leg.travelTime / 60)), \(opening.label)")
            current = place; time = departure; seen.formUnion(place.themes)
        }
        return Itinerary(stops: stops)
    }
}

@MainActor public struct UnknownHoursProvider: OpeningHoursProviding {
    public init() {}
    public func hours(for place: Place) -> OpeningHours { .unknown }
}
@MainActor public struct FixtureHoursProvider: OpeningHoursProviding {
    public let start: Date
    public init(start: Date) { self.start = start }
    public func hours(for place: Place) -> OpeningHours {
        .demo(windows: [.init(opens: start, closes: start.addingTimeInterval(8 * 3600))])
    }
}
