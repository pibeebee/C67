import Foundation

public struct ContextTravelTime: Codable, Sendable {
    public var seconds: Double; public var departure: Date; public var source: String
    public init(seconds: Double, departure: Date, source: String) { self.seconds = seconds; self.departure = departure; self.source = source }
}
@MainActor public protocol ContextTravelProvider: Sendable {
    func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime?
}
public struct ContextPlanStop: Codable, Sendable {
    public var snapshot: PlaceSnapshot; public var request: VisitContextRequest; public var weather: VisitWeatherContext?
    public init(snapshot: PlaceSnapshot, request: VisitContextRequest, weather: VisitWeatherContext? = nil) { self.snapshot = snapshot; self.request = request; self.weather = weather }
}
public enum ContextSearchPolicy: String, Codable, Sendable, CaseIterable {
    case beam, firstFeasible, selectiveOrders
}
public struct ContextPlanRequest: Codable, Sendable {
    public var originID: String; public var returnID: String; public var departure: Date; public var deadline: Date
    public var stops: [ContextPlanStop]
    public var priorities: [VisitGoal] = [.preferredTime, .lowerRain, .quiet, .comfortableTemperature]
    public var beamWidth = 12; public var maxTravelCalls = 256
    public var maximumTotalWaitingMinutes: Int?
    public var policy = ContextSearchPolicy.beam
    public var allVisitSlots = false
    enum CodingKeys: String, CodingKey { case originID, returnID, departure, deadline, stops, priorities, beamWidth, maxTravelCalls, maximumTotalWaitingMinutes, policy, allVisitSlots }
    public init(from decoder: Decoder)throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originID = try c.decode(String.self, forKey: .originID); returnID = try c.decode(String.self, forKey: .returnID)
        departure = try c.decode(Date.self, forKey: .departure); deadline = try c.decode(Date.self, forKey: .deadline)
        stops = try c.decode([ContextPlanStop].self, forKey: .stops)
        priorities = try c.decodeIfPresent([VisitGoal].self, forKey: .priorities) ?? [.preferredTime, .lowerRain, .quiet, .comfortableTemperature]
        beamWidth = try c.decodeIfPresent(Int.self, forKey: .beamWidth) ?? 12
        maxTravelCalls = try c.decodeIfPresent(Int.self, forKey: .maxTravelCalls) ?? 256
        maximumTotalWaitingMinutes = try c.decodeIfPresent(Int.self, forKey: .maximumTotalWaitingMinutes)
        policy = try c.decodeIfPresent(ContextSearchPolicy.self, forKey: .policy) ?? .beam
        allVisitSlots = try c.decodeIfPresent(Bool.self, forKey: .allVisitSlots) ?? false
    }
    public init(originID: String, returnID: String, departure: Date, deadline: Date, stops: [ContextPlanStop]) {
        self.originID = originID; self.returnID = returnID; self.departure = departure; self.deadline = deadline; self.stops = stops
    }
}
public struct ContextScheduledVisit: Codable, Sendable {
    public var placeID: String; public var arrival: Date; public var visit: VisitContextOption
}
public struct ContextTravelLeg: Codable, Sendable {
    public var from: String; public var to: String; public var departure: Date; public var arrival: Date; public var evidence: ContextTravelTime
}
public struct ContextItineraryResult: Codable, Sendable {
    public var travelSeconds = 0.0; public var waitingSeconds = 0.0; public var dwellSeconds = 0.0; public var elapsedSeconds: Double?
    public var status: String; public var visits: [ContextScheduledVisit]; public var legs: [ContextTravelLeg]; public var finish: Date?
    public var travelCalls: Int; public var searchTruncated: Bool; public var penaltyByPriority: [Double]
    public var contexts: [VisitContextResult]; public var warnings: [String]
}
/// Bounded beam search over order AND visit slots. No distance-based ETA or invented zero costs.
/// Travel adapters use app-owned IDs; this module has no MapKit dependency or coordinate transfer.
@MainActor public enum ContextItineraryPlanner {
    private struct TravelKey: Hashable { var from: String; var to: String; var departure: Date }
    private struct State {
        var remaining: [Int]; var last: String; var cursor: Date
        var visits: [ContextScheduledVisit] = []; var legs: [ContextTravelLeg] = []; var penalties: [Double]; var travel = 0.0; var waiting = 0.0
    }
    public static func plan(_ input: ContextPlanRequest, provider: any ContextTravelProvider, now: Date = .now,
                            requiring moment: VisitOpportunity? = nil) async throws -> ContextItineraryResult {
        guard (1 ... 6).contains(input.stops.count), Set(input.stops.map { $0.request.placeID }).count == input.stops.count,
              !input.originID.isEmpty,!input.returnID.isEmpty, input.originID.count <= 256, input.returnID.count <= 256,
              !input.stops.contains(where: { $0.request.placeID == input.originID || $0.request.placeID == input.returnID }),
              input.departure >= now, input.departure < input.deadline,
              ContextClock.label(input.departure) == ContextClock.label(input.deadline.addingTimeInterval(-0.001)),
              (1 ... 256).contains(input.beamWidth), (1 ... 512).contains(input.maxTravelCalls),
              input.maximumTotalWaitingMinutes.map({ (0 ... 1440).contains($0) }) ?? true,
              Set(input.priorities).count == input.priorities.count,
              input.stops.allSatisfy({ $0.request.day == ContextClock.label(input.departure) && Set($0.request.goals).isSubset(of: Set(input.priorities)) })
        else { throw ContextError.invalid("Plan requires 1–6 unique stops, future single-day bounds and explicit priority coverage") }
        var contexts = try input.stops.map { try VisitContextEngine.evaluate(snapshot: $0.snapshot, request: $0.request, weather: $0.weather, now: now) }
        if let moment {
            guard let index = contexts.firstIndex(where: { $0.placeID == moment.placeID }) else {
                throw ContextError.invalid("Momen harus merujuk tujuan yang ada dalam rencana")
            }
            contexts[index].options.removeAll { !moment.matches($0) }
        }
        var result = ContextItineraryResult(status: "needs_context", visits: [], legs: [], finish: nil, travelCalls: 0, searchTruncated: false, penaltyByPriority: [], contexts: contexts,
                                            warnings: ["Experimental bounded search; no global optimum, human relevance or field ETA accuracy claim", "All requested stops retained; Google facts and supplied travel evidence have separate provenance"])
        guard contexts.allSatisfy({ !$0.options.isEmpty }) else { return result }
        // Even a single successful tour needs one leg per stop plus the return.
        // Avoid a paid request when the declared cap cannot validate that minimum.
        if input.maxTravelCalls < input.stops.count + 1 {
            result.status = "no_candidate_within_search"; result.searchTruncated = true; return result
        }
        var cache: [TravelKey: ContextTravelTime] = [:]; var missing = Set<TravelKey>(); var hadUnavailable = false
        func leg(_ from: String, _ to: String, _ date: Date) async throws -> ContextTravelLeg? {
            try Task.checkCancellation(); let key = TravelKey(from: from, to: to, departure: date)
            if missing.contains(key) { return nil }
            let time: ContextTravelTime
            if let stored = cache[key] { time = stored }
            else {
                guard result.travelCalls < input.maxTravelCalls else { result.searchTruncated = true; return nil }
                result.travelCalls += 1
                guard let value = try await provider.travel(from: from, to: to, departure: date), value.seconds.isFinite, value.seconds >= 0,
                      abs(value.departure.timeIntervalSince(date)) < 0.001,!value.source.isEmpty else {
                    missing.insert(key); hadUnavailable = true; return nil
                }
                time = value; cache[key] = value
            }
            return .init(from: from, to: to, departure: date, arrival: date.addingTimeInterval(time.seconds), evidence: time)
        }
        func better(_ a: State, _ b: State) -> Bool {
            if a.penalties != b.penalties { return a.penalties.lexicographicallyPrecedes(b.penalties) }
            if a.cursor != b.cursor { return a.cursor < b.cursor }
            if a.travel != b.travel { return a.travel < b.travel }
            return a.visits.map(\.placeID).lexicographicallyPrecedes(b.visits.map(\.placeID))
        }
        func optimisticPenalties(_ state: State) -> [Double] {
            var penalties = state.penalties
            for index in state.remaining {
                let options = contexts[index].options.filter { $0.start >= state.cursor && $0.end <= input.deadline }
                guard !options.isEmpty else { return Array(repeating: .infinity, count: penalties.count) }
                for (priority, goal) in input.priorities.enumerated() {
                    let minimum = options.map { option in
                        option.assessments.first(where: { $0.goal == goal }).map { $0.penalty ?? 10000 } ?? 0
                    }.min()!
                    penalties[priority] += minimum
                }
            }
            return penalties
        }
        func betterPartial(_ a: State, _ b: State) -> Bool {
            // Unvisited goals contribute an optimistic bound. Otherwise visits with a
            // positive weather penalty are disadvantaged simply for being visited early.
            let left = optimisticPenalties(a)
            let right = optimisticPenalties(b)
            if left != right { return left.lexicographicallyPrecedes(right) }
            return better(a, b)
        }
        func permutations(_ values: [Int]) -> [[Int]] {
            if values.isEmpty { return [[]] }
            return values.flatMap { first in permutations(values.filter { $0 != first }).map { [first] + $0 } }
        }
        // Adapted policies share slot evaluation, objective, hard rules and exact ETA cache.
        // They are not the historical distance-prior D/E implementations.
        let indices = Array(input.stops.indices)
        let rotations = indices.map { offset in Array(indices[offset...]) + Array(indices[..<offset]) }
        let rest = permutations(indices).filter { !rotations.contains($0) }
        let orders: [[Int]?] = input.policy == .beam ? [nil] : (rotations + rest).map { Optional($0) }
        var complete: [State] = []
        var attemptedOrders = 0
        for order in orders {
            if input.policy == .selectiveOrders && attemptedOrders >= 3 {
                result.searchTruncated = true
                break
            }
            attemptedOrders += 1
            var beam = [State(remaining: Array(input.stops.indices), last: input.originID, cursor: input.departure, penalties: Array(repeating: 0, count: input.priorities.count))]
            for depth in input.stops.indices {
                var next: [State] = []
                for state in beam {
                    let indices = order.map { [$0[depth]] } ?? state.remaining
                    for index in indices {
                        let id = input.stops[index].request.placeID
                        let key = TravelKey(from: state.last, to: id, departure: state.cursor)
                        let needsProviderCall = cache[key] == nil && !missing.contains(key)
                        // Recompute after each destination. Cached evidence consumes no provider budget.
                        // Reserve one call for each remaining visit and the final return.
                        if needsProviderCall && input.maxTravelCalls - result.travelCalls < state.remaining.count + 1 {
                            result.searchTruncated = true
                            continue
                        }
                        guard let movement = try await leg(state.last, id, state.cursor), movement.arrival < input.deadline else { continue }
                        let feasible = contexts[index].options.filter { $0.start >= movement.arrival && $0.end <= input.deadline }
                        var selected = input.allVisitSlots ? feasible : Array(feasible.prefix(3))
                        if let earliest = feasible.min(by: { $0.start < $1.start }),!selected.contains(where: { $0.start == earliest.start }) { selected.append(earliest) }
                        if selected.count < feasible.count { result.searchTruncated = true }
                        for option in selected {
                            var n = state; n.remaining.removeAll { $0 == index }; n.last = id; n.cursor = option.end
                            n.waiting += option.start.timeIntervalSince(movement.arrival)
                            if let cap = input.maximumTotalWaitingMinutes, n.waiting > Double(cap * 60) + 0.001 { continue }
                            n.legs.append(movement); n.visits.append(.init(placeID: id, arrival: movement.arrival, visit: option)); n.travel += movement.evidence.seconds
                            for (i, goal) in input.priorities.enumerated() {
                                if let assessment = option.assessments.first(where: { $0.goal == goal }) { n.penalties[i] += assessment.penalty ?? 10000 }
                            }
                            next.append(n)
                        }
                    }
                }
                next.sort(by: betterPartial)
                if next.count > input.beamWidth { result.searchTruncated = true }
                let futureLegs = input.stops.count - depth
                let affordableStates = max(1, (input.maxTravelCalls - result.travelCalls) / max(1, futureLegs))
                if next.count > affordableStates { result.searchTruncated = true }
                beam = Array(next.prefix(min(input.beamWidth, affordableStates)))
                if beam.isEmpty { break }
            }
            var found: [State] = []
            for state in beam where state.remaining.isEmpty {
                guard let movement = try await leg(state.last, input.returnID, state.cursor), movement.arrival <= input.deadline else { continue }
                var finished = state; finished.legs.append(movement); finished.travel += movement.evidence.seconds; finished.cursor = movement.arrival; found.append(finished)
            }
            complete += found
            if input.policy == .firstFeasible && !found.isEmpty {
                if attemptedOrders < orders.count { result.searchTruncated = true }
                break
            }
            if input.policy == .selectiveOrders, let best = found.min(by: better),
               best.penalties.allSatisfy({ $0 == 0 }), best.waiting <= 1800, input.deadline.timeIntervalSince(best.cursor) >= 1800 {
                if attemptedOrders < orders.count { result.searchTruncated = true }
                break
            }
        }
        if let best = complete.min(by: better) {
            let unmodelledRainWaiting = best.visits.contains { visit in
                visit.visit.start > visit.arrival && input.stops.contains(where: { $0.request.placeID == visit.placeID && $0.request.avoidRain })
            }
            result.status = best.visits.contains(where: { !$0.visit.unknowns.isEmpty }) || unmodelledRainWaiting ? "candidate_with_unknown_preferences" : "candidate"
            result.visits = best.visits; result.legs = best.legs; result.finish = best.cursor; result.penaltyByPriority = best.penalties
            result.travelSeconds = best.travel
            result.waitingSeconds = best.visits.reduce(0) { $0 + $1.visit.start.timeIntervalSince($1.arrival) }
            result.dwellSeconds = best.visits.reduce(0) { $0 + $1.visit.end.timeIntervalSince($1.visit.start) }
            result.elapsedSeconds = best.cursor.timeIntervalSince(input.departure)
            if unmodelledRainWaiting { result.warnings.append("Rain preference evaluated during visits only; exposure while waiting is unknown") }
        } else { result.status = hadUnavailable ? "incomplete_travel_data" : "no_candidate_within_search" }
        if hadUnavailable { result.warnings.append("Some travel evidence unavailable; unknown was not converted to zero or a global infeasibility proof") }
        return result
    }
}
