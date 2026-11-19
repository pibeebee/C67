import Foundation
import C67Domain

/// V4.1 keeps the v4 evaluator and adds bounded expansion, boundary seeds and explicit preference ranking.
enum V41Planner {
    private struct Candidate {
        var index: Int
        var spec: V4Spec
        var priority: [Int]
    }
    struct Result: Sendable {
        var selected: V4Schedule?
        var assessment: PlanningScheduleAssessment
        var blockedByRegularHours: Bool
    }

    static func search(_ original: V4Trip, input: PlanningInput, modelTargets: [String: V4Target],
                       routes: V41RouteSession) async throws -> Result {
        let trip = original
        await routes.startSearch()
        var domain = try V4Planner.specs(trip)
        var visited = Set<V4Spec>()
        var rows: [V4Schedule] = []
        var best: V4Schedule?
        var bestKey: [Int]?
        var batchCount = 0
        while !domain.isEmpty {
            try Task.checkCancellation()
            let proxies = await routes.proxies
            let failures = await routes.failedPairs
            let coveredStarts = Set(rows.compactMap { $0.spec.order.first })
            let coveredEnds = Set(rows.compactMap { $0.spec.order.last })
            var candidates: [Candidate] = []
            for (index, spec) in domain.enumerated() {
                let screen = screen(trip, spec, input: input, proxies: proxies)
                let pairs = zip([trip.origin] + spec.order, spec.order + [trip.endpoint]).map { pair in
                    V41RouteSession.Pair(from: pair.0, to: pair.1)
                }
                let failedCount = pairs.filter { failures.contains($0) }.count
                let coverage = (coveredStarts.contains(spec.order[0]) ? 1 : 0) + (coveredEnds.contains(spec.order.last!) ? 1 : 0)
                var priority = [failedCount, screen.conflicts.count + screen.regular_conflicts.count, coverage, screen.eligible ? 0 : 1]
                priority += screen.eligible ? rank(trip, screen, input: input, modelTargets: modelTargets) : [0, 0, 0, 0, 0, 0]
                candidates.append(.init(index: index, spec: spec, priority: priority))
            }
            candidates.sort { a, b in
                a.priority == b.priority ? a.index < b.index : a.priority.lexicographicallyPrecedes(b.priority)
            }
            var batch: [V4Spec] = []
            var orders = Set<[String]>()
            var starts = Set<String>()
            for candidate in candidates {
                let diverse = batchCount == 0 ? orders.insert(candidate.spec.order).inserted : starts.insert(candidate.spec.order[0]).inserted
                guard diverse else { continue }
                batch.append(candidate.spec)
                if batch.count == 5 { break }
            }
            for candidate in candidates where batch.count < 5 && !batch.contains(candidate.spec) { batch.append(candidate.spec) }
            for spec in batch {
                guard await routes.reserveCandidate() else { break }
                let row = try await evaluate(trip, spec, input: input, routes: routes)
                visited.insert(spec)
                rows.append(row)
                if let waiting = preferredWaitSeed(trip, row, modelTargets: modelTargets),
                   !visited.contains(waiting), !domain.contains(waiting) { domain.append(waiting) }
                if row.eligible {
                    let key = rank(trip, row, input: input, modelTargets: modelTargets)
                    if bestKey == nil || key.lexicographicallyPrecedes(bestKey!) { best = row; bestKey = key }
                }
                if await routes.stopReason != nil { break }
            }
            batchCount += 1
            domain.removeAll { visited.contains($0) }
            if batchCount == 1, input.enginePreferences?.flexibleDeparture == true {
                let extra = boundarySeeds(trip, input: input, modelTargets: modelTargets, proxies: await routes.proxies)
                let existing = Set(domain).union(visited)
                domain.append(contentsOf: extra.filter { !existing.contains($0) })
            }
            let stopped = await routes.stopReason != nil
            let preferenceMatched = bestKey?.prefix(4).allSatisfy { $0 == 0 } == true
            let checkedStarts = Set(rows.compactMap { $0.spec.order.first })
            let unexploredStart = domain.contains { !checkedStarts.contains($0.order[0]) }
            let checkedEnds = Set(rows.compactMap { $0.spec.order.last })
            let unexploredEnd = domain.contains { !checkedEnds.contains($0.order.last!) }
            let latestProxies = await routes.proxies
            let promising = domain.contains { spec in
                let estimate = screen(trip, spec, input: input, proxies: latestProxies)
                guard estimate.eligible, let bestKey else { return false }
                return rank(trip, estimate, input: input, modelTargets: modelTargets).lexicographicallyPrecedes(bestKey)
            }
            let refine = batchCount < 3 && (unexploredStart || unexploredEnd || !preferenceMatched || promising)
            if stopped || (best != nil && !refine) { break }
        }
        var assessment = PlanningScheduleAssessment()
        assessment.generatedCandidates = visited.count + domain.count
        assessment.evaluatedCandidates = rows.count
        assessment.completeCandidates = rows.filter(\.eligible).count
        assessment.routeCalls = await routes.calls
        assessment.stopReason = await routes.stopReason ?? (domain.isEmpty ? "domain_exhausted" : "candidate_batch_complete")
        let routeStopped = await routes.stopReason != nil
        assessment.allCandidatesMissedDeadline = !routeStopped && domain.isEmpty && !rows.isEmpty && rows.allSatisfy {
            $0.conflicts.contains { $0.code == "return_deadline_exceeded" }
        }
        func issues(_ values: [V4Issue]) -> [PlanningScheduleIssue] {
            var seen = Set<String>()
            return values.map { PlanningScheduleIssue(code: $0.code, placeID: UUID(uuidString: $0.place), source: $0.source) }
                .filter { seen.insert($0.id).inserted }
        }
        let reported = best.map { [$0] } ?? rows
        assessment.conflicts = issues(reported.flatMap(\.conflicts))
        assessment.regularConflicts = issues(reported.flatMap(\.regular_conflicts))
        assessment.unresolved = issues(reported.flatMap(\.unresolved))
        if let best {
            assessment.remainingMinutes = best.finish.map { trip.return_deadline - $0 }
            assessment.preferredPeriodOutsideMinutes = periodDeviation(best, input: input)
        }
        let blockedByRegularHours = best == nil && !routeStopped && domain.isEmpty && !rows.isEmpty &&
            rows.allSatisfy { row in
                row.finish != nil && row.conflicts.allSatisfy { $0.code == "return_deadline_exceeded" } &&
                    (!row.regular_conflicts.isEmpty || !row.conflicts.isEmpty)
            } && rows.contains { !$0.regular_conflicts.isEmpty }
        return .init(selected: best, assessment: assessment, blockedByRegularHours: blockedByRegularHours)
    }

    private static func screen(_ trip: V4Trip, _ spec: V4Spec, input: PlanningInput,
                               proxies: [V41RouteSession.Pair: V4Quote]) -> V4Schedule {
        V4Planner.evaluate(trip, spec) { from, to, _ in
            if to == "endpoint", input.enginePreferences?.endPoint == nil, input.enginePreferences?.returnToOrigin != true {
                return .init(minutes: 0, meters: 0, status: "no_endpoint")
            }
            return proxies[.init(from: from, to: to)] ?? .init(minutes: nil, meters: nil, status: "proxy_unavailable")
        }
    }

    private static func evaluate(_ trip: V4Trip, _ initial: V4Spec, input: PlanningInput, routes: V41RouteSession) async throws -> V4Schedule {
        var spec = initial
        var evaluationTrip = trip
        for index in evaluationTrip.stops.indices {
            for window in evaluationTrip.stops[index].hours.windows.indices {
                evaluationTrip.stops[index].hours.windows[window].last_entry = nil
            }
        }
        var quotes: [V41RouteSession.Key: V4Quote] = [:]
        while true {
            var missing: V41RouteSession.Key?
            var row = V4Planner.evaluate(evaluationTrip, spec) { from, to, minute in
                let key = V41RouteSession.Key(from: from, to: to, minute: minute)
                if let quote = quotes[key] { return quote }
                if missing == nil { missing = key }
                return .init(minutes: nil, meters: nil, status: "pending")
            }
            // Insert the earliest necessary wait only within the traveller's explicit allowance.
            var adjusted = false
            for (index, visit) in row.visits.enumerated() {
                guard let arrival = visit.arrival, let duration = visit.duration,
                      let stop = trip.stops.first(where: { $0.id == visit.id }) else { continue }
                var start = arrival
                if let target = stop.target, target.strength == "hard" { start = max(start, target.earliest) }
                if ["regular", "confirmed"].contains(stop.hours.kind),
                   let window = stop.hours.windows.first(where: { max(start, $0.opens) + duration <= $0.closes }) {
                    start = max(start, window.opens)
                }
                let wait = max(initial.waits[index], start - arrival, 0)
                let total = spec.waits.reduce(0, +) - spec.waits[index] + wait
                if wait != spec.waits[index], wait <= (trip.waiting.per_stop ?? 0), total <= (trip.waiting.total ?? 0) {
                    spec.waits[index] = wait
                    adjusted = true
                    break
                }
            }
            if adjusted { continue }
            if let missing {
                quotes[missing] = try await routes.quote(missing.from, missing.to, missing.minute)
                continue
            }
            for visit in row.visits {
                if let arrival = visit.arrival, let start = visit.start, let end = visit.end,
                   let stop = trip.stops.first(where: { $0.id == visit.id }),
                   let window = stop.hours.windows.first(where: { $0.opens <= start && end <= $0.closes }),
                   let cutoff = window.last_entry, max(arrival, window.opens) > cutoff {
                    row.conflicts.append(.init(code: "visit_outside_hours_or_entry", place: visit.id, source: stop.hours.source))
                }
                if let session = input.places.first(where: { $0.id.uuidString == visit.id })?.activitySession,
                   let cutoff = session.arriveBy, let arrival = visit.arrival,
                   arrival > Int(floor(cutoff.timeIntervalSince1970 / 60)) {
                    row.conflicts.append(.init(code: "session_arrival_missed", place: visit.id, source: "traveller_session"))
                }
            }
            return row
        }
    }

    static func rank(_ trip: V4Trip, _ row: V4Schedule, input: PlanningInput, modelTargets: [String: V4Target]) -> [Int] {
        let modelDeviation = row.visits.reduce(0) { total, visit in
            guard let target = modelTargets[visit.id], let start = visit.start else { return total }
            return total + max(target.earliest - start, 0, start - target.latest)
        }
        let estimatedHoursDeviation = row.visits.reduce(0) { total, visit in
            guard let hours = trip.stops.first(where: { $0.id == visit.id })?.hours, hours.kind == "estimated",
                  let window = hours.windows.first, let start = visit.start, let end = visit.end else { return total }
            return total + end - start - max(0, min(end, window.closes) - max(start, window.opens))
        }
        return [row.soft_deviation ?? Int.max, periodDeviation(row, input: input), modelDeviation, estimatedHoursDeviation,
                (row.finish ?? trip.return_deadline) - row.spec.departure, row.spec.waits.reduce(0, +)]
    }

    private static func preferredWaitSeed(_ trip: V4Trip, _ row: V4Schedule, modelTargets: [String: V4Target]) -> V4Spec? {
        for (index, visit) in row.visits.enumerated() {
            let target = trip.stops.first { $0.id == visit.id }?.target ?? modelTargets[visit.id]
            guard let target, target.strength == "soft", let arrival = visit.arrival, let start = visit.start,
                  target.earliest > start else { continue }
            var spec = row.spec
            let wait = target.earliest - arrival
            spec.waits[index] = wait
            if wait <= (trip.waiting.per_stop ?? 0), spec.waits.reduce(0, +) <= (trip.waiting.total ?? 0) { return spec }
        }
        return nil
    }

    private static func periodDeviation(_ row: V4Schedule, input: PlanningInput) -> Int {
        guard let part = input.enginePreferences?.preferredDayPart, let zone = TimeZone(identifier: input.timeZone) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let midnight = calendar.startOfDay(for: input.startsAt)
        let range = part.minuteRange
        let lower = Int(midnight.addingTimeInterval(Double(range.lowerBound * 60)).timeIntervalSince1970 / 60)
        let upper = Int(midnight.addingTimeInterval(Double(range.upperBound * 60)).timeIntervalSince1970 / 60)
        return row.visits.reduce(0) { total, visit in
            guard let start = visit.start, let end = visit.end else { return total }
            return total + (end - start) - max(0, min(end, upper) - max(start, lower))
        }
    }

    private static func boundarySeeds(_ trip: V4Trip, input: PlanningInput, modelTargets: [String: V4Target],
                                      proxies: [V41RouteSession.Pair: V4Quote]) -> [V4Spec] {
        guard let base = try? V4Planner.specs({ var copy = trip; copy.departures = [trip.earliest_departure]; return copy }()) else { return [] }
        var extra: [V4Spec] = []
        for spec in base {
            var elapsed = 0
            var from = trip.origin
            for id in spec.order {
                guard let minutes = proxies[.init(from: from, to: id)]?.minutes,
                      let stop = trip.stops.first(where: { $0.id == id }), let duration = stop.duration else { break }
                elapsed += minutes
                var anchors = stop.hours.windows.map(\.opens)
                if let target = stop.target { anchors.append(target.earliest) }
                if let target = modelTargets[id] { anchors.append(target.earliest) }
                if let part = input.enginePreferences?.preferredDayPart, let zone = TimeZone(identifier: input.timeZone) {
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                    anchors.append(Int(calendar.startOfDay(for: input.startsAt).timeIntervalSince1970 / 60) + part.minuteRange.lowerBound)
                }
                for anchor in anchors {
                    let departure = anchor - elapsed
                    if departure >= trip.earliest_departure, departure < trip.return_deadline {
                        extra.append(.init(order: spec.order, departure: departure, waits: spec.waits))
                    }
                }
                elapsed += duration.target
                from = id
            }
        }
        return Array(Set(extra)).sorted { a, b in
            a.departure == b.departure ? a.order.joined() < b.order.joined() : a.departure < b.departure
        }
    }
}
