import Foundation
import PlaceContextEngine

public struct RoutingObservation: Codable, Sendable {
    public var caseID: String
    public var backend: String
    public var policy: String
    public var evidenceMode: String
    public var outcome: String
    public var wallSeconds: Double
    public var calls: Int
    public var visited: Int
    public var requiredRetained: Bool
    public var orderRetained: Bool
    public var deadlineMet: Bool
    public var arithmeticValid: Bool
    public var accessStatus: String
    public var searchLimited: Bool
    public var syntheticElapsedSeconds: Double? = nil
    public var syntheticTravelSeconds: Double? = nil
    public var syntheticWaitingSeconds: Double? = nil
    public var syntheticWalkingSeconds: Double? = nil
    public var syntheticPenalty: [Double]? = nil
}
public struct RoutingManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var venues: [RoutingVenue]
    public init(venues: [RoutingVenue], schemaVersion: Int = 1) { self.venues = venues; self.schemaVersion = schemaVersion }
    public func validate() throws {
        guard schemaVersion == 1, venues.count <= 64, !venues.isEmpty, Set(venues.map(\.id)).count == venues.count,
              venues.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.displayPoint.valid && !$0.sourceURL.isEmpty }) else { throw RoutingFailure.invalidInput }
    }
}
public enum RoutingStatistics {
    public static func percentile(_ values: [Double], fraction: Double) -> Double? {
        let sorted = values.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard !sorted.isEmpty, (0 ... 1).contains(fraction) else { return nil }
        return sorted[max(0, min(sorted.count - 1, Int(ceil(fraction * Double(sorted.count))) - 1))]
    }
}

@MainActor public final class SyntheticRoutingProvider: RoutingProvider {
    public let name = "SYNTHETIC routing fixture"
    public let backend: RouteBackend
    public let points: [String: RoutingPoint]
    public private(set) var calls = 0
    public var unavailableIDs = Set<String>()
    public var delay: Duration = .zero
    public init(backend: RouteBackend, points: [String: RoutingPoint]) { self.backend = backend; self.points = points }
    public func route(_ query: RoutingQuery) async throws -> RoutingResult? {
        try query.validate(); try Task.checkCancellation(); calls += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        guard !unavailableIDs.contains(query.to.id) else { return nil }
        guard let from = query.from.point ?? points[query.from.id], let to = query.to.point ?? points[query.to.id] else { throw RoutingFailure.invalidInput }
        let meters = from.distance(to: to) * 1.3
        let seconds = max(30, meters / (query.mode == .walking ? 1.2 : 6))
        return try .init(query: query, seconds: seconds, meters: meters, snappedFrom: from, snappedTo: to, geometry: query.geometry ? [from, .init(from.latitude, to.longitude), to] : [], source: name, traffic: "SYNTHETIC; no provider accuracy claim")
    }
}

@MainActor public enum RoutingFixtures {
    public struct WrongPriorTravel: ContextTravelProvider {
        public init() {}
        public func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
            let best = ["origin", "synthetic-3", "synthetic-2", "synthetic-1", "synthetic-0", "origin"]
            let fast = zip(best, best.dropFirst()).contains { $0.0 == from && $0.1 == to }
            return .init(seconds: fast ? 60 : 900, departure: departure, source: "SYNTHETIC directed-road adversary; deliberately contradicts local distance prior")
        }
    }
    public static let now = ContextClock.day("2026-11-10")!
    public static let day = "2026-11-11"
    public static var venues: [RoutingVenue] {
        let areas = ["Blok M", "Cikini", "Tebet", "Senayan-SCBD", "Kemang", "Kebon Jeruk", "Ragunan", "Kuningan"]
        return (0 ..< 16).map { index in
            let p = RoutingPoint(-6.20 - Double(index % 4) * 0.003, 106.80 + Double(index / 4) * 0.003)
            let access = AccessPoint(id: "door-\(index)", point: p, kind: .pedestrianEntrance, modes: [.walking], publicAccess: true, sourceURL: "https://example.invalid/synthetic-selection", checkedAt: now, status: .synthetic)
            var vehicle = access; vehicle.id += "-vehicle"; vehicle.kind = .dropoff; vehicle.modes = [.automobile]
            return .init(id: "synthetic-\(index)", name: "SYNTHETIC venue \(index)", area: areas[index / 2], displayPoint: .init(p.latitude - 0.0008, p.longitude), applePoint: .init(p.latitude - 0.0008, p.longitude), googlePlaceID: "synthetic-\(index)", accesses: [access, vehicle], reference: nil, sourceURL: "https://example.invalid/synthetic")
        }
    }
    public static func request(ids: [String], fixed: Bool = false) throws -> ContextPlanRequest {
        let stops = try ids.map { id -> ContextPlanStop in
            let place = try JSONDecoder().decode(GooglePlace.self, from: PlaceContextDemo.fixture(id: id))
            let snapshot = PlaceSnapshot(place: place, fetchedAt: now, fieldMask: "SYNTHETIC", source: "SYNTHETIC")
            var visit = VisitContextRequest(placeID: id, day: day)
            visit.identityConfirmed = true; visit.durationMinutes = 30; visit.startStepMinutes = 15
            return .init(snapshot: snapshot, request: visit)
        }
        let date = ContextClock.day(day)!
        var input = ContextPlanRequest(originID: "origin", returnID: "origin", departure: date.addingTimeInterval(9 * 3600), deadline: date.addingTimeInterval(18 * 3600), stops: stops)
        input.maxTravelCalls = 128; input.allVisitSlots = true; input.order = fixed ? .fixed : .optimized
        input.maximumTotalWaitingMinutes = 120
        return input
    }
    public static func observation(id: String, backend: String, policy: String, mode: String, seconds: Double, result: ContextItineraryResult, required: Set<String>, input: ContextPlanRequest) -> RoutingObservation {
        let visited = result.visits.map(\.placeID)
        let order = input.stops.map { $0.request.placeID }.filter { visited.contains($0) }
        let arithmetic = result.elapsedSeconds.map { abs($0 - result.travelSeconds - result.waitingSeconds - result.dwellSeconds) < 0.01 } ?? result.visits.isEmpty
        var row = RoutingObservation(caseID: id, backend: backend, policy: policy, evidenceMode: mode, outcome: result.status, wallSeconds: seconds, calls: result.travelCalls, visited: visited.count,
                                     requiredRetained: required.isSubset(of: Set(visited)), orderRetained: input.order != .fixed || order == visited, deadlineMet: result.finish.map { $0 <= input.deadline } ?? false,
                                     arithmeticValid: arithmetic, accessStatus: "unverified", searchLimited: result.searchTruncated)
        if mode.hasPrefix("SYNTHETIC") {
            row.syntheticElapsedSeconds = result.elapsedSeconds; row.syntheticTravelSeconds = result.travelSeconds
            row.syntheticWaitingSeconds = result.totalWaitingSeconds; row.syntheticWalkingSeconds = result.walkingSeconds; row.syntheticPenalty = result.penaltyByPriority
        }
        return row
    }
    public static func run() async throws -> [RoutingObservation] {
        var observations: [RoutingObservation] = []
        let points = Dictionary(uniqueKeysWithValues: venues.map { ($0.id, $0.accesses[0].point) }).merging(["origin": .init(-6.199, 106.799)]) { a, _ in a }
        for backend in RouteBackend.allCases {
            for mode in RouteMode.allCases {
                let provider = SyntheticRoutingProvider(backend: backend, points: points)
                for venue in venues {
                    let endpoint = try venue.endpoint(backend: backend, mode: mode, now: now, synthetic: true)
                    for approach in [-1.0, 1.0] {
                        let origin = RoutingEndpoint(id: "origin", revision: "synthetic-approach", point: .init(venue.displayPoint.latitude, venue.displayPoint.longitude + approach * 0.002))
                        let clock = ContinuousClock.now
                        let result = try await provider.route(.init(from: origin, to: endpoint, mode: mode, departure: now, geometry: true))
                        observations.append(.init(caseID: "leg-\(venue.id)-\(mode)-\(approach)", backend: backend.rawValue, policy: "fixed_leg", evidenceMode: "SYNTHETIC", outcome: result == nil ? "unavailable" : "available", wallSeconds: seconds(clock), calls: 1, visited: 0, requiredRetained: true, orderRetained: true, deadlineMet: true, arithmeticValid: true, accessStatus: "synthetic_only", searchLimited: false))
                    }
                }
            }
            for count in [1, 3, 6] {
                let ids = Array(venues.prefix(count)).map(\.id)
                for fixed in [false, true] {
                    for policy in ["baseline", "finalists"] {
                        let input = try request(ids: ids, fixed: fixed)
                        let memo = RoutingMemo(base: SyntheticRoutingProvider(backend: backend, points: points))
                        var endpoints: [String: RoutingEndpoint] = ["origin": .init(id: "origin", revision: "synthetic-origin", point: points["origin"])]
                        for venue in venues.prefix(count) { endpoints[venue.id] = try venue.endpoint(backend: backend, mode: .automobile, now: now, synthetic: true) }
                        let adapter = RoutingTravelAdapter(endpoints: endpoints, provider: memo, mode: .automobile)
                        let clock = ContinuousClock.now, required = Set(ids)
                        let result: ContextItineraryResult
                        if policy == "baseline" { result = try await OptionalItineraryPlanner.plan(input, requiredIDs: required, provider: adapter, now: now) }
                        else { result = try await FinalistRoutingPlanner.plan(input, required: required, provider: adapter, points: points, now: now) }
                        observations.append(observation(id: "itinerary-\(count)-\(fixed ? "fixed" : "optimized")", backend: backend.rawValue, policy: policy, mode: "SYNTHETIC", seconds: seconds(clock), result: result, required: required, input: input))
                    }
                }
            }
        }
        // Edit operations exercise the shared planner without touching app/editor state.
        for (operation, ids) in [("replace_first", ["synthetic-3", "synthetic-1", "synthetic-2"]), ("replace_middle", ["synthetic-0", "synthetic-3", "synthetic-2"]), ("replace_last", ["synthetic-0", "synthetic-1", "synthetic-3"]), ("reorder", ["synthetic-2", "synthetic-0", "synthetic-1"]), ("delete", ["synthetic-0", "synthetic-2"]), ("add", ["synthetic-0", "synthetic-1", "synthetic-2", "synthetic-3"])] {
            let input = try request(ids: ids, fixed: true)
            let endpoints = Dictionary(uniqueKeysWithValues: (["origin"] + ids).map { ($0, RoutingEndpoint(id: $0, revision: "synthetic-edit", point: points[$0])) })
            let adapter = RoutingTravelAdapter(endpoints: endpoints, provider: SyntheticRoutingProvider(backend: .valhallaAccess, points: points), mode: .walking)
            let clock = ContinuousClock.now
            let result = try await FinalistRoutingPlanner.plan(input, required: Set(ids), provider: adapter, points: points, now: now)
            observations.append(observation(id: operation, backend: "synthetic_walking", policy: "finalists", mode: "SYNTHETIC", seconds: seconds(clock), result: result, required: Set(ids), input: input))
        }
        observations += try await RoutingTransitFixtures.run()
        observations += try await RoutingTransitFixtures.itineraries()
        var adversary = try request(ids: (0 ..< 4).map { "synthetic-\($0)" })
        adversary.beamWidth = 64; adversary.maxTravelCalls = 512; adversary.allVisitSlots = false
        let required = Set(adversary.stops.map { $0.request.placeID })
        for policy in ["baseline", "finalists"] {
            let clock = ContinuousClock.now
            let result: ContextItineraryResult
            if policy == "baseline" { result = try await OptionalItineraryPlanner.plan(adversary, requiredIDs: required, provider: WrongPriorTravel(), now: now) }
            else { result = try await FinalistRoutingPlanner.plan(adversary, required: required, provider: WrongPriorTravel(), points: [:], now: now) }
            observations.append(observation(id: "adversarial_wrong_prior", backend: "synthetic_directed_roads", policy: policy, mode: "SYNTHETIC_ADVERSARIAL", seconds: seconds(clock), result: result, required: required, input: adversary))
        }
        return observations
    }
    public static func seconds(_ start: ContinuousClock.Instant) -> Double {
        let c = start.duration(to: .now).components; return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
