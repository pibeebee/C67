import Foundation
import PocketEngine

struct Scenario: Decodable, Sendable {
    let id: String
    let venues: [Venue]
    let choices: [StopChoice]
    let categories: Set<String>
    let preferences: [String: Preference]
    let departure: Int
    let deadline: Int
    let returnToOrigin: Bool
    let maxWait: Int
    let avoidRain: Bool
    let budget: Int
    let defaultETA: Int
    let edges: [Edge]
    let weather: [String: Weather]
    let rankingOnly: Bool
    let expected: Expected
}

struct Expected: Decodable, Sendable {
    let want: Int
    let departureRange: [Int]?
    let appointment: Timing?
    let preferredTime: Timing?
    let last: String?

    struct Timing: Decodable, Sendable {
        let venueID: String
        let minute: Int

        init(from decoder: Decoder) throws {
            var fields = try decoder.unkeyedContainer()
            venueID = try fields.decode(String.self)
            minute = try fields.decode(Int.self)
        }
    }
}

struct Edge: Decodable, Sendable {
    let from: String
    let to: String
    let fromMinute: Int
    let minutes: Int?
    let failFirst: Bool
}

struct Weather: Decodable, Sendable {
    let rainBefore: Int
    let early: Double?
    let late: Double?
}

struct Candidate: Encodable {
    let id: String
    let score: Int
    let eligible: Bool
    let blockers: [String]
    let unknowns: [String]
}

struct Run: Encodable {
    let id: String
    let iteration: Int
    let elapsedMs: Double
    let etaCalls: Int
    let etaFailures: Int
    let weatherCalls: Int
    let ranking: [Candidate]
    let itinerary: Itinerary?
    let error: String?
}

enum FixtureError: Error {
    case badInput
    case etaUnavailable
}

actor Provider {
    let scenario: Scenario
    let day: Date
    let idByCoordinate: [Coordinate: String]
    var attempts: [String: Int] = [:]
    var etaCalls = 0
    var etaFailures = 0
    var weatherCalls = 0

    init(scenario: Scenario, day: Date, origin: Coordinate) {
        self.scenario = scenario
        self.day = day
        idByCoordinate = Dictionary(uniqueKeysWithValues:
            [(origin, "origin")] + scenario.venues.map { ($0.coordinate, $0.id) })
    }

    func quote(from: Coordinate, to: Coordinate, at departure: Date) throws -> LegQuote {
        etaCalls += 1
        guard let source = idByCoordinate[from], let destination = idByCoordinate[to] else {
            throw FixtureError.badInput
        }
        let key = source + ">" + destination
        attempts[key, default: 0] += 1
        let minute = Int(departure.timeIntervalSince(day) / 60)
        let edge = scenario.edges.last {
            $0.from == source && $0.to == destination && $0.fromMinute <= minute
        }
        if let edge {
            guard let minutes = edge.minutes else {
                etaFailures += 1
                throw FixtureError.etaUnavailable
            }
            if edge.failFirst && attempts[key] == 1 {
                etaFailures += 1
                throw TravelQuoteError.temporary(retryAfter: .zero)
            }
            return .init(seconds: Double(minutes * 60), meters: 1_000)
        }
        return .init(seconds: Double(scenario.defaultETA * 60), meters: 1_000)
    }

    func forecast(at point: Coordinate, start: Date) -> WeatherReading {
        weatherCalls += 1
        let minute = Int(start.timeIntervalSince(day) / 60)
        let forecast = idByCoordinate[point].flatMap { scenario.weather[$0] }
        let probability = forecast.flatMap { minute < $0.rainBefore ? $0.early : $0.late }
        return .init(maxRainChance: probability, summary: "Synthetic weather replay")
    }

    func counts() -> (Int, Int, Int) { (etaCalls, etaFailures, weatherCalls) }
}

@main struct AcceptanceBench {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3, let repeats = Int(args[2]), (1 ... 100).contains(repeats),
              let day = TripClock.calendar.date(from: DateComponents(year: 2026, month: 11, day: 14)) else {
            throw FixtureError.badInput
        }
        let cases = try Codec.decoder().decode([Scenario].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let origin = Coordinate(latitude: -6.2, longitude: 106.8)
        let encoder = Codec.encoder()
        for scenario in cases {
            var profile = Profile()
            profile.categories = scenario.categories
            for (key, preference) in scenario.preferences {
                guard let facet = Facet(rawValue: key) else { throw FixtureError.badInput }
                profile.preferences[facet] = preference
            }
            func at(_ minute: Int) -> Date { day.addingTimeInterval(Double(minute * 60)) }
            let input = TripInput(
                departure: day.addingTimeInterval(Double(scenario.departure * 60)),
                deadline: day.addingTimeInterval(Double(scenario.deadline * 60)),
                origin: origin,
                returnToOrigin: scenario.returnToOrigin,
                maxWaitMinutes: scenario.maxWait,
                avoidRain: scenario.avoidRain,
                latestDeparture: scenario.expected.departureRange?.last.map(at),
                lastVenueID: scenario.expected.last,
                minimumStops: scenario.expected.want
            )
            let choices = scenario.choices.map { choice in
                var choice = choice
                if let timing = scenario.expected.appointment, timing.venueID == choice.venueID {
                    choice.timing = .required(timing.minute)
                } else if let timing = scenario.expected.preferredTime, timing.venueID == choice.venueID {
                    choice.timing = .preferred(timing.minute)
                }
                return choice
            }
            for iteration in 0 ... repeats {
                let provider = Provider(scenario: scenario, day: day, origin: origin)
                let start = ContinuousClock.now
                let ranking = scenario.venues.map {
                    Recommender.assess($0, profile: profile, now: input.departure)
                }.sorted {
                    if $0.eligible != $1.eligible { return $0.eligible }
                    return $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score
                }.map {
                    Candidate(id: $0.id, score: $0.score, eligible: $0.eligible, blockers: $0.blockers, unknowns: $0.unknowns)
                }
                var itinerary: Itinerary?
                var failure: String?
                if !scenario.rankingOnly {
                    do {
                        itinerary = try await ItineraryPlanner.make(
                            input: input, choices: choices, venues: scenario.venues, profile: profile,
                            travel: { try await provider.quote(from: $0, to: $1, at: $2) },
                            weather: { point, start, _ in await provider.forecast(at: point, start: start) },
                            budget: scenario.budget
                        )
                    } catch {
                        failure = error.localizedDescription
                    }
                }
                let duration = start.duration(to: .now).components
                let counts = await provider.counts()
                let run = Run(
                    id: scenario.id, iteration: iteration,
                    elapsedMs: Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15,
                    etaCalls: counts.0, etaFailures: counts.1, weatherCalls: counts.2,
                    ranking: ranking, itinerary: itinerary, error: failure
                )
                print(String(decoding: try encoder.encode(run), as: UTF8.self))
            }
        }
    }
}
