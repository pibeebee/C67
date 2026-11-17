import Foundation

// Native port of poc/hybrid-v4-lab/v4_planner.py. Times and durations are integer minutes.
struct V4Window: Codable, Sendable { var opens: Int; var closes: Int; var last_entry: Int? }
struct V4Hours: Codable, Sendable { var kind: String; var windows: [V4Window]; var source: String? }
struct V4Duration: Codable, Sendable { var minimum: Int; var target: Int; var maximum: Int; var basis: String; var source: String }
struct V4Target: Codable, Sendable { var earliest: Int; var latest: Int; var strength: String; var origin: String; var source: String }
struct V4Stop: Codable, Sendable { var id: String; var duration: V4Duration?; var hours: V4Hours; var target: V4Target? }
struct V4Waiting: Codable, Sendable { var per_stop: Int?; var total: Int? }
struct V4Trip: Codable, Sendable {
    var id: String; var origin: String; var endpoint: String; var stops: [V4Stop]
    var earliest_departure: Int; var return_deadline: Int; var departures: [Int]
    var waiting: V4Waiting; var wait_choices: [Int]; var first_id: String?; var locked: Bool
    var duration_policy: String; var objective: String; var last_id: String? = nil
}
struct V4Spec: Codable, Hashable, Sendable { var order: [String]; var departure: Int; var waits: [Int] }
struct V4Quote: Codable, Sendable { var minutes: Int?; var meters: Int?; var status: String }
struct V4Issue: Codable, Equatable, Sendable { var code: String; var place: String; var source: String? }
struct V4Visit: Codable, Sendable { var id: String; var arrival: Int?; var start: Int?; var end: Int?; var wait: Int; var duration: Int?; var quote: V4Quote }
struct V4Schedule: Codable, Sendable {
    var spec: V4Spec; var duration_policy: String; var visits: [V4Visit] = []; var finish: Int?
    var return_quote: V4Quote?; var driving: Int?; var meters: Int?; var soft_deviation: Int?
    var conflicts: [V4Issue] = []; var regular_conflicts: [V4Issue] = []; var unresolved: [V4Issue] = []; var assumptions: [String] = []
    var eligible: Bool { conflicts.isEmpty && regular_conflicts.isEmpty && finish != nil && driving != nil && soft_deviation != nil }
}
struct V4SearchResult: Sendable {
    var localCandidates: Int; var evaluated: [V4Schedule]; var recommended: V4Schedule?; var quoteCalls: Int; var exhausted: Bool

    var allCandidatesMissedDeadline: Bool {
        !exhausted && !evaluated.isEmpty && evaluated.count == localCandidates &&
            evaluated.allSatisfy { row in row.conflicts.contains { $0.code == "return_deadline_exceeded" } }
    }
}

enum V4Planner {
    enum Failure: Error { case tooManyCandidates, invalidInput }
    static func specs(_ trip: V4Trip, limit: Int = 100_000) throws -> [V4Spec] {
        let ids = trip.stops.map(\.id)
        guard !ids.isEmpty, ids.count <= 6, Set(ids).count == ids.count,
              !trip.departures.isEmpty, trip.wait_choices.contains(0) else { throw Failure.invalidInput }
        func permutations(_ ids: [String]) -> [[String]] {
            guard ids.count > 1 else { return [ids] }
            return ids.indices.flatMap { i -> [[String]] in
                var rest = ids; let first = rest.remove(at: i)
                return permutations(rest).map { [first] + $0 }
            }
        }
        let orders = trip.locked ? [ids] : permutations(ids)
        var result: [V4Spec] = []
        func waits(_ current: [Int], order: [String], departure: Int) throws {
            if current.count == order.count {
                guard trip.waiting.total == nil || current.reduce(0, +) <= trip.waiting.total! else { return }
                guard result.count < limit else { throw Failure.tooManyCandidates }
                result.append(.init(order: order, departure: departure, waits: current)); return
            }
            for wait in trip.wait_choices.sorted() { try waits(current + [wait], order: order, departure: departure) }
        }
        for order in orders where (trip.first_id == nil || order.first == trip.first_id) && (trip.last_id == nil || order.last == trip.last_id) {
            for departure in trip.departures.sorted() { try waits([], order: order, departure: departure) }
        }
        return result
    }
    static func evaluate(_ trip: V4Trip, _ spec: V4Spec, quote: (String, String, Int) -> V4Quote) -> V4Schedule {
        var result = V4Schedule(spec: spec, duration_policy: trip.duration_policy)
        func append(_ items: inout [V4Issue], _ code: String, _ place: String, _ source: String? = nil) {
            let issue = V4Issue(code: code, place: place, source: source); if !items.contains(issue) { items.append(issue) }
        }
        var durations: [String: Int] = [:]
        for stop in trip.stops {
            let hours = stop.hours
            if ["confirmed", "regular"].contains(hours.kind) && hours.windows.isEmpty {
                if hours.kind == "confirmed" { append(&result.conflicts, "all_day_closed", stop.id, hours.source) }
                else { append(&result.regular_conflicts, "all_day_closed", stop.id, hours.source) }
            }
            if hours.kind != "confirmed" { append(&result.unresolved, "date_access_unverified", stop.id, hours.source) }
            if let duration = stop.duration {
                let chosen = trip.duration_policy == "minimum" ? duration.minimum : trip.duration_policy == "maximum" ? duration.maximum : duration.target
                durations[stop.id] = chosen
                if duration.basis == "estimate" { result.assumptions.append("\(stop.id):estimated_duration:\(duration.source)") }
                if trip.duration_policy != "target" { result.assumptions.append("\(stop.id):duration_policy:\(trip.duration_policy)") }
                if ["confirmed", "regular"].contains(hours.kind), !hours.windows.isEmpty, !hours.windows.contains(where: { chosen <= $0.closes - $0.opens }) {
                    if hours.kind == "confirmed" { append(&result.conflicts, "duration_exceeds_all_windows", stop.id, hours.source) }
                    else { append(&result.regular_conflicts, "duration_exceeds_all_windows", stop.id, hours.source) }
                }
            } else { append(&result.unresolved, "duration_unknown", stop.id) }
            if let target = stop.target {
                if ["model", "forecast"].contains(target.origin) { result.assumptions.append("\(stop.id):conditional_target:\(target.origin):\(target.source)") }
                if target.strength == "hard", target.latest < trip.earliest_departure || target.earliest >= trip.return_deadline { append(&result.conflicts, "target_outside_availability", stop.id, target.source) }
            }
        }
        if let maxWait = trip.waiting.total, spec.waits.reduce(0, +) > maxWait { append(&result.conflicts, "total_wait_exceeded", "trip") }
        let byID = Dictionary(uniqueKeysWithValues: trip.stops.map { ($0.id, $0) })
        var clock: Int? = spec.departure; var origin = trip.origin; var driving = 0; var meters: Int? = 0; var soft: Int? = 0
        for (id, wait) in zip(spec.order, spec.waits) {
            guard let stop = byID[id] else { continue }
            let leg = clock.map { quote(origin, id, $0) } ?? V4Quote(minutes: nil, meters: nil, status: "upstream_unknown")
            if let value = leg.minutes { driving += value } else { append(&result.unresolved, "eta:" + leg.status, id) }
            if let value = leg.meters, let prior = meters { meters = prior + value } else { meters = nil; append(&result.unresolved, "distance_unknown", id) }
            let arrival = clock.flatMap { c in leg.minutes.map { c + $0 } }
            let start = arrival.map { $0 + wait }; let duration = durations[id]
            let end = start.flatMap { s in duration.map { s + $0 } }
            if let arrival, trip.waiting.per_stop == nil || trip.waiting.total == nil {
                let fits = duration.map { d in stop.hours.windows.contains { $0.opens <= arrival && arrival < $0.closes && arrival + d <= $0.closes && ($0.last_entry == nil || arrival <= $0.last_entry!) } } ?? false
                let later = duration.map { d in !fits && stop.hours.windows.contains { $0.opens > arrival && $0.opens + d <= $0.closes } } ?? false
                if (stop.target.map { $0.earliest > arrival } ?? false) || later { append(&result.unresolved, "waiting_permission_unknown", id) }
            }
            if let start, let end, ["confirmed", "regular"].contains(stop.hours.kind) {
                let fits = stop.hours.windows.contains { $0.opens <= start && start < $0.closes && end <= $0.closes && ($0.last_entry == nil || start <= $0.last_entry!) }
                if !fits {
                    if stop.hours.kind == "confirmed" { append(&result.conflicts, "visit_outside_hours_or_entry", id, stop.hours.source) }
                    else { append(&result.regular_conflicts, "visit_outside_hours_or_entry", id, stop.hours.source) }
                }
            }
            if let target = stop.target {
                if let start {
                    let deviation = max(target.earliest - start, 0, start - target.latest)
                    if target.strength == "hard" && deviation > 0 { append(&result.conflicts, "hard_target_missed", id, target.source) }
                    else if target.strength == "soft", let prior = soft { soft = prior + deviation }
                } else { append(&result.unresolved, "target_not_checked", id, target.source); if target.strength == "soft" { soft = nil } }
            }
            result.visits.append(.init(id: id, arrival: arrival, start: start, end: end, wait: wait, duration: duration, quote: leg))
            origin = id; clock = end
        }
        let leg = clock.map { quote(origin, trip.endpoint, $0) } ?? V4Quote(minutes: nil, meters: nil, status: "upstream_unknown")
        result.return_quote = leg
        if let value = leg.minutes { driving += value } else { append(&result.unresolved, "eta:" + leg.status, "endpoint") }
        if let value = leg.meters, let prior = meters { meters = prior + value } else { meters = nil; append(&result.unresolved, "distance_unknown", "endpoint") }
        result.finish = clock.flatMap { c in leg.minutes.map { c + $0 } }
        if let finish = result.finish, finish > trip.return_deadline { append(&result.conflicts, "return_deadline_exceeded", "endpoint") }
        result.driving = result.finish == nil ? nil : driving; result.meters = meters; result.soft_deviation = soft
        return result
    }
    static func key(_ trip: V4Trip, _ row: V4Schedule) -> [Int] {
        let cost = trip.objective == "driving" ? row.driving! : trip.objective == "earliest_return" ? row.finish! : row.finish! - row.spec.departure
        return [row.soft_deviation!, cost, row.spec.waits.reduce(0, +)]
    }
    static func shortlist(_ trip: V4Trip, _ screens: [V4Schedule], size: Int) -> [V4Spec] {
        let complete = screens.filter(\.eligible); var selected: [V4Spec] = []
        func add(_ row: V4Schedule) { if selected.count < size && !selected.contains(row.spec) { selected.append(row.spec) } }
        func stable(_ rows: [V4Schedule], _ value: (V4Schedule) -> [Int]) -> [V4Schedule] {
            rows.enumerated().sorted { a, b in let x = value(a.element), y = value(b.element); return x == y ? a.offset < b.offset : x.lexicographicallyPrecedes(y) }.map(\.element)
        }
        if !complete.isEmpty {
            let ordered = stable(complete) { key(trip, $0) }
            let families = [ordered, stable(complete) { [$0.finish! - $0.spec.departure, $0.spec.departure] }, stable(complete) { [$0.driving!] }, stable(complete.filter { $0.meters != nil }) { [$0.meters!] }]
            for family in families { if let first = family.first { add(first) } }
            var chosen = Set(selected.map(\.order))
            for row in ordered where !chosen.contains(row.spec.order) { add(row); chosen.insert(row.spec.order) }
            for row in ordered { add(row) }
        }
        for row in screens { add(row) }
        return selected
    }
    static func search(_ trip: V4Trip, size: Int = 5, quoteLimit: Int? = 72, bounded: Bool = true,
                       proxy: (String, String, Int) -> V4Quote,
                       quote: (String, String, Int) async throws -> V4Quote) async throws -> V4SearchResult {
        let domain = try specs(trip)
        let chosen: [V4Spec]
        if bounded {
            let screens = domain.map { evaluate(trip, $0, quote: proxy) }
            chosen = shortlist(trip, screens, size: size)
        } else { chosen = domain }
        struct CacheKey: Hashable { var from: String; var to: String; var at: Int }
        var cache: [CacheKey: V4Quote] = [:]; var count = 0; var exhausted = false; var rows: [V4Schedule] = []
        // Evaluate synchronously against an incrementally filled exact-time cache; each pass
        // discovers the next missing quote, which is fetched before resuming the candidate.
        for spec in chosen {
            while true {
                var missing: CacheKey?
                let row = evaluate(trip, spec) { from, to, at in
                    let k = CacheKey(from: from, to: to, at: at)
                    if let q = cache[k] { return q }
                    if missing == nil { missing = k }
                    return V4Quote(minutes: nil, meters: nil, status: "pending")
                }
                guard let k = missing else { rows.append(row); break }
                if let quoteLimit, count >= quoteLimit {
                    exhausted = true; cache[k] = .init(minutes: nil, meters: nil, status: "quote_budget_exhausted")
                } else { count += 1; cache[k] = try await quote(k.from, k.to, k.at) }
            }
        }
        let eligible = rows.filter(\.eligible)
        let best = eligible.enumerated().min { a, b in let x = key(trip, a.element), y = key(trip, b.element); return x == y ? a.offset < b.offset : x.lexicographicallyPrecedes(y) }?.element
        return .init(localCandidates: domain.count, evaluated: rows, recommended: best, quoteCalls: count, exhausted: exhausted)
    }
}
