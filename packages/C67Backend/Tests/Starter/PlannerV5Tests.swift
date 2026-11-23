import C67Domain
import Foundation
import Testing
@testable import C67Data
@testable import C67PlannerV5

@Suite("Planner v5 synthetic fixtures")
struct PlannerV5Tests {
    private static let anchor = Date(timeIntervalSince1970: 0)
    private static let legs = [[0, 10, 10], [15, 0, 18], [12, 10, 0]]

    @Test(arguments: [30, 45, 60, 90])
    func museumDurationChangesGoldenHour(_ duration: Int) async throws {
        let (trip, museum, park) = Self.fixture(museumMinutes: duration)
        let result = try await Self.planner.plan(trip)
        let fastest = try #require(result.schedule)
        #expect(fastest.visits.map(\.placeID) == [park, museum])
        #expect(fastest.drivingMinutes == 35)
        let expected = try #require([30: 0.0, 45: 13.0, 60: 25.0, 90: 7.0][duration])
        if expected == 0 {
            #expect(result.alternative == nil)
        } else {
            let alternative = try #require(result.alternative)
            #expect(alternative.visits.map(\.placeID) == [museum, park])
            #expect(alternative.drivingMinutes == 40)
            #expect(alternative.metrics.first(where: { $0.goal == .goldenHour })?.value == expected)
            #expect(alternative.legs.last?.to == nil)
        }
    }

    @Test func boundedTradeoffAndEnrichmentReuse() async throws {
        var (input, museum, park) = Self.fixture(museumMinutes: 60)
        input.extraTravelMinutes = 5
        input.trip.places[0].durationOverridden = false
        input.visits[museum] = .init(duration: .init(minutes: 30 ... 90, target: 60, source: .localEstimate))
        let prepared = try await Self.planner.prepare(input)
        let initial = try #require(prepared.result.schedule)
        #expect(initial.visits.map(\.placeID) == [museum, park])
        #expect(prepared.result.enrichment.contains { $0.placeID == museum && $0.information == .activitySuggestion })
        let updated = try await prepared.refine(with: [
            .traveller(placeID: museum, activity: "Quick visit", durationMinutes: 30, exposure: .indoor)
        ])
        let recommendation = try #require(updated.schedule)
        #expect(recommendation.visits.map(\.placeID) == [park, museum])
        #expect(recommendation.visits.last?.duration.source == .traveller)
        #expect(updated.routeQuotes == prepared.result.routeQuotes)
    }

    @Test func stableUncertainDurationDoesNotRequestEnrichment() async throws {
        var (input, _, _) = Self.fixture(museumMinutes: 45)
        input.trip.places[0].durationOverridden = false
        input.trip.preservesPlaceOrder = true
        input.visits = [:]
        let result = try await Self.planner.plan(input)
        #expect(result.status == .scheduled)
        #expect(result.enrichment.isEmpty)
        #expect(result.sensitivity.count >= 2)
    }

    @Test func rejectsLateCheckInWithoutFetchingTheNextLeg() async throws {
        var (input, museum, _) = Self.fixture(museumMinutes: 60)
        input.trip.preservesPlaceOrder = true
        input.trip.places[0].activitySession = .init(startsAt: Self.at(15, 45), endsAt: Self.at(16, 45),
                                                    arriveBy: Self.at(15, 35))
        let result = try await Self.planner.plan(input)
        #expect(result.status == .conflicts)
        #expect(result.issues == [.checkIn(museum)])
        #expect(result.routeQuotes == 1)
    }

    @Test func equalEvidenceIsRequiredForRain() async throws {
        var (input, _, park) = Self.fixture(museumMinutes: 60)
        input.visits[park]?.goals = [.avoidRain]
        input.visits[park]?.rain = [
            .init(interval: .init(start: Self.at(15, 0), end: Self.at(17, 0)), probability: 0.8, source: "Fixture"),
            .init(interval: .init(start: Self.at(17, 0), end: Self.at(18, 0)), probability: 0.2, source: "Fixture")
        ]
        let covered = try await Self.planner.plan(input)
        let wet = try #require(covered.schedule?.metrics.first?.value)
        let dry = try #require(covered.alternative?.metrics.first?.value)
        #expect(abs(wet - 32) < 0.0001)
        #expect(abs(dry - 9.2) < 0.0001)
        input.visits[park]?.rain.removeLast()
        let gap = try await Self.planner.plan(input)
        #expect(gap.alternative == nil)
        input.visits[park]?.exposureSource = .suggestion("Fixture model")
        let unverified = try await Self.planner.plan(input)
        #expect(unverified.schedule?.metrics.first?.value == nil)
        #expect(unverified.alternative == nil)
    }

    @Test func solarEventUsesHalfOpenVisitAndRequiresMatchingAccess() async throws {
        var (input, _, park) = Self.fixture(museumMinutes: 60)
        input.extraTravelMinutes = 5
        input.visits[park]?.goals = [.sunrise, .sunset]
        input.visits[park]?.light = [.sunrise(Self.at(16, 20)), .sunset(Self.at(17, 20))]
        let both = try await Self.planner.plan(input)
        #expect(both.fastestComparable?.metrics.first { $0.goal == .sunrise }?.value == 0)
        #expect(both.schedule?.metrics.first { $0.goal == .sunset }?.value == 1)
        let hours = DateInterval(start: Self.at(14, 0), end: Self.at(17, 0))
        input.visits[park]?.access = .init(windows: [.init(hours)], source: .venue("Fixture regular hours"))
        let constrained = try await Self.planner.plan(input)
        #expect(constrained.status == .scheduled)
        #expect(constrained.alternative == nil)
        #expect(constrained.issues.contains(.access(park)))
    }

    @Test func exactMinuteChangesReturnETA() async throws {
        let (input, _, _) = Self.fixture(museumMinutes: 60)
        let planner = PlannerV5 { from, to, time, _ in
            let origin = Int(from.longitude)
            let destination = Int(to.longitude)
            let minutes = origin == 2 && destination == 0 && time == Self.at(17, 38)
                ? 32 : Self.legs[origin][destination]
            return .init(seconds: minutes * 60)
        }
        let result = try await planner.plan(input)
        #expect(result.alternative?.legs.last?.departsAt == Self.at(17, 38))
        #expect(result.alternative?.finishesAt == Self.at(18, 10))
        #expect(result.alternative?.drivingMinutes == 60)
    }

    @Test func missingQuoteAndExhaustedBudgetHaveDifferentOutcomes() async throws {
        let (input, _, _) = Self.fixture(museumMinutes: 60)
        let missing = try await PlannerV5 { _, _, _, _ in nil }.plan(input)
        #expect(missing.status == .incomplete)
        #expect(missing.issues.contains { if case .etaUnavailable = $0 { return true }; return false })
        var work = PlannerV5.Work(quotes: 72)
        let limited = try await Self.planner.solve(input, work: &work)
        #expect(limited.status == .incomplete)
        #expect(limited.limit == .routeQuotes)
        #expect(limited.routeQuotes == 72)
    }

    @Test func syntheticComparisonWithV42AndIndependentEnumeration() async throws {
        var (input, _, _) = Self.fixture(museumMinutes: 60)
        input.visits = [:]
        let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary,
                              input: input.trip, createdAt: input.trip.startsAt)
        let services = PocketPlanningServices(
            travel: { from, to, _, _ in
                .init(seconds: Double(Self.legs[Int(from.longitude)][Int(to.longitude)] * 60), meters: 1000)
            },
            weather: { _, _, _ in .init(maxRainChance: nil, summary: "Synthetic fixture") },
            advise: { _ in throw PlanningError.unavailable }
        )
        let clock = ContinuousClock()
        let oldStart = clock.now
        let old = try await V41ItineraryPlanner(services: services, hours: { _ in .init(status: "unavailable") },
                                              synthetic: true).plan(job)
        let oldElapsed = oldStart.duration(to: clock.now)
        let newStart = clock.now
        let new = try await Self.planner.plan(input)
        let newElapsed = newStart.duration(to: clock.now)
        let allOrders = [[1, 2], [2, 1]]
        let costs = allOrders.map { order in
            zip([0] + order, order + [0]).reduce(0) { $0 + Self.legs[$1.0][$1.1] }
        }
        let oracle = try #require(costs.min())
        let proposal = try #require(old.proposal)
        let result = try #require(new.schedule)
        #expect(result.drivingMinutes == oracle)
        #expect(proposal.stops.map(\.id) == result.visits.map(\.placeID))
        #expect(new.evaluatedCandidates == allOrders.count)
        print("PLANNER_COMPARISON v42=\(oldElapsed) v5=\(newElapsed) v42_quotes=\(proposal.scheduleAssessment?.routeCalls ?? 0) v5_quotes=\(new.routeQuotes) oracle_driving=\(oracle)")
    }

    private static var planner: PlannerV5 {
        PlannerV5 { from, to, _, _ in
            .init(seconds: legs[Int(from.longitude)][Int(to.longitude)] * 60, meters: 1000)
        }
    }

    private static func at(_ hour: Int, _ minute: Int) -> Date {
        anchor.addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    private static func fixture(museumMinutes: Int) -> (PlannerV5Input, UUID, UUID) {
        var museum = PlanningPlace(id: UUID(), name: "Museum", location: .init(latitude: 0, longitude: 1),
                                   visitSeconds: museumMinutes * 60)
        var park = PlanningPlace(id: UUID(), name: "Park", location: .init(latitude: 0, longitude: 2),
                                 visitSeconds: 40 * 60)
        museum.durationOverridden = true
        park.durationOverridden = true
        var trip = PlanningInput(title: "Fixture", origin: .init(latitude: 0, longitude: 0), places: [museum, park],
                                 preferences: "", startsAt: at(15, 30), finishBy: at(20, 0), timeZone: "UTC",
                                 mode: .automobile)
        var options = PlanningPreferences()
        options.returnToOrigin = true
        options.orderingMethod = .hybridV42
        options.semanticAssistance = .disabled
        trip.enginePreferences = options
        let parkContext = PlannerV5VisitContext(activity: "Photography", activitySource: .traveller,
                                                 exposure: .outdoor, exposureSource: .traveller, goals: [.goldenHour],
                                                 light: [.goldenHour(.init(start: at(17, 10), end: at(17, 35)))],
                                                 lightSource: "Synthetic solar window")
        return (.init(trip: trip, visits: [park.id: parkContext]), museum.id, park.id)
    }
}
