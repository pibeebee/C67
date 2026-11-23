import Foundation
import C67Domain
import PocketEngine

/// One command's route budget and exact-time cache, shared across dates and candidates.
actor V41RouteSession {
    struct Key: Hashable {
        var from: String
        var to: String
        var minute: Int
    }

    struct Pair: Hashable {
        var from: String
        var to: String
    }

    let limit: Int
    private let services: PocketPlanningServices
    private let input: PlanningInput
    private var cache: [Key: V4Quote] = [:]
    private(set) var proxies: [Pair: V4Quote] = [:]
    private(set) var failedPairs = Set<Pair>()
    private(set) var calls = 0
    private(set) var providerDuration: Duration = .zero
    private(set) var stopReason: String?
    private var firstCallAt: ContinuousClock.Instant?
    private let maximumSeconds: Double
    private let reserve: @Sendable (Int) async throws -> Void
    private let candidateLimit: Int
    private var candidates = 0
    private var reservationError: (any Error)?

    func checkReservation() throws {
        if let reservationError { throw reservationError }
    }

    func quote(_ from: PlanningPoint, _ to: PlanningPoint, _ minute: Int) async throws -> V4Quote {
        func key(for point: PlanningPoint) -> String? {
            if point == input.origin { return "origin" }
            if point == input.planningEndpoint { return "endpoint" }
            return input.places.first { $0.location == point }?.id.uuidString
        }
        guard let fromID = key(for: from), let toID = key(for: to) else {
            return .init(minutes: nil, meters: nil, status: "missing_point")
        }
        return try await quote(fromID, toID, minute)
    }

    init(input: PlanningInput, services: PocketPlanningServices, limit: Int = 72, maximumSeconds: Double = 90,
         candidateLimit: Int = 500, initialCalls: Int = 0, reserve: @escaping @Sendable (Int) async throws -> Void = { _ in }) {
        self.input = input
        self.services = services
        self.limit = limit
        self.maximumSeconds = maximumSeconds
        calls = initialCalls
        self.reserve = reserve
        self.candidateLimit = candidateLimit
    }

    func startSearch() { firstCallAt = firstCallAt ?? .now }

    func reserveCandidate() -> Bool {
        if let start = firstCallAt, start.duration(to: .now) > .seconds(maximumSeconds) { stopReason = stopReason ?? "time_budget_exhausted" }
        if candidates >= candidateLimit { stopReason = stopReason ?? "candidate_budget_exhausted" }
        guard stopReason == nil else { return false }
        candidates += 1
        return true
    }

    func quote(_ from: String, _ to: String, _ minute: Int) async throws -> V4Quote {
        try Task.checkCancellation()
        let key = Key(from: from, to: to, minute: minute)
        if let value = cache[key] { return value }
        let endpoint = input.enginePreferences?.endPoint ?? (input.enginePreferences?.returnToOrigin == true ? input.origin : nil)
        if to == "endpoint", endpoint == nil { return .init(minutes: 0, meters: 0, status: "no_endpoint") }
        func point(_ id: String) -> PlanningPoint? {
            if id == "origin" { return input.origin }
            if id == "endpoint" { return endpoint }
            return input.places.first { $0.id.uuidString == id }?.location
        }
        guard let a = point(from), let b = point(to) else { return .init(minutes: nil, meters: nil, status: "missing_point") }
        if a == b { return .init(minutes: 0, meters: 0, status: "same_point") }
        if stopReason == nil, calls >= limit { stopReason = "quote_budget_exhausted" }
        if let start = firstCallAt, start.duration(to: .now) > .seconds(maximumSeconds) { stopReason = stopReason ?? "time_budget_exhausted" }
        if let stopReason { return .init(minutes: nil, meters: nil, status: stopReason) }
        firstCallAt = firstCallAt ?? .now
        calls += 1
        try checkReservation()
        do { try await reserve(calls) }
        catch {
            reservationError = error
            stopReason = "route_reservation_failed"
            throw error
        }
        try Task.checkCancellation()
        let pair = Pair(from: from, to: to)
        let value: V4Quote
        let started = ContinuousClock.now
        defer { providerDuration += started.duration(to: .now) }
        do {
            let leg = try await services.travel(.init(latitude: a.latitude, longitude: a.longitude),
                                                .init(latitude: b.latitude, longitude: b.longitude),
                                                Date(timeIntervalSince1970: Double(minute * 60)), input.mode)
            try Task.checkCancellation()
            if leg.seconds.isFinite, (0 ... 604_800).contains(leg.seconds), leg.meters.isFinite, leg.meters >= 0 {
                value = .init(minutes: Int(ceil(leg.seconds / 60)), meters: Int(ceil(leg.meters)), status: "mapkit_quote")
                proxies[pair] = value
            } else { value = .init(minutes: nil, meters: nil, status: "invalid_quote") }
        } catch TravelQuoteError.throttled {
            stopReason = "route_throttled"
            value = .init(minutes: nil, meters: nil, status: "route_throttled")
        } catch {
            try Task.checkCancellation()
            value = .init(minutes: nil, meters: nil, status: "route_unavailable")
        }
        if value.minutes == nil { failedPairs.insert(pair) }
        cache[key] = value
        return value
    }
}
