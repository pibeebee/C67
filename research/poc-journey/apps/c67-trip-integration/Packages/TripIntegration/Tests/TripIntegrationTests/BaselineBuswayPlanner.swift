import Foundation
@testable import TripIntegration

// Frozen pre-improvement planner for paired regression measurements.
/// Corridor-1 direct journeys. Every component retains its source and waiting assumption.
@MainActor final class BaselineBuswayPlanner {
    let feed: BuswayFeed
    let walking: any BuswayWalking
    private let services: [String: BuswayService]
    private var walks: [String: BuswayWalk] = [:]
    private var unavailableWalks = Set<String>()

    init(feed: BuswayFeed, walking: any BuswayWalking, now: Date) throws {
        try feed.validate()
        try feed.requireFresh(at: now)
        self.feed = feed
        self.walking = walking
        services = Dictionary(uniqueKeysWithValues: feed.services.map { ($0.id, $0) })
    }

    private func walk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayWalk? {
        let key = "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)"
        if let saved = walks[key] { return saved }
        if unavailableWalks.contains(key) { return nil }
        let value = try await walking.walk(from: from, to: to, departure: departure)
        try Task.checkCancellation()
        if let value {
            guard value.seconds.isFinite, value.seconds >= 0, value.distanceMeters.isFinite, value.distanceMeters >= 0,
                  value.from.latitude == from.latitude, value.from.longitude == from.longitude,
                  value.to.latitude == to.latitude, value.to.longitude == to.longitude else {
                throw IntegrationError.invalid("Provider jalan kaki mengembalikan bukti yang tidak cocok.")
            }
            walks[key] = value
        } else { unavailableWalks.insert(key) }
        return value
    }

    private func nearby(_ pin: PlacePin) -> [BuswayStop] {
        feed.stops.filter { WeatherPolicy.distance(pin, $0.pin) <= 800 }
            .sorted {
                let a = WeatherPolicy.distance(pin, $0.pin)
                let b = WeatherPolicy.distance(pin, $1.pin)
                return a == b ? $0.id < $1.id : a < b
            }.prefix(2).map { $0 }
    }

    func directWalk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayJourney? {
        // Bound candidate discovery to 2 km before requesting the walking provider.
        // The provider duration must still satisfy the 20-minute walking policy.
        guard WeatherPolicy.distance(from, to) <= 2000,
              let value = try await walk(from: from, to: to, departure: departure), value.seconds <= 1200 else { return nil }
        let journey = BuswayJourney(source: feed.source, departure: departure,
                                    arrival: departure.addingTimeInterval(value.seconds), access: value)
        try journey.validate()
        return journey
    }

    func bus(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayJourney? {
        let boarding = nearby(from)
        let alighting = nearby(to)
        guard !boarding.isEmpty, !alighting.isEmpty else { return nil }
        let calendar = TripClock.calendar
        let today = calendar.startOfDay(for: departure)
        let days = [calendar.date(byAdding: .day, value: -1, to: today)!, today]
        var best: BuswayJourney?
        for board in boarding {
            guard let access = try await walk(from: from, to: board.pin, departure: departure), access.seconds <= 1200 else { continue }
            let ready = departure.addingTimeInterval(access.seconds)
            for alight in alighting where alight.id != board.id {
                for pattern in feed.patterns {
                    try Task.checkCancellation()
                    guard let service = services[pattern.serviceID] else { continue }
                    for (index, call) in pattern.calls.enumerated() where call.stopID == board.id {
                        for later in pattern.calls.dropFirst(index + 1) where later.stopID == alight.id {
                            guard later.arrivalOffset > call.departureOffset else { continue }
                            for day in days where service.operates(on: day) {
                                for frequency in pattern.frequencies {
                                    let start = day.addingTimeInterval(Double(frequency.start + call.departureOffset))
                                    let end = day.addingTimeInterval(Double(frequency.end + call.departureOffset))
                                    let boardAt = max(ready, start).addingTimeInterval(Double(frequency.headway))
                                    guard boardAt < end else { continue }
                                    let alightAt = boardAt.addingTimeInterval(Double(later.arrivalOffset - call.departureOffset))
                                    guard let egress = try await walk(from: alight.pin, to: to, departure: alightAt), egress.seconds <= 1200 else { continue }
                                    let ride = BuswayRide(pattern: pattern, patternID: pattern.id, headsign: pattern.headsign,
                                                          directionID: pattern.directionID, board: board, alight: alight,
                                                          boardSequence: call.sequence, alightSequence: later.sequence,
                                                          boardOffset: call.departureOffset, alightOffset: later.arrivalOffset,
                                                          service: service, serviceDay: day, frequency: frequency,
                                                          boardAt: boardAt, alightAt: alightAt)
                                    let candidate = BuswayJourney(source: feed.source, departure: departure,
                                                                  arrival: alightAt.addingTimeInterval(egress.seconds),
                                                                  access: access, ride: ride, egress: egress)
                                    if best == nil || candidate.arrival < best!.arrival {
                                        best = candidate
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        try best?.validate()
        return best
    }

    func eta(from: NativeTripPoint, to: NativeTripPoint, mode: NativeTripMode, departure: Date) async throws -> NativeTripETA {
        guard let a = from.coordinate, let b = to.coordinate else {
            throw IntegrationError.invalid("Koordinat ruas belum tersedia.")
        }
        let start = PlacePin(id: from.id, name: from.title, address: from.address ?? "Jakarta",
                             latitude: a.latitude, longitude: a.longitude)
        let end = PlacePin(id: to.id, name: to.title, address: to.address ?? "Jakarta",
                           latitude: b.latitude, longitude: b.longitude)
        let journey: BuswayJourney?
        switch mode {
        case .walking: journey = try await directWalk(from: start, to: end, departure: departure)
        case .transit: journey = try await bus(from: start, to: end, departure: departure)
        case .automobile: throw IntegrationError.invalid("Moda mobil tidak termasuk pilihan busway.")
        }
        let id = "\(from.id)>\(to.id):\(mode.rawValue):\(departure.timeIntervalSince1970)"
        guard let journey else {
            return .init(id: id, mode: mode, status: "unavailable",
                         note: "Belum ada ruas \(mode == .walking ? "jalan kaki" : "BRT Koridor 1") dalam batas halte, layanan dan akses. "
                             + walking.failures.suffix(2).joined(separator: " | "))
        }
        return .init(id: id, mode: mode, seconds: journey.seconds,
                     expectedDeparture: departure, expectedArrival: journey.arrival,
                     status: "available", note: journey.summary, busway: journey)
    }
}
