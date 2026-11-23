import C67Domain
import Foundation
import Testing
@testable import C67Data
import C67PlannerV5

@Suite("Planner v4.2, v5 and v5.1 comparison", .serialized)
struct PlannerV5BenchmarkTests {
    private struct Scenario {
        let name: String
        let stops: Int
        var flexible = false
        var traffic = false
        var delay = false
        var lateCheckIn = false

        func eta(_ from: Int, _ to: Int, at minute: Int) -> Int {
            let directional = (from * 7 + to * 3) % 5
            let rush = traffic && (9 * 60 + 15 ..< 10 * 60 + 30).contains(minute)
                && (from + 2 * to).isMultiple(of: 3)
            return 3 + abs(from - to) * 2 + directional + (rush ? 18 : 0)
        }
    }

    private enum Engine: String, CaseIterable {
        case v42 = "v4.2"
        case v5
        case v51 = "v5.1"
    }

    private struct Observation {
        let elapsed: Duration
        let quotes: Int
        let driving: Int?
        let reason: String
    }

    private static let start = 9 * 60
    private static let finish = 13 * 60
    private static let dwell = 20

    @Test func matchedInputsAcrossSearchSizes() async throws {
        let scenarios = [
            Scenario(name: "three-static", stops: 3),
            Scenario(name: "four-traffic", stops: 4, traffic: true),
            Scenario(name: "five-flexible", stops: 5, flexible: true),
            Scenario(name: "six-traffic", stops: 6, traffic: true),
            Scenario(name: "six-flexible-traffic", stops: 6, flexible: true, traffic: true),
            Scenario(name: "four-traffic-delayed", stops: 4, traffic: true, delay: true),
            Scenario(name: "locked-missed-checkin", stops: 3, lateCheckIn: true)
        ]
        for scenario in scenarios {
            let input = Self.input(scenario)
            let oracle = Self.oracle(scenario)
            var observations: [Engine: [Observation]] = [:]
            let engines = Engine.allCases
            for iteration in 0 ... 10 { // One warm-up and ten measured rounds with a rotating engine order.
                for offset in engines.indices {
                    let engine = engines[(iteration + offset) % engines.count]
                    let result = try await Self.measure(scenario, input: input, engine: engine)
                    if iteration > 0 { observations[engine, default: []].append(result) }
                    if let driving = result.driving {
                        let minimum = try #require(oracle)
                        #expect(driving >= minimum)
                    }
                }
            }
            for engine in engines {
                let rows = try #require(observations[engine])
                let name = engine.rawValue
                let observed = rows.compactMap(\.driving)
                let elapsed = rows.map(\.elapsed).sorted().map(Self.ms)
                let quotes = rows.map(\.quotes).sorted()
                let outcome = Set(rows.map(\.reason)).sorted().joined(separator: ",")
                let p50 = (elapsed[4] + elapsed[5]) / 2
                print("MATCHED \(scenario.name) \(name) success=\(observed.count)/\(rows.count) oracle=\(oracle ?? -1) travel=\(Set(observed).sorted()) quotes=\(Set(quotes).sorted()) p50_ms=\(p50) p95_ms=\(elapsed[9]) outcome=\(outcome)")
                if scenario.lateCheckIn {
                    #expect(rows.allSatisfy { $0.driving == nil })
                    if engine != .v42 { #expect(rows.allSatisfy { $0.quotes == 1 }) }
                } else {
                    #expect(rows.allSatisfy { $0.driving != nil })
                }
            }
        }
    }

    private static func date(_ minute: Int) -> Date {
        Date(timeIntervalSince1970: Double(minute) * 60)
    }

    private static func input(_ scenario: Scenario) -> PlanningInput {
        var places = (1 ... scenario.stops).map { index in
            var place = PlanningPlace(id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\(index)")!,
                                      name: "Stop \(index)", location: .init(latitude: 0, longitude: Double(index)),
                                      visitSeconds: dwell * 60)
            place.durationOverridden = true
            // Identical confirmed access prevents the v4.2 fallback category window from affecting rank.
            place.visitConfirmation = .init(opensAt: date(start), closesAt: date(finish), publicAccessConfirmed: true)
            return place
        }
        if scenario.lateCheckIn {
            places[0].activitySession = .init(startsAt: date(start + 15), endsAt: date(start + 15 + dwell),
                                             arriveBy: date(start + 1))
        }
        var trip = PlanningInput(title: scenario.name, origin: .init(latitude: 0, longitude: 0), places: places,
                                 preferences: "", startsAt: date(start), finishBy: date(finish), timeZone: "UTC",
                                 mode: .automobile, preservesPlaceOrder: scenario.lateCheckIn)
        var preferences = PlanningPreferences()
        preferences.returnToOrigin = true
        preferences.flexibleDeparture = scenario.flexible
        preferences.orderingMethod = .hybridV42
        preferences.semanticAssistance = .disabled
        trip.enginePreferences = preferences
        return trip
    }

    private static func measure(_ scenario: Scenario, input: PlanningInput, engine: Engine) async throws -> Observation {
        let fixture: @Sendable (Int, Int, Date) async throws -> Int = { from, to, at in
            if scenario.delay { try await Task.sleep(for: .milliseconds(2)) }
            return scenario.eta(from, to, at: Int(at.timeIntervalSince1970 / 60))
        }
        let clock = ContinuousClock()
        if engine != .v42 {
            let route: PlannerV5.RouteProvider = { from, to, at, _ in
                let minutes = try await fixture(Int(from.longitude), Int(to.longitude), at)
                return .init(seconds: minutes * 60, meters: 1000)
            }
            let began = clock.now
            let result: PlannerV5Result
            switch engine {
            case .v5: result = try await PlannerV5(route: route).plan(.init(trip: input))
            case .v51: result = try await PlannerV51(route: route).plan(.init(trip: input))
            case .v42: preconditionFailure("Expected an isolated planner")
            }
            return .init(elapsed: began.duration(to: clock.now), quotes: result.routeQuotes,
                         driving: result.schedule?.drivingMinutes, reason: result.limit.map { String(describing: $0) } ?? String(describing: result.status))
        }

        let services = PocketPlanningServices(
            travel: { from, to, at, _ in
                let minutes = try await fixture(Int(from.longitude), Int(to.longitude), at)
                return .init(seconds: Double(minutes * 60), meters: 1000)
            },
            weather: { _, _, _ in .init(maxRainChance: nil, summary: "Synthetic fixture") },
            advise: { _ in throw PlanningError.unavailable }
        )
        let planner = V41ItineraryPlanner(services: services, hours: { _ in .init(status: "unavailable") }, synthetic: true)
        let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: input.startsAt)
        let began = clock.now
        do {
            let result = try await planner.plan(job)
            let proposal = try #require(result.proposal)
            let driveSeconds = proposal.stops.map(\.travelSeconds).reduce(0, +) + (proposal.returnTravelSeconds ?? 0)
            return .init(elapsed: began.duration(to: clock.now), quotes: proposal.scheduleAssessment?.routeCalls ?? 0,
                         driving: driveSeconds / 60, reason: proposal.scheduleAssessment?.stopReason ?? "scheduled")
        } catch let failure as PlanningScheduleFailure {
            return .init(elapsed: began.duration(to: clock.now), quotes: failure.assessment.routeCalls, driving: nil, reason: failure.code)
        }
    }

    private static func oracle(_ scenario: Scenario) -> Int? {
        if scenario.lateCheckIn {
            return nil // The only allowed first leg arrives after minute 541.
        }
        let departures = scenario.flexible ? Array(stride(from: start, to: finish, by: 30)) : [start]
        var best: Int?
        func visit(_ from: Int, remaining: [Int], minute: Int, driving: Int) {
            guard minute <= finish else { return }
            if remaining.isEmpty {
                let home = scenario.eta(from, 0, at: minute)
                if minute + home <= finish {
                    best = min(best ?? Int.max, driving + home)
                }
                return
            }
            for next in remaining {
                let leg = scenario.eta(from, next, at: minute)
                visit(next, remaining: remaining.filter { $0 != next }, minute: minute + leg + dwell, driving: driving + leg)
            }
        }
        for departure in departures {
            visit(0, remaining: Array(1 ... scenario.stops), minute: departure, driving: 0)
        }
        return best
    }

    private static func ms(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
    }
}
