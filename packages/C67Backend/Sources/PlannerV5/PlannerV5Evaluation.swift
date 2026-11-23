import C67Domain
import Foundation

extension PlannerV5 {
    func evaluate(_ candidate: Candidate, day: Day, durations: [Int], work: inout Work) async throws -> Evaluation {
        var clock = candidate.departure
        var from = day.origin
        var visits: [PlannerV5Visit] = []
        var legs: [PlannerV5Leg] = []
        var metrics: [PlannerV5Metric] = []
        var checkIns: [PlannerV51CheckIn] = []
        var outdoorVisits: [PlannerV51OutdoorVisit] = []
        var waiting = 0
        var preference = 0
        var driving = 0

        for to in candidate.order + (day.endpoint.map { [$0] } ?? []) {
            let fromID = from < day.stops.count ? day.stops[from].place.id : nil
            let toID = to < day.stops.count ? day.stops[to].place.id : nil
            let key = Key(from: from, to: to, minute: clock)
            let quote = try await lookup(key, day: day, work: &work)
            if work.limit != nil { return .limited }
            guard let quote else { return .missing(.etaUnavailable(from: fromID, to: toID)) }
            let travel = (quote.seconds + 59) / 60
            let arrival = clock + travel
            legs.append(.init(from: fromID, to: toID, departsAt: Self.date(clock),
                              arrivesAt: Self.date(arrival), route: quote))
            clock = arrival
            driving += travel
            from = to
            guard arrival <= day.end else { return .conflict(.deadline) }
            guard toID != nil else { continue }

            let stop = day.stops[to]
            let place = stop.place
            let session = place.activitySession
            let arrivalDate = Self.date(arrival)
            if let session {
                let deadline = min(session.arriveBy ?? session.startsAt, session.startsAt)
                if arrivalDate > deadline { return .conflict(.checkIn(place.id)) }
                if let target = bufferTarget(day) {
                    let buffer = deadline.timeIntervalSince(arrivalDate) / 60
                    checkIns.append(.init(placeID: place.id, deadline: deadline, arrival: arrivalDate,
                                          targetMinutes: target, bufferMinutes: buffer,
                                          shortfallMinutes: max(0, Double(target) - buffer)))
                }
            }
            let hard = place.visitTiming == .required || place.visitTiming == .notBefore
            let earliest = hard ? max(arrival, place.preferredAfter.map { Self.minute($0, rounding: .up) } ?? arrival) : arrival
            let latest = place.visitTiming == .required ? place.preferredBefore.map { Self.minute($0) } ?? day.end : day.end
            if earliest > latest { return .conflict(.visitTime(place.id)) }
            let latestStart = place.visitTiming == .required ? place.preferredBefore ?? Self.date(day.end) : Self.date(day.end)
            if let session, session.startsAt < Self.date(earliest) || session.startsAt > latestStart {
                return .conflict(.visitTime(place.id))
            }

            let start: Date
            let end: Date
            let length = durations[to]
            if let access = stop.access {
                let possible = access.windows.compactMap { window -> Date? in
                    let openingMinute = Self.minute(window.interval.start, rounding: .up)
                    let proposed = session?.startsAt ?? Self.date(max(earliest, openingMinute))
                    let finish = session?.endsAt ?? proposed.addingTimeInterval(Double(length) * 60)
                    guard proposed >= window.interval.start, proposed < window.interval.end, finish <= window.interval.end,
                          window.lastEntry.map({ proposed <= $0 }) ?? true else { return nil }
                    return proposed
                }
                guard let first = possible.min() else { return .conflict(.access(place.id)) }
                start = first
                end = session?.endsAt ?? start.addingTimeInterval(Double(length) * 60)
            } else {
                start = session?.startsAt ?? Self.date(earliest)
                end = session?.endsAt ?? start.addingTimeInterval(Double(length) * 60)
            }
            if start > latestStart { return .conflict(.visitTime(place.id)) }
            let waitingHere = Int(ceil(start.timeIntervalSince(arrivalDate) / 60))
            waiting += waitingHere
            if waiting > day.wait { return .conflict(.waiting(place.id)) }
            clock = Self.minute(end, rounding: .up)
            if clock > day.end { return .conflict(.deadline) }

            let startMinute = Self.minute(start, rounding: .up)
            if place.visitTiming == .preferred {
                let early = place.preferredAfter.map { Self.minute($0, rounding: .up) - startMinute } ?? 0
                let late = place.preferredBefore.map { startMinute - Self.minute($0) } ?? 0
                preference += max(0, early, late)
            }
            if let dayPart = day.dayPart {
                preference += max(0, clock - startMinute - max(0, min(clock, dayPart.upperBound) - max(startMinute, dayPart.lowerBound)))
            }
            var duration = stop.duration
            duration.target = length
            visits.append(.init(placeID: place.id, arrivesAt: arrivalDate, startsAt: start, endsAt: end,
                                duration: duration, activity: stop.context.activity, activitySource: stop.context.activitySource,
                                exposure: stop.exposure, exposureSource: stop.exposure == nil ? nil : stop.context.exposureSource,
                                accessSource: stop.access?.source, unverifiedAccess: stop.access?.source != .traveller))
            if checkInBufferMinutes != nil, stop.exposure == .outdoor {
                outdoorVisits.append(outdoorVisit(stop, start: start, end: end))
            }
            metrics += day.goals(stop).map { metric($0, stop: stop, start: start, end: end) }
        }
        return .complete(.init(departsAt: Self.date(candidate.departure), finishesAt: Self.date(clock), visits: visits,
                               legs: legs, drivingMinutes: driving, waitingMinutes: waiting,
                               preferredTimeDeviation: preference, metrics: metrics,
                               checkIns: checkIns, outdoorVisits: outdoorVisits))
    }

    private func lookup(_ key: Key, day: Day, work: inout Work) async throws -> PlannerV5Route? {
        try Task.checkCancellation()
        let from = day.points[key.from]
        let to = day.points[key.to]
        if from == to { return .init(seconds: 0, meters: 0) }
        if let cached = work.routes[key] { return cached }
        if work.missing.contains(key) { return nil }
        guard work.quotes < 72 else {
            work.limit = .routeQuotes
            return nil
        }

        work.quotes += 1
        let quote: PlannerV5Route?
        do {
            quote = try await route(from, to, Self.date(key.minute), day.input.trip.mode)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            work.missing.insert(key)
            return nil
        }
        guard let quote, (0 ... 604_800).contains(quote.seconds), (quote.meters ?? 0) >= 0 else {
            work.missing.insert(key)
            return nil
        }
        work.routes[key] = quote
        return quote
    }

    func faster(_ left: PlannerV5Schedule, _ right: PlannerV5Schedule) -> Bool {
        let lhs = (left.preferredTimeDeviation, left.drivingMinutes, left.waitingMinutes, left.departsAt)
        let rhs = (right.preferredTimeDeviation, right.drivingMinutes, right.waitingMinutes, right.departsAt)
        if lhs != rhs { return lhs < rhs }
        return left.visits.map { $0.placeID.uuidString }.lexicographicallyPrecedes(right.visits.map { $0.placeID.uuidString })
    }

    /// Compare matching evidence only and preserve the baseline when requested goals conflict.
    func improves(_ candidate: PlannerV5Schedule, over baseline: PlannerV5Schedule) -> Bool {
        var gain = false
        for original in baseline.metrics {
            let new = candidate.metrics.first { $0.placeID == original.placeID && $0.goal == original.goal }
            switch (original.value, new?.value) {
            case (nil, nil): continue
            case let (old?, value?):
                guard original.sources == new?.sources else { return false }
                let difference = original.goal == .avoidRain ? old - value : value - old
                if difference < -1e-8 { return false }
                if difference > 1e-8 { gain = true }
            default: return false
            }
        }
        return gain
    }

    private func metric(_ goal: PlannerV5Goal, stop: Stop, start: Date, end: Date) -> PlannerV5Metric {
        var value: Double?
        var sources: [String] = []
        switch goal {
        case .avoidRain:
            if stop.exposure == .outdoor {
                return rainMetric(stop, start: start, end: end)
            }
        case .sunrise, .sunset, .goldenHour:
            if let source = stop.context.lightSource, !source.isEmpty {
                let windows = stop.context.light.compactMap { light -> DateInterval? in
                    guard case let .goldenHour(window) = light else { return nil }
                    return window
                }.sorted { $0.start < $1.start }
                if goal == .goldenHour, !windows.isEmpty {
                    var cursor = start
                    var minutes = 0.0
                    for window in windows {
                        let lower = max(window.start, cursor)
                        let upper = min(window.end, end)
                        if upper > lower {
                            minutes += upper.timeIntervalSince(lower) / 60
                            cursor = upper
                        }
                    }
                    value = minutes
                } else {
                    let events = stop.context.light.compactMap { light -> Date? in
                        switch (goal, light) {
                        case let (.sunrise, .sunrise(date)), let (.sunset, .sunset(date)): date
                        default: nil
                        }
                    }
                    if !events.isEmpty { value = events.contains { start <= $0 && $0 < end } ? 1 : 0 }
                }
                if value != nil { sources = [source] }
            }
        }
        return .init(placeID: stop.place.id, goal: goal, value: value, sources: sources)
    }

    func rainMetric(_ stop: Stop, start: Date, end: Date) -> PlannerV5Metric {
        let records = stop.context.rain.filter { $0.interval.start < end && $0.interval.end > start }
            .sorted { $0.interval.start < $1.interval.start }
        let unknown = PlannerV5Metric(placeID: stop.place.id, goal: .avoidRain, value: nil, sources: [])
        var cursor = start
        var weightedMinutes = 0.0
        for row in records {
            let lower = max(row.interval.start, start)
            let upper = min(row.interval.end, end)
            guard cursor == lower, upper > lower, (0 ... 1).contains(row.probability),
                  !row.source.isEmpty else { return unknown }
            cursor = upper
            weightedMinutes += upper.timeIntervalSince(lower) / 60 * row.probability
        }
        let providers = Set(records.map(\.source))
        guard cursor == end, providers.count == 1 else { return unknown }
        return .init(placeID: stop.place.id, goal: .avoidRain, value: weightedMinutes, sources: providers.sorted())
    }

    func boundaries(_ stop: Stop) -> [Int] {
        let visitTimes = [stop.place.activitySession?.startsAt, stop.place.activitySession?.arriveBy,
                          stop.place.preferredAfter, stop.place.preferredBefore].compactMap { $0 }
        let access = stop.access?.windows.flatMap { [$0.interval.start, $0.interval.end] + ($0.lastEntry.map { [$0] } ?? []) } ?? []
        let light = stop.context.light.flatMap { light -> [Date] in
            switch light {
            case let .sunrise(date), let .sunset(date): [date]
            case let .goldenHour(window): [window.start, window.end]
            }
        }
        return (visitTimes + access + light).map { Self.minute($0) }
    }

    func sensitivityMinutes(_ day: Day, index: Int, schedule: PlannerV5Schedule?) -> [Int] {
        let stop = day.stops[index]
        let range = stop.duration.minutes
        var values = Set([range.lowerBound, range.upperBound])
        if let schedule, let position = schedule.visits.firstIndex(where: { $0.placeID == stop.place.id }) {
            let byID = Dictionary(uniqueKeysWithValues: day.stops.map { ($0.place.id, $0) })
            for (offset, visit) in schedule.visits[position...].enumerated() {
                guard let affected = byID[visit.placeID] else { continue }
                let anchors = boundaries(affected) + v51Anchors(affected, day: day)
                let references = offset == 0 ? [visit.endsAt] : [visit.arrivesAt, visit.startsAt, visit.endsAt]
                for reference in references {
                    for anchor in anchors + [day.end] {
                        let difference = anchor - Self.minute(reference)
                        for value in [stop.duration.target + difference, stop.duration.target + difference + 1]
                        where range.contains(value) {
                            values.insert(value)
                        }
                    }
                }
            }
        }
        values.remove(stop.duration.target)
        return [range.lowerBound, range.upperBound].filter { values.remove($0) != nil } + values.sorted()
    }
}
