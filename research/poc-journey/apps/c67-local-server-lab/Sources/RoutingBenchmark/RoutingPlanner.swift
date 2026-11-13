import Foundation
import PlaceContextEngine
import TripIntegration

/// Per-campaign memo with revision-aware keys and owned in-flight tasks.
@MainActor public final class RoutingMemo: RoutingProvider {
    public var name: String { base.name }
    private let base: any RoutingProvider
    private var values: [RoutingQuery: RoutingResult] = [:]
    private var missing = Set<RoutingQuery>()
    private var tasks: [RoutingQuery: Task<RoutingResult?, Error>] = [:]
    private var generation = UUID()
    public private(set) var calls = 0
    public private(set) var hits = 0
    public let limit: Int
    public init(base: any RoutingProvider, limit: Int = 128) { self.base = base; self.limit = limit }
    public func invalidate() {
        generation = UUID(); tasks.values.forEach { $0.cancel() }; tasks.removeAll(); values.removeAll(); missing.removeAll()
    }
    public func route(_ query: RoutingQuery) async throws -> RoutingResult? {
        try Task.checkCancellation(); try query.validate()
        if let value = values[query] { hits += 1; return value }
        if missing.contains(query) { hits += 1; return nil }
        let identity = generation
        let task: Task<RoutingResult?, Error>
        if let pending = tasks[query] { hits += 1; task = pending }
        else {
            guard calls < limit else { throw RoutingFailure.budgetExhausted }
            calls += 1
            task = Task { try await base.route(query) }; tasks[query] = task
        }
        do {
            let value = try await task.value
            try Task.checkCancellation()
            guard generation == identity else { throw RoutingFailure.staleResult }
            if let value {
                guard value.query == query else { throw RoutingFailure.invalidResponse }
                values[query] = value
            } else { missing.insert(query) }
            tasks[query] = nil; return value
        } catch {
            if generation == identity { tasks[query] = nil }
            throw error
        }
    }
}

@MainActor public final class RoutingTravelAdapter: ContextTravelProvider {
    private let endpoints: [String: RoutingEndpoint]
    private let provider: any RoutingProvider
    private let mode: RouteMode
    public init(endpoints: [String: RoutingEndpoint], provider: any RoutingProvider, mode: RouteMode) { self.endpoints = endpoints; self.provider = provider; self.mode = mode }
    public func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
        guard let a = endpoints[from], let b = endpoints[to] else { throw RoutingFailure.invalidInput }
        let query = RoutingQuery(from: a, to: b, mode: mode, departure: departure)
        guard let route = try await provider.route(query), route.query == query else { return nil }
        return .init(seconds: route.seconds, departure: departure, source: route.source + "; " + route.traffic)
    }
}

@MainActor public final class RoutingWalkingAdapter: BuswayWalking {
    public private(set) var requests = 0
    public private(set) var failures: [String] = []
    public var synthetic: Bool { provenance == "synthetic_walking" }
    private let provider: any RoutingProvider
    private let provenance: String
    private let googlePlaceIDs: [String: String]
    private var cancelled = false
    public init(provider: any RoutingProvider, provenance: String, googlePlaceIDs: [String: String] = [:]) throws {
        guard ["valhalla_osm_walking", "google_routes_walking", "apple_maps_rest_walking", "mapkit_walking", "synthetic_walking"].contains(provenance) else { throw RoutingFailure.invalidInput }
        self.provider = provider; self.provenance = provenance; self.googlePlaceIDs = googlePlaceIDs
    }
    public func cancel() { cancelled = true }
    public func walk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayWalk? {
        try Task.checkCancellation(); guard !cancelled else { throw CancellationError() }
        guard requests < 128 else { failures.append("walking_budget_exhausted"); return nil }
        func endpoint(_ pin: PlacePin) -> RoutingEndpoint {
            .init(id: pin.id, revision: "tj-walk-coordinate", point: googlePlaceIDs[pin.id] == nil ? .init(pin.latitude, pin.longitude) : nil, googlePlaceID: googlePlaceIDs[pin.id])
        }
        let query = RoutingQuery(from: endpoint(from), to: endpoint(to), mode: .walking, departure: departure)
        requests += 1
        guard let result = try await provider.route(query), result.query == query else { failures.append("walking_provider_unavailable"); return nil }
        try Task.checkCancellation(); guard !cancelled else { throw CancellationError() }
        return .init(from: from, to: to, seconds: result.seconds, distanceMeters: result.meters, provider: provenance)
    }
}

@MainActor public final class RoutingTransitAdapter: ContextTravelProvider {
    private let endpoints: [String: RoutingEndpoint]
    private let service: BuswayRoutingService
    public init(endpoints: [String: RoutingEndpoint], feed: BuswayFeed, walking: RoutingWalkingAdapter, now: Date) throws {
        self.endpoints = endpoints; service = try .init(feed: feed, walking: walking, now: now)
    }
    public func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
        guard let a = endpoints[from]?.point, let b = endpoints[to]?.point else { throw RoutingFailure.missingAccess }
        let start = PlacePin(id: from, name: from, address: "Benchmark access point", latitude: a.latitude, longitude: a.longitude)
        let end = PlacePin(id: to, name: to, address: "Benchmark access point", latitude: b.latitude, longitude: b.longitude)
        guard let trip = try await service.route(from: start, to: end, departure: departure) else { return nil }
        try trip.validate()
        var details = ContextTransportDetails(mode: trip.rides.isEmpty ? "walking" : "transjakarta", walkingSeconds: trip.walkingSeconds, transitWaitingSeconds: trip.waitingSeconds, summary: trip.summary, sourceSHA256: trip.source.sourceSHA256, searchLimited: service.searchLimited)
        details.sourceCheckedAt = trip.source.checkedAt; details.sourcePublisher = trip.source.publisher
        return .init(seconds: trip.seconds, departure: departure, source: "Static attributed GTFS; " + trip.access.provider, details: details)
    }
}

public struct RoutingPair: Hashable, Sendable {
    public var from: String
    public var to: String
    public init(_ from: String, _ to: String) { self.from = from; self.to = to }
}
@MainActor public enum FinalistRoutingPlanner {
    /// Search priors may rank orders, but only the shared exact planner certifies a candidate.
    public static func plan(_ input: ContextPlanRequest, required: Set<String>, provider: any ContextTravelProvider, points: [String: RoutingPoint], priors: [RoutingPair: Double] = [:], now: Date) async throws -> ContextItineraryResult {
        guard (1 ... 6).contains(input.stops.count), required.isSubset(of: Set(input.stops.map { $0.request.placeID })), Set(input.stops.map { $0.request.placeID }).count == input.stops.count else { throw RoutingFailure.invalidInput }
        let memo = FinalistTravelMemo(provider: provider, limit: input.maxTravelCalls)
        let indices = Array(input.stops.indices)
        let orders = input.order == .fixed ? [indices] : permutations(indices).sorted {
            let a = rank($0, input: input, points: points, priors: priors), b = rank($1, input: input, points: points, priors: priors)
            return a == b ? $0.lexicographicallyPrecedes($1) : a < b
        }
        var best: ContextItineraryResult?
        for order in orders.prefix(3) {
            try Task.checkCancellation()
            var candidate = input; candidate.order = .fixed; candidate.stops = order.map { input.stops[$0] }
            candidate.beamWidth = min(input.beamWidth, 2); candidate.allVisitSlots = false
            // Keep the existing bounded slot/subset search and preference objective.
            let result = try await OptionalItineraryPlanner.plan(candidate, requiredIDs: required, provider: memo, now: now)
            if best == nil || better(result, than: best!) { best = result }
        }
        guard var result = best else { throw RoutingFailure.invalidInput }
        result.travelCalls = memo.calls; result.searchTruncated = result.searchTruncated || orders.count > 3 || memo.exhausted
        result.warnings.append("Benchmark finalist search: at most three locally ranked orders and two slot states; estimates are not final ETA evidence; no global optimum claim")
        return result
    }
    private static func permutations(_ values: [Int]) -> [[Int]] {
        values.isEmpty ? [[]] : values.flatMap { first in permutations(values.filter { $0 != first }).map { [first] + $0 } }
    }
    private static func rank(_ order: [Int], input: ContextPlanRequest, points: [String: RoutingPoint], priors: [RoutingPair: Double]) -> Double {
        let ids = [input.originID] + order.map { input.stops[$0].request.placeID } + [input.returnID]
        return zip(ids, ids.dropFirst()).reduce(0) { total, pair in
            if let prior = priors[.init(pair.0, pair.1)], prior.isFinite, prior >= 0 { return total + prior }
            guard let a = points[pair.0], let b = points[pair.1] else { return total + 1e9 }
            return total + a.distance(to: b) / 6
        }
    }
    private static func better(_ a: ContextItineraryResult, than b: ContextItineraryResult) -> Bool {
        if a.visits.isEmpty != b.visits.isEmpty { return !a.visits.isEmpty }
        if a.penaltyByPriority != b.penaltyByPriority { return a.penaltyByPriority.lexicographicallyPrecedes(b.penaltyByPriority) }
        if a.visits.count != b.visits.count { return a.visits.count > b.visits.count }
        return (a.finish ?? .distantFuture) < (b.finish ?? .distantFuture)
    }
}

@MainActor private final class FinalistTravelMemo: ContextTravelProvider {
    struct Key: Hashable { var from: String; var to: String; var departure: Date }
    let provider: any ContextTravelProvider
    let limit: Int
    var calls = 0, exhausted = false
    var values: [Key: ContextTravelTime] = [:]
    var missing = Set<Key>()
    init(provider: any ContextTravelProvider, limit: Int) { self.provider = provider; self.limit = limit }
    func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
        let key = Key(from: from, to: to, departure: departure)
        if let value = values[key] { return value }; if missing.contains(key) { return nil }
        guard calls < limit else { exhausted = true; return nil }
        calls += 1
        if let value = try await provider.travel(from: from, to: to, departure: departure) { values[key] = value; return value }
        missing.insert(key); return nil
    }
}
