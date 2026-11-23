import C67Domain
import Foundation

extension PlannerV5 {
    struct Key: Hashable {
        let from: Int
        let to: Int
        let minute: Int
    }

    struct Work: Sendable {
        var routes: [Key: PlannerV5Route] = [:]
        var missing: Set<Key> = []
        var quotes = 0
        var candidates = 0
        var limit: PlannerV5Limit?
    }

    struct Stop {
        let place: PlanningPlace
        let context: PlannerV5VisitContext
        let duration: PlannerV5Duration
        let access: PlannerV5Access?
        let exposure: PlannerV5Exposure?
    }

    struct Day {
        let input: PlannerV5Input
        let start: Int
        let end: Int
        let stops: [Stop]
        let dayPart: Range<Int>?
        let orders: [[Int]]
        let points: [PlanningPoint]
        let wait: Int

        init(_ input: PlannerV5Input) throws {
            self.input = input
            let trip = input.trip
            start = PlannerV5.minute(trip.startsAt, rounding: .up)
            end = PlannerV5.minute(trip.finishBy, rounding: .down)
            wait = trip.enginePreferences?.maximumWaitMinutes ?? 0
            guard let zone = TimeZone(identifier: trip.timeZone) else { throw PlannerV5Error.invalidInput }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            if let part = trip.enginePreferences?.preferredDayPart {
                let midnight = calendar.startOfDay(for: trip.startsAt)
                let bounds = part.minuteRange
                guard let lower = calendar.date(byAdding: .minute, value: bounds.lowerBound, to: midnight),
                      let upper = calendar.date(byAdding: .minute, value: bounds.upperBound, to: midnight) else {
                    throw PlannerV5Error.invalidInput
                }
                dayPart = PlannerV5.minute(lower) ..< PlannerV5.minute(upper)
            } else { dayPart = nil }
            stops = try trip.places.map { place in
                let context = input.visits[place.id] ?? .init()
                let duration: PlannerV5Duration
                if let session = place.activitySession {
                    let length = Int(ceil(session.endsAt.timeIntervalSince(session.startsAt) / 60))
                    duration = .init(minutes: length ... length, target: length, source: .reservation)
                } else if place.hasExplicitVisitDuration {
                    let length = (place.visitSeconds + 59) / 60
                    duration = .init(minutes: length ... length, target: length, source: .traveller)
                } else if let supplied = context.duration {
                    duration = supplied
                } else {
                    let base = place.visitSeconds > 0 ? (min(place.visitSeconds, 86_400) + 59) / 60 : 30
                    let target = min(1440, base + (place.id == trip.enginePreferences?.mainSpotID ? 15 : 0))
                    duration = .init(minutes: max(1, target - 15) ... min(1440, target + 15),
                                     target: target, source: .localEstimate)
                }
                let minimum = context.duration?.source == .observed("active_visit") ? 0 : 1
                guard duration.minutes.contains(duration.target), duration.minutes.lowerBound >= minimum,
                      duration.minutes.upperBound <= 1440 else { throw PlannerV5Error.invalidInput }
                let access: PlannerV5Access?
                if let confirmation = place.visitConfirmation, confirmation.publicAccessConfirmed {
                    guard confirmation.opensAt < confirmation.closesAt else { throw PlannerV5Error.invalidInput }
                    let interval = DateInterval(start: confirmation.opensAt, end: confirmation.closesAt)
                    access = .init(windows: [.init(interval, lastEntry: confirmation.lastEntryAt)], source: .traveller)
                } else if let supplied = context.access {
                    switch supplied.source {
                    case .traveller, .reservation, .venue: access = supplied
                    default: access = nil
                    }
                } else { access = nil }
                let exposure: PlannerV5Exposure?
                switch context.exposureSource {
                case .traveller?, .reservation?, .venue(_)?, .observed(_)?: exposure = context.exposure
                default: exposure = nil
                }
                return Stop(place: place, context: context, duration: duration, access: access, exposure: exposure)
            }
            let indices = Array(trip.places.indices)
            let allOrders = trip.preservesPlaceOrder ? [indices] : PlannerV5.permutations(indices)
            orders = allOrders.filter { order in
                (trip.firstPlaceID == nil || trip.places[order[0]].id == trip.firstPlaceID) &&
                    (trip.enginePreferences?.lastPlaceID == nil ||
                        trip.places[order[order.count - 1]].id == trip.enginePreferences?.lastPlaceID)
            }
            points = trip.places.map(\.location) + [trip.origin] + (trip.planningEndpoint.map { [$0] } ?? [])
            guard points.allSatisfy({ abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }) else {
                throw PlannerV5Error.invalidInput
            }
        }

        var origin: Int { stops.count }
        var endpoint: Int? { points.count == stops.count + 2 ? stops.count + 1 : nil }

        func goals(_ stop: Stop) -> [PlannerV5Goal] {
            var goals = stop.context.goals
            if input.trip.enginePreferences?.avoidRain == true { goals.insert(.avoidRain) }
            return [.avoidRain, .sunrise, .sunset, .goldenHour].filter { goals.contains($0) }
        }
    }

    struct Candidate: Hashable {
        let order: [Int]
        let departure: Int
    }

    enum Evaluation {
        case complete(PlannerV5Schedule)
        case conflict(PlannerV5Issue)
        case missing(PlannerV5Issue)
        case limited
    }

    struct Search {
        var selected: PlannerV5Schedule?
        var fastest: PlannerV5Schedule?
        var completeCandidates = 0
        var missingETA = false
        var alternative: PlannerV5Schedule?
        var issues: [PlannerV5Issue] = []
        var status: PlannerV5Status = .incomplete
        var partial = false
        var uncertainExposure: [UUID] = []
    }

    static func minute(_ date: Date, rounding: FloatingPointRoundingRule = .down) -> Int {
        let value = date.timeIntervalSince1970 / 60
        // Saturate an out-of-domain provider boundary before converting it to an integer.
        if value.isNaN { return Int.max / 4 }
        return Int(min(Double(Int.max / 4), max(Double(Int.min / 4), value.rounded(rounding))))
    }

    static func date(_ minute: Int) -> Date {
        Date(timeIntervalSince1970: Double(minute) * 60)
    }

    private static func permutations(_ values: [Int]) -> [[Int]] {
        guard values.count > 1 else { return [values] }
        return values.indices.flatMap { index -> [[Int]] in
            var tail = values
            let first = tail.remove(at: index)
            return permutations(tail).map { [first] + $0 }
        }
    }

    func search(_ day: Day, durations: [Int], work: inout Work) async throws -> Search {
        try Task.checkCancellation()
        if day.orders.isEmpty { throw PlannerV5Error.invalidInput }
        if durations.reduce(0, +) > day.end - day.start {
            return .init(issues: [.deadline], status: .conflicts)
        }
        let latestDeparture = day.end - durations.reduce(0, +)
        let flexible = day.input.trip.enginePreferences?.flexibleDeparture == true
        let departures = flexible ? Array(stride(from: day.start, through: latestDeparture, by: 30)) : [day.start]
        let v51Boundaries = day.stops.map { v51Anchors($0, day: day) }
        var domain = day.orders.flatMap { order in departures.map { Candidate(order: order, departure: $0) } }
        if flexible {
            for order in day.orders {
                var elapsed = 0
                for index in order {
                    let stop = day.stops[index]
                    let windows = stop.access?.windows.map { Self.minute($0.interval.start, rounding: .up) } ?? []
                    let anchors = windows + boundaries(stop) + v51Boundaries[index]
                    for boundary in anchors {
                        for departure in [boundary - elapsed, boundary - elapsed - durations[index] + 1]
                        where departure >= day.start && departure <= latestDeparture {
                            domain.append(.init(order: order, departure: departure))
                        }
                    }
                    elapsed += durations[index]
                }
            }
        }

        var unseen = Set(domain)
        var evaluated: Set<Candidate> = []
        var usedOrders: Set<[Int]> = []
        var schedules: [PlannerV5Schedule] = []
        var result = Search()
        var checked = 0
        let anchors = day.stops.indices.map { boundaries(day.stops[$0]) + v51Boundaries[$0] }
        while !unseen.isEmpty {
            try Task.checkCancellation()
            guard work.limit == nil else { break }
            if work.candidates >= 500 {
                work.limit = .candidates
                break
            }
            let proxies = Dictionary(grouping: work.routes.keys) { [$0.from, $0.to] }
            let snapshot = work
            let rankedCandidate = unseen.lazy.map { candidate in
                (candidate, priority(candidate, day: day, durations: durations, work: snapshot,
                                     proxies: proxies, usedOrders: usedOrders, anchors: anchors))
            }.min { left, right in
                if left.1 != right.1 { return left.1.lexicographicallyPrecedes(right.1) }
                if left.0.departure != right.0.departure { return left.0.departure < right.0.departure }
                return left.0.order.lexicographicallyPrecedes(right.0.order)
            }!
            let candidate = rankedCandidate.0
            if checked >= 3, let best = schedules.min(by: faster) {
                let estimate = priority(candidate, day: day, durations: durations, work: work, proxies: proxies, usedOrders: [candidate.order], anchors: anchors)
                if checked >= 12 || (checkInBufferMinutes == nil && best.preferredTimeDeviation == 0 &&
                    estimate[2] > best.drivingMinutes + day.input.extraTravelMinutes && estimate[3] == 0) {
                    break
                }
            } else if checked >= 24 {
                break
            }
            unseen.remove(candidate)
            if flexible, checkInBufferMinutes != nil { evaluated.insert(candidate) }
            usedOrders.insert(candidate.order)
            checked += 1
            work.candidates += 1
            switch try await evaluate(candidate, day: day, durations: durations, work: &work) {
            case let .complete(schedule):
                schedules.append(schedule)
                if flexible, checkInBufferMinutes != nil {
                    for (index, visit) in zip(candidate.order, schedule.visits) {
                        for boundary in v51Boundaries[index] {
                            let anchors = [visit.arrivesAt, visit.startsAt, visit.endsAt]
                            for time in anchors {
                                let departure = candidate.departure + boundary - Self.minute(time)
                                let shifted = Candidate(order: candidate.order, departure: departure)
                                if (day.start ... latestDeparture).contains(departure), !evaluated.contains(shifted) {
                                    unseen.insert(shifted)
                                }
                            }
                        }
                    }
                }
            case let .conflict(issue): if !result.issues.contains(issue) { result.issues.append(issue) }
            case let .missing(issue):
                result.missingETA = true
                if !result.issues.contains(issue) { result.issues.append(issue) }
            case .limited: break
            }
        }
        result.partial = !unseen.isEmpty || result.missingETA || work.limit != nil
        result.completeCandidates = schedules.count
        let ranked = schedules.sorted(by: faster)
        if let baseline = ranked.first {
            result.fastest = baseline
            let comparable = ranked.filter { $0.preferredTimeDeviation == baseline.preferredTimeDeviation }
            let selected: PlannerV5Schedule
            if checkInBufferMinutes != nil {
                let choice = selectV51(comparable, extraTravelMinutes: day.input.extraTravelMinutes)
                selected = choice.0
                result.alternative = choice.1
            } else {
                let improvements = comparable.filter { improves($0, over: baseline) }
                let affordable = improvements.filter { $0.drivingMinutes <= baseline.drivingMinutes + day.input.extraTravelMinutes }
                selected = affordable.first(where: { candidate in
                    !affordable.contains { improves($0, over: candidate) }
                }) ?? baseline
                if improves(selected, over: baseline) {
                    result.alternative = selected.drivingMinutes > baseline.drivingMinutes ? baseline : nil
                } else {
                    result.alternative = improvements.first
                }
            }
            result.selected = selected
            for stop in day.stops where stop.exposure == nil && day.goals(stop).contains(.avoidRain) {
                guard let initial = selected.visits.first(where: { $0.placeID == stop.place.id }),
                      let rain = rainMetric(stop, start: initial.startsAt, end: initial.endsAt).value else { continue }
                if comparable.contains(where: { candidate in
                    guard let visit = candidate.visits.first(where: { $0.placeID == stop.place.id }),
                          let other = rainMetric(stop, start: visit.startsAt, end: visit.endsAt).value else { return false }
                    return other + 1e-8 < rain
                }) {
                    result.uncertainExposure.append(stop.place.id)
                }
            }
            result.status = .scheduled
        } else if !result.partial {
            result.status = .conflicts
        }
        return result
    }

    private func priority(_ candidate: Candidate, day: Day, durations: [Int], work: Work,
                          proxies: [[Int]: [Key]], usedOrders: Set<[Int]>, anchors: [[Int]]) -> [Int] {
        var from = day.origin
        var clock = candidate.departure
        var travel = 0
        var distance = 0.0
        var contextual = false
        var widestShortfall = 0
        var totalShortfall = 0
        var estimatedConflict = false
        for to in candidate.order + (day.endpoint.map { [$0] } ?? []) {
            let keys = proxies[[from, to]] ?? []
            let estimated = keys.filter { abs($0.minute - clock) <= 30 }
                .min { (abs($0.minute - clock), $0.minute) < (abs($1.minute - clock), $1.minute) }
            let eta = estimated.flatMap { work.routes[$0] }.map { ($0.seconds + 59) / 60 } ?? 0
            clock += eta
            travel += eta
            let a = day.points[from]
            let b = day.points[to]
            distance += hypot(a.latitude - b.latitude, a.longitude - b.longitude)
            if to < day.stops.count {
                let stop = day.stops[to]
                let next = clock + durations[to]
                contextual = contextual || anchors[to].contains { clock <= $0 && $0 < next }
                    || (day.goals(stop).contains(.avoidRain) && stop.exposure == .outdoor && !stop.context.rain.isEmpty)
                if let target = bufferTarget(day), let session = stop.place.activitySession {
                    let deadline = Self.minute(session.arriveBy ?? session.startsAt)
                    estimatedConflict = estimatedConflict || clock > deadline
                    let shortfall = max(0, target - (deadline - clock))
                    widestShortfall = max(widestShortfall, shortfall)
                    totalShortfall += shortfall
                    clock = max(next, Self.minute(session.endsAt, rounding: .up))
                } else {
                    clock = next
                }
            }
            from = to
        }
        let feasibility = clock > day.end || estimatedConflict ? 1 : 0
        let diversity = usedOrders.contains(candidate.order) ? 1 : 0
        if checkInBufferMinutes != nil {
            return [feasibility, diversity, widestShortfall, totalShortfall, contextual ? -1 : 0,
                    travel, Int(distance * 100_000)]
        }
        return [feasibility, diversity, travel, contextual ? -1 : 0, Int(distance * 100_000)]
    }
}
