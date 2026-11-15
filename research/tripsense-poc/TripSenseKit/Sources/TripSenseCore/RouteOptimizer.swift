import Foundation

public struct RouteMatrix: Sendable {
    public struct Key: Hashable, Sendable {
        public var from: String
        public var to: String
        public init(_ from: String, _ to: String) { self.from = from; self.to = to }
    }
    public var legs: [Key: RouteLeg] = [:]
    public var unavailable: Set<Key> = []
    public init() {}
}
public struct OptimizationRequest: Sendable {
    public var preferences: TripPreferences
    public var places: [Place]
    public var recommendations: [Recommendation]
    public var lockedIDs: Set<String>
    public var enforceVariety: Bool
    public init(preferences: TripPreferences, places: [Place], recommendations: [Recommendation], lockedIDs: Set<String> = [], enforceVariety: Bool = true) {
        self.preferences = preferences; self.places = places; self.recommendations = recommendations; self.lockedIDs = lockedIDs; self.enforceVariety = enforceVariety
    }
}

@MainActor public struct RouteOptimizer {
    public let routes: any RouteProviding
    public let hours: any OpeningHoursProviding
    public let diagnostics: Diagnostics
    public init(routes: any RouteProviding, hours: any OpeningHoursProviding, diagnostics: Diagnostics) {
        self.routes = routes; self.hours = hours; self.diagnostics = diagnostics
    }

    // Lexicographic ordering prioritizes travel time; waiting, distance, candidate rank and IDs break ties.
    private func better(_ a: Itinerary, _ b: Itinerary, ranks: [String: Int]) -> Bool {
        if a.travelTime != b.travelTime { return a.travelTime < b.travelTime }
        if a.waitingTime != b.waitingTime { return a.waitingTime < b.waitingTime }
        if a.distance != b.distance { return a.distance < b.distance }
        let ar = a.stops.reduce(0) { $0 + (ranks[$1.id] ?? 999) }
        let br = b.stops.reduce(0) { $0 + (ranks[$1.id] ?? 999) }
        if ar != br { return ar < br }
        return a.stops.map(\.id).lexicographicallyPrecedes(b.stops.map(\.id))
    }

    public func optimize(_ request: OptimizationRequest) async throws -> Itinerary {
        try await withThrowingTaskGroup(of: Itinerary.self) { group in
            group.addTask { try await self.execute(request) }
            group.addTask { try await Task.sleep(for: .seconds(180)); throw PlanningError.deadlineExceeded }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw PlanningError.deadlineExceeded }
            return result
        }
    }

    private func execute(_ request: OptimizationRequest) async throws -> Itinerary {
        let p = request.preferences
        let places = request.places
        guard (1 ... 6).contains(p.count), (p.count ... 6).contains(places.count), p.origin.isValid,
              p.start.timeIntervalSince1970.isFinite, p.duration.isFinite, p.duration > 0, p.duration <= 86400,
              p.visitDuration.isFinite, p.visitDuration > 0, p.buffer.isFinite, p.buffer >= 0,
              let zone = TimeZone(identifier: p.timeZoneID) else { throw PlanningError.invalidInput }
        let ids = places.map(\.id)
        guard Set(ids).count == ids.count, request.lockedIDs.isSubset(of: Set(ids)),
              request.lockedIDs.count <= p.count, places.allSatisfy({ $0.coordinate.isValid }) else { throw PlanningError.invalidIDs }
        let recIDs = request.recommendations.map(\.placeID)
        guard Set(recIDs).count == recIDs.count, Set(recIDs).isSubset(of: Set(ids)) else { throw PlanningError.invalidIDs }
        let deadline = Date().addingTimeInterval(180)
        func check() throws { try Task.checkCancellation(); if Date() > deadline { throw PlanningError.deadlineExceeded } }
        diagnostics.phase = "Checking opening hours…"
        let opening = await hours.fetchHours(for: places, start: p.start, end: p.start.addingTimeInterval(p.duration), timeZone: zone)
        try check()
        let origin = Place(id: "origin", name: "Starting point", coordinate: p.origin, category: "Origin", themes: [])
        guard !ids.contains(origin.id) else { throw PlanningError.invalidIDs }
        diagnostics.phase = "Fetching route estimates…"
        var matrix = RouteMatrix()
        var report = OptimizationReport()
        // Sequential requests stay below the maximum concurrency of two and limit throttling.
        for from in [origin] + places {
            for to in places where from.id != to.id {
                try check()
                guard report.matrixRequests < 36 else { throw PlanningError.toolBudget }
                report.matrixRequests += 1
                do {
                    let leg = try await routes.estimate(from: from, to: to, mode: p.mode, departure: p.start)
                    guard leg.originID == from.id, leg.destinationID == to.id, leg.mode == p.mode,
                          leg.travelTime.isFinite, leg.travelTime >= 0, leg.distance.isFinite, leg.distance >= 0 else { throw PlanningError.incompleteMatrix }
                    matrix.legs[.init(from.id, to.id)] = leg
                } catch is CancellationError { throw CancellationError() }
                catch PlanningError.unavailableRoute { matrix.unavailable.insert(.init(from.id, to.id)) }
                catch PlanningError.toolBudget { throw PlanningError.toolBudget }
                catch PlanningError.throttled { throw PlanningError.throttled }
                catch { diagnostics.record("Matrix incomplete: \(from.id) → \(to.id)"); throw PlanningError.incompleteMatrix }
            }
        }
        report.matrixComplete = true
        let catalog = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let reasons = Dictionary(request.recommendations.map { ($0.placeID, $0.reason) }, uniquingKeysWith: { a, _ in a })
        let ranks = Dictionary(uniqueKeysWithValues: places.enumerated().map { ($0.element.id, $0.offset) })
        var feasible: [Itinerary] = []
        var candidateOrders: [[String]] = []
        func enumerate(_ prefix: [String], _ remaining: [String]) throws {
            try check()
            if prefix.count == p.count {
                guard request.lockedIDs.isSubset(of: Set(prefix)) else { return }
                if p.theme == .mixed && p.count >= 2 && request.enforceVariety {
                    var groups: Set<String> = []
                    for id in prefix { let t = catalog[id]!.themes
                        if !t.isDisjoint(with: [.history, .culture]) { groups.insert("heritage") }
                        if t.contains(.nature) { groups.insert("nature") }
                        if t.contains(.food) { groups.insert("food") }
                    }
                    if groups.count < 2 { return }
                } else if p.theme != .mixed && prefix.contains(where: { !catalog[$0]!.themes.contains(p.theme) }) { return }
                report.evaluatedOrders += 1; candidateOrders.append(prefix)
                if let itinerary = evaluate(order: prefix, origin: origin, catalog: catalog, reasons: reasons,
                                            p: p, opening: opening, matrix: matrix) { feasible.append(itinerary) }
                return
            }
            for id in remaining { try enumerate(prefix + [id], remaining.filter { $0 != id }) }
        }
        diagnostics.phase = "Comparing schedules…"
        try enumerate([], ids)
        guard !feasible.isEmpty else { throw PlanningError.insufficientTime }
        feasible.sort { better($0, $1, ranks: ranks) }
        report.snapshotTravelTime = feasible[0].travelTime
        let initialIDs = request.recommendations.map(\.placeID).filter { catalog[$0] != nil }
        let initialOrder = Array(initialIDs.prefix(p.count))
        var baselineOrders: [[String]] = []
        var initialBaseline: [String]?
        var heuristicBaseline: [String]?
        if initialOrder.count == p.count && candidateOrders.contains(initialOrder) { baselineOrders.append(initialOrder); initialBaseline = initialOrder }
        // Reproduce the previous geographic heuristic on the original selection.
        if initialOrder.count == p.count {
            var pending = initialOrder; var chosen: [String] = []; var current = origin.coordinate; var seen: Set<Theme> = []
            while !pending.isEmpty {
                pending.sort { a, b in
                    let x = Scheduler.score(place: catalog[a]!, from: current, origin: p.origin, theme: p.theme, seen: seen)
                    let y = Scheduler.score(place: catalog[b]!, from: current, origin: p.origin, theme: p.theme, seen: seen)
                    return x == y ? a < b : x > y
                }
                let next = pending.removeFirst(); chosen.append(next); current = catalog[next]!.coordinate; seen.formUnion(catalog[next]!.themes)
            }
            if candidateOrders.contains(chosen) { baselineOrders.append(chosen); heuristicBaseline = chosen }
        }
        var orders = feasible.prefix(3).map { $0.stops.map(\.id) }
        for order in baselineOrders where !orders.contains(order) { orders.append(order) }
        diagnostics.phase = "Validating selected routes…"
        var validated: [(Itinerary, [String])] = []
        for order in orders {
            try check()
            var current = origin; var now = p.start; var stops: [ScheduledStop] = []; var failed = false
            for id in order {
                try check()
                guard report.matrixRequests + report.detailRequests < 72 else { throw PlanningError.toolBudget }
                report.detailRequests += 1
                let place = catalog[id]!
                do {
                    let leg = try await routes.route(from: current, to: place, mode: p.mode, departure: now)
                    guard let stop = makeStop(place: place, leg: leg, current: current, now: now, p: p,
                                              opening: opening[id] ?? .unknown, reason: reasons[id] ?? "Native category match from retrieved results") else {
                        report.failures.append("Schedule conflicts with time or hours at \(id)"); failed = true; break
                    }
                    stops.append(stop); current = place; now = stop.departure
                } catch is CancellationError { throw CancellationError() }
                catch PlanningError.toolBudget { throw PlanningError.toolBudget }
                catch PlanningError.throttled { throw PlanningError.throttled }
                catch { report.failures.append("Final route unavailable: \(current.id) → \(id)"); failed = true; break }
            }
            if !failed { validated.append((Itinerary(stops: stops, startedAt: p.start, bufferPerStop: p.buffer), order)) }
        }
        guard !validated.isEmpty else { throw PlanningError.unavailableRoute }
        report.validatedAlternatives = validated.count
        report.baselineTravelTime = validated.filter { baselineOrders.contains($0.1) }.map { $0.0.travelTime }.min()
        report.initialBaselineTravelTime = validated.first { $0.1 == initialBaseline }?.0.travelTime
        report.heuristicBaselineTravelTime = validated.first { $0.1 == heuristicBaseline }?.0.travelTime
        report.networkRequests = routes.networkRequests
        report.cacheHits = routes.cacheHits
        validated.sort { better($0.0, $1.0, ranks: ranks) }
        var result = validated[0].0
        result.baselineTravelTime = report.baselineTravelTime
        result.report = report
        diagnostics.record("Optimizer: \(report.evaluatedOrders) orders, \(report.matrixRequests) ETA lookups, \(report.detailRequests) route lookups, \(report.validatedAlternatives) validated; best among validated only")
        if let requests = report.networkRequests {
            diagnostics.record("MapKit network requests: \(requests), cache hits: \(report.cacheHits ?? 0)")
        }
        for failure in report.failures { diagnostics.record(failure) }
        return result
    }

    private func evaluate(order: [String], origin: Place, catalog: [String: Place], reasons: [String: String],
                          p: TripPreferences, opening: [String: OpeningHours], matrix: RouteMatrix) -> Itinerary? {
        var current = origin; var now = p.start; var stops: [ScheduledStop] = []
        for id in order {
            guard let place = catalog[id], let leg = matrix.legs[.init(current.id, id)],
                  let stop = makeStop(place: place, leg: leg, current: current, now: now, p: p,
                                      opening: opening[id] ?? .unknown, reason: reasons[id] ?? "Native category match from retrieved results") else { return nil }
            stops.append(stop); current = place; now = stop.departure
        }
        return Itinerary(stops: stops, startedAt: p.start, bufferPerStop: p.buffer)
    }

    private func makeStop(place: Place, leg: RouteLeg, current: Place, now: Date, p: TripPreferences,
                          opening: OpeningHours, reason: String) -> ScheduledStop? {
        guard leg.originID == current.id, leg.destinationID == place.id, leg.mode == p.mode,
              leg.travelTime.isFinite, leg.travelTime >= 0, leg.distance.isFinite, leg.distance >= 0 else { return nil }
        var arrival = now.addingTimeInterval(leg.travelTime + p.buffer)
        if let windows = opening.windows {
            guard let window = windows.sorted(by: { $0.opens < $1.opens }).first(where: {
                max(arrival, $0.opens).addingTimeInterval(p.visitDuration) <= $0.closes
            }) else { return nil }
            arrival = max(arrival, window.opens)
        } else if p.requireHours { return nil }
        let departure = arrival.addingTimeInterval(p.visitDuration)
        guard departure <= p.start.addingTimeInterval(p.duration) else { return nil }
        return ScheduledStop(place: place, arrival: arrival, departure: departure, leg: leg, hours: opening, reason: reason, score: -leg.travelTime / 60)
    }
}
