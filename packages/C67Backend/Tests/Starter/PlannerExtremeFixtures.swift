import C67Domain
import C67PlannerV5
import Foundation
import Testing
@testable import C67Data

enum PlannerExtremeEngine: String, CaseIterable {
    case v42 = "v4.2"
    case v5
    case v51 = "v5.1"
}

struct PlannerExtremeFixture: Sendable {
    typealias ETA = @Sendable (Int, Int, Int) -> Int?

    struct Stop: Sendable {
        let number: Int
        var duration = 10
        var opens: Int?
        var closes: Int?
        var lastEntry: Int?
        var sessionStart: Int?
        var checkIn: Int?

        var id: UUID {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(number)))
        }
    }

    struct Visit: Equatable {
        let id: UUID
        let arrival: Int
        let start: Int
        let end: Int
    }

    struct Schedule: Equatable {
        let departure: Int
        let finish: Int
        let driving: Int
        let visits: [Visit]
    }

    struct Observation {
        let schedule: Schedule?
        let result: PlannerV5Result?
        let quotes: Int
        let outcome: String
        var legacyIssueCodes: Set<String> = []
        let elapsed: Duration
    }

    let name: String
    let stops: [Stop]
    var start = 540
    var finish = 680
    var wait = 0
    var flexible = false
    var locked = false
    var first: Int?
    var returns = true
    var extraTravel = 0
    var context: [UUID: PlannerV5VisitContext] = [:]
    var delay = false
    var eta: ETA = { _, _, _ in 5 }

    static func date(_ minute: Int) -> Date {
        Date(timeIntervalSince1970: Double(minute * 60))
    }

    static func minute(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }

    var input: PlannerV5Input {
        let places = stops.map { stop in
            var place = PlanningPlace(
                id: stop.id, name: "Synthetic stop \(stop.number)",
                location: .init(latitude: 0, longitude: Double(stop.number)), visitSeconds: stop.duration * 60
            )
            place.durationOverridden = true
            place.visitConfirmation = .init(
                opensAt: Self.date(stop.opens ?? start), closesAt: Self.date(stop.closes ?? finish),
                publicAccessConfirmed: true
            )
            place.visitConfirmation?.lastEntryAt = stop.lastEntry.map(Self.date)
            if let session = stop.sessionStart {
                place.activitySession = .init(startsAt: Self.date(session), endsAt: Self.date(session + stop.duration),
                                              arriveBy: stop.checkIn.map(Self.date))
            }
            return place
        }
        var trip = PlanningInput(title: name, origin: .init(latitude: 0, longitude: 0), places: places,
                                 preferences: "", startsAt: Self.date(start), finishBy: Self.date(finish),
                                 timeZone: "UTC", mode: .automobile, preservesPlaceOrder: locked)
        trip.firstPlaceID = stops.first { $0.number == first }?.id
        var preferences = PlanningPreferences()
        preferences.maximumWaitMinutes = wait
        preferences.returnToOrigin = returns
        preferences.flexibleDeparture = flexible
        preferences.orderingMethod = .hybridV42
        preferences.semanticAssistance = .disabled
        trip.enginePreferences = preferences
        return .init(trip: trip, visits: context, extraTravelMinutes: extraTravel)
    }

    // Replay a candidate independently from its reported order and departure.
    func replay(_ order: [UUID], departure: Int) -> Schedule? {
        guard order.count == stops.count, Set(order) == Set(stops.map(\.id)),
              !locked || order == stops.map(\.id),
              first == nil || order.first == stops.first(where: { $0.number == first })?.id,
              (start ..< finish).contains(departure), flexible || departure == start else { return nil }
        let lookup = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0) })
        var visits: [Visit] = []
        var clock = departure
        var origin = 0
        var driving = 0
        var waiting = 0
        for id in order {
            guard let stop = lookup[id], let drive = eta(origin, stop.number, clock) else { return nil }
            let arrival = clock + drive
            let begins = stop.sessionStart ?? max(arrival, stop.opens ?? start)
            let end = begins + stop.duration
            let closing = stop.closes ?? finish
            guard begins >= arrival, begins >= (stop.opens ?? start), begins < closing, end <= closing,
                  begins <= (stop.lastEntry ?? finish),
                  arrival <= (stop.checkIn ?? stop.sessionStart ?? finish), end <= finish else { return nil }
            waiting += begins - arrival
            guard waiting <= wait else { return nil }
            visits.append(.init(id: id, arrival: arrival, start: begins, end: end))
            clock = end
            origin = stop.number
            driving += drive
        }
        if returns {
            guard let drive = eta(origin, 0, clock) else { return nil }
            driving += drive
            clock += drive
        }
        guard clock <= finish else { return nil }
        return .init(departure: departure, finish: clock, driving: driving, visits: visits)
    }

    func oracle() -> [Schedule] {
        var schedules: [Schedule] = []
        func enumerate(_ order: [UUID], remaining: [Stop]) {
            if remaining.isEmpty {
                let departures = flexible ? start ..< finish : start ..< (start + 1)
                for departure in departures {
                    if let schedule = replay(order, departure: departure) { schedules.append(schedule) }
                }
                return
            }
            for stop in remaining {
                if order.isEmpty, let first, stop.number != first { continue }
                enumerate(order + [stop.id], remaining: remaining.filter { $0.id != stop.id })
            }
        }
        if locked {
            let departures = flexible ? start ..< finish : start ..< (start + 1)
            return departures.compactMap { replay(stops.map(\.id), departure: $0) }
        }
        enumerate([], remaining: stops)
        return schedules
    }

    func bufferShortfalls(_ schedule: Schedule) -> [Int] {
        stops.compactMap { stop in
            guard let deadline = stop.checkIn ?? stop.sessionStart,
                  let visit = schedule.visits.first(where: { $0.id == stop.id }) else { return nil }
            return max(0, 15 - (deadline - visit.arrival))
        }
    }

    func bufferRank(_ schedule: Schedule) -> (Int, Int) {
        let gaps = bufferShortfalls(schedule)
        return (gaps.max() ?? 0, gaps.reduce(0, +))
    }

    // Minute-by-minute integration is independent of the engine's interval-overlap calculation.
    func weatherScore(_ reading: PlannerV51WeatherSeries, during visit: Visit) -> Double? {
        var sum = 0.0
        for minute in visit.start ..< visit.end {
            let at = Self.date(minute)
            let covering = reading.samples.filter { $0.interval.start <= at && at < $0.interval.end }
            guard covering.count == 1, let sample = covering.first else { return nil }
            sum += reading.threshold.map { max(0, sample.value - $0) } ?? sample.value
        }
        return reading.threshold == nil ? sum / Double(visit.end - visit.start) : sum
    }

    func measure(_ engine: PlannerExtremeEngine) async throws -> Observation {
        let input = self.input
        let quote: @Sendable (Int, Int, Date) async throws -> Int? = { from, to, date in
            let minute = Self.minute(date)
            if self.delay {
                try await Task.sleep(for: .milliseconds(3 + (from * 11 + to * 7 + minute) % 16))
            }
            return self.eta(from, to, minute)
        }
        let clock = ContinuousClock()
        if engine == .v42 {
            let services = PocketPlanningServices(
                travel: { from, to, date, _ in
                    guard let minutes = try await quote(Int(from.longitude), Int(to.longitude), date) else {
                        throw PlanningError.unavailable
                    }
                    return .init(seconds: Double(minutes * 60), meters: 1000)
                },
                weather: { _, _, _ in .init(maxRainChance: nil, summary: "Synthetic fixture") },
                advise: { _ in throw PlanningError.unavailable }
            )
            let planner = V41ItineraryPlanner(services: services, hours: { _ in .init(status: "unavailable") }, synthetic: true)
            let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input.trip,
                                  createdAt: input.trip.startsAt)
            let began = clock.now
            do {
                let result = try await planner.plan(job)
                let elapsed = began.duration(to: clock.now)
                let proposal = try #require(result.proposal)
                let departure = try #require(proposal.departureAt)
                let finish = try #require(proposal.finishesAt)
                let visits = try proposal.stops.map { stop in
                    let arrival = try #require(stop.arrivalAt)
                    let start = try #require(stop.visitStartsAt)
                    let end = try #require(stop.departureAt)
                    return Visit(id: stop.id, arrival: Self.minute(arrival), start: Self.minute(start), end: Self.minute(end))
                }
                if returns { _ = try #require(proposal.returnTravelSeconds) }
                let driving = (proposal.stops.map(\.travelSeconds).reduce(0, +) + (proposal.returnTravelSeconds ?? 0)) / 60
                return .init(schedule: .init(departure: Self.minute(departure), finish: Self.minute(finish),
                                             driving: driving, visits: visits),
                             result: nil, quotes: proposal.scheduleAssessment?.routeCalls ?? 0,
                             outcome: proposal.scheduleAssessment?.stopReason ?? "scheduled", elapsed: elapsed)
            } catch let failure as PlanningScheduleFailure {
                let elapsed = began.duration(to: clock.now)
                let assessment = failure.assessment
                let codes = Set((assessment.conflicts + assessment.regularConflicts + assessment.unresolved).map(\.code))
                return .init(schedule: nil, result: nil, quotes: assessment.routeCalls,
                             outcome: "\(failure.code)/\(assessment.stopReason)", legacyIssueCodes: codes, elapsed: elapsed)
            }
        }
        let route: PlannerV5.RouteProvider = { from, to, date, _ in
            guard let minutes = try await quote(Int(from.longitude), Int(to.longitude), date) else { return nil }
            return .init(seconds: minutes * 60, meters: 1000)
        }
        let v5 = PlannerV5(route: route)
        let v51 = PlannerV51(route: route)
        let began = clock.now
        let result: PlannerV5Result
        if engine == .v5 {
            result = try await v5.plan(input)
        } else {
            result = try await v51.plan(input)
        }
        let elapsed = began.duration(to: clock.now)
        let schedule = result.schedule.map { schedule in
            Schedule(departure: Self.minute(schedule.departsAt), finish: Self.minute(schedule.finishesAt),
                     driving: schedule.drivingMinutes, visits: schedule.visits.map {
                         Visit(id: $0.placeID, arrival: Self.minute($0.arrivesAt), start: Self.minute($0.startsAt), end: Self.minute($0.endsAt))
                     })
        }
        return .init(schedule: schedule, result: result, quotes: result.routeQuotes,
                     outcome: "\(result.status)/\(result.limit.map { String(describing: $0) } ?? "complete")", elapsed: elapsed)
    }
}
