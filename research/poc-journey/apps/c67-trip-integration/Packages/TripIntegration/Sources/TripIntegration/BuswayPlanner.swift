import Foundation

@MainActor public protocol BuswayWalking {
    var requests: Int { get }
    var synthetic: Bool { get }
    var failures: [String] { get }
    func walk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayWalk?
    func cancel()
}

/// Time-dependent direct and one-transfer TJ journeys with bounded walking requests.
@MainActor final class BuswayPlanner {
    let feed: BuswayFeed
    let walking: any BuswayWalking
    private let services: [String: BuswayService]
    private let stops: [String: BuswayStop]
    private var walks: [String: BuswayWalk] = [:]
    private var unavailableWalks = Set<String>()
    private(set) var searchLimited = false
    private var calculationRequests = 0

    init(feed: BuswayFeed, walking: any BuswayWalking, now: Date) throws {
        try feed.validate()
        try feed.requireFresh(at: now)
        self.feed = feed
        self.walking = walking
        services = Dictionary(uniqueKeysWithValues: feed.services.map { ($0.id, $0) })
        stops = Dictionary(uniqueKeysWithValues: feed.stops.map { ($0.id, $0) })
    }

    private func walk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayWalk? {
        try Task.checkCancellation()
        let key = "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)"
        if let saved = walks[key] {
            // Cached geometry/duration is reused, while endpoint identity belongs to this request.
            return .init(from: from, to: to, seconds: saved.seconds, distanceMeters: saved.distanceMeters, provider: saved.provider)
        }
        if unavailableWalks.contains(key) { return nil }
        guard calculationRequests < 128 else { searchLimited = true; return nil }
        calculationRequests += 1
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
        feed.stops.filter { WeatherPolicy.distance(pin, $0.pin) <= 800 }.sorted {
            let a = WeatherPolicy.distance(pin, $0.pin), b = WeatherPolicy.distance(pin, $1.pin)
            return a == b ? $0.id < $1.id : a < b
        }
    }

    func directWalk(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayJourney? {
        guard WeatherPolicy.distance(from, to) <= 2000,
              let value = try await walk(from: from, to: to, departure: departure), value.seconds <= 1200 else { return nil }
        let journey = BuswayJourney(source: feed.source, departure: departure,
                                    arrival: departure.addingTimeInterval(value.seconds), access: value)
        try journey.validate()
        return journey
    }

    private struct Segment {
        var pattern: BuswayPattern
        var board: BuswayCall
        var alight: BuswayCall
    }
    private struct Path {
        var first: Segment
        var transfer: BuswayTransfer?
        var second: Segment?
        var rank: Double
    }

    private func segments(boarding: Set<String>, alighting: Set<String>) -> [Segment] {
        feed.patterns.flatMap { pattern in
            pattern.calls.enumerated().flatMap { index, board -> [Segment] in
                guard boarding.contains(board.stopID), board.pickupAllowed != false else { return [] }
                return pattern.calls.dropFirst(index + 1).compactMap { alight in
                    guard alighting.contains(alight.stopID), alight.dropOffAllowed != false,
                          board.stopID != alight.stopID, alight.arrivalOffset > board.departureOffset else { return nil }
                    return Segment(pattern: pattern, board: board, alight: alight)
                }
            }
        }
    }

    private func ride(_ segment: Segment, ready: Date) -> BuswayRide? {
        guard let service = services[segment.pattern.serviceID],
              let board = stops[segment.board.stopID], let alight = stops[segment.alight.stopID] else { return nil }
        let midnight = TripClock.calendar.startOfDay(for: ready)
        var best: BuswayRide?
        for day in [midnight.addingTimeInterval(-86400), midnight] where service.operates(on: day) {
            for frequency in segment.pattern.frequencies {
                let start = day.addingTimeInterval(Double(frequency.start + segment.board.departureOffset))
                let end = day.addingTimeInterval(Double(frequency.end + segment.board.departureOffset))
                let boardAt = max(ready, start).addingTimeInterval(Double(frequency.headway))
                guard boardAt < end else { continue }
                let candidate = BuswayRide(pattern: segment.pattern, patternID: segment.pattern.id,
                                           headsign: segment.pattern.headsign, directionID: segment.pattern.directionID,
                                           board: board, alight: alight, boardSequence: segment.board.sequence,
                                           alightSequence: segment.alight.sequence, boardOffset: segment.board.departureOffset,
                                           alightOffset: segment.alight.arrivalOffset, service: service, serviceDay: day,
                                           frequency: frequency, boardAt: boardAt,
                                           alightAt: boardAt.addingTimeInterval(Double(segment.alight.arrivalOffset - segment.board.departureOffset)))
                if best == nil || candidate.alightAt < best!.alightAt { best = candidate }
            }
        }
        return best
    }

    private func paths(from: PlacePin, to: PlacePin, transferring: Bool) -> [Path] {
        let boarding = Set(nearby(from).map(\.id)), alighting = Set(nearby(to).map(\.id))
        guard !boarding.isEmpty, !alighting.isEmpty else { return [] }
        if !transferring {
            return segments(boarding: boarding, alighting: alighting).map {
                Path(first: $0, rank: rank($0, from: from, to: to))
            }
        }
        // Only attributed interchange edges from the importer are considered.
        let edges = feed.transfers ?? []
        let firsts = segments(boarding: boarding, alighting: Set(edges.map(\.fromStopID)))
        let seconds = segments(boarding: Set(edges.map(\.toStopID)), alighting: alighting)
        let byBoard = Dictionary(grouping: seconds, by: { $0.board.stopID })
        let byExit = Dictionary(grouping: edges, by: \.fromStopID)
        var result: [Path] = []
        for first in firsts {
            for edge in byExit[first.alight.stopID] ?? [] {
                for second in byBoard[edge.toStopID] ?? [] where second.pattern.effectiveRouteID != first.pattern.effectiveRouteID {
                    let score = rank(first, from: from, to: stops[first.alight.stopID]!.pin)
                        + rank(second, from: stops[second.board.stopID]!.pin, to: to) + edge.minimumSeconds
                    result.append(Path(first: first, transfer: edge, second: second, rank: score))
                }
            }
        }
        return result
    }

    private func rank(_ segment: Segment, from: PlacePin, to: PlacePin) -> Double {
        let access = WeatherPolicy.distance(from, stops[segment.board.stopID]!.pin)
        let egress = WeatherPolicy.distance(stops[segment.alight.stopID]!.pin, to)
        return (access + egress) / 1.2 + Double(segment.alight.arrivalOffset - segment.board.departureOffset)
            + Double(segment.pattern.frequencies.map(\.headway).min() ?? 0)
    }

    private func evaluate(_ path: Path, from: PlacePin, to: PlacePin, departure: Date, latestArrival: Date?) async throws -> BuswayJourney? {
        guard let board = stops[path.first.board.stopID],
              let access = try await walk(from: from, to: board.pin, departure: departure), access.seconds <= 1200,
              let first = ride(path.first, ready: departure.addingTimeInterval(access.seconds)) else { return nil }
        if let latestArrival, first.alightAt >= latestArrival { return nil }
        var last = first
        var connection: BuswayConnection?
        if let edge = path.transfer, let second = path.second, let nextBoard = stops[second.board.stopID] {
            let transferDeparture = first.alightAt.addingTimeInterval(edge.minimumSeconds)
            guard let transferWalk = try await walk(from: first.alight.pin, to: nextBoard.pin, departure: transferDeparture), transferWalk.seconds <= 1200,
                  let onward = ride(second, ready: transferDeparture.addingTimeInterval(transferWalk.seconds)) else { return nil }
            connection = .init(walk: transferWalk, bufferSeconds: edge.minimumSeconds, evidence: edge.evidence, ride: onward)
            last = onward
        }
        if let latestArrival, last.alightAt >= latestArrival { return nil }
        guard let egress = try await walk(from: last.alight.pin, to: to, departure: last.alightAt), egress.seconds <= 1200 else { return nil }
        let journey = BuswayJourney(source: feed.source, departure: departure,
                                    arrival: last.alightAt.addingTimeInterval(egress.seconds), access: access,
                                    ride: first, egress: egress, connection: connection)
        try journey.validate()
        return journey
    }

    func bus(from: PlacePin, to: PlacePin, departure: Date) async throws -> BuswayJourney? {
        var best: BuswayJourney?
        // Prefer direct services. One-transfer search is a fallback when direct candidates fail.
        for transferring in [false, true] {
            let candidates = paths(from: from, to: to, transferring: transferring).sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                return "\($0.first.pattern.id):\($0.first.board.sequence):\($0.first.alight.sequence):\($0.second?.pattern.id ?? "")"
                    < "\($1.first.pattern.id):\($1.first.board.sequence):\($1.first.alight.sequence):\($1.second?.pattern.id ?? "")"
            }
            if candidates.count > 64 { searchLimited = true }
            for candidate in candidates.prefix(64) {
                try Task.checkCancellation()
                if let journey = try await evaluate(candidate, from: from, to: to, departure: departure, latestArrival: best?.arrival),
                   best == nil || journey.arrival < best!.arrival { best = journey }
            }
            if best != nil { break }
        }
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
        case .transit:
            if let local = try await directWalk(from: start, to: end, departure: departure), local.seconds <= 900 {
                return .init(id: "\(from.id)>\(to.id):walking-priority", mode: mode, status: "unavailable",
                             note: "Walking hingga 15 menit diprioritaskan untuk ruas lokal; waktu walking tetap diperiksa provider.")
            }
            journey = try await bus(from: start, to: end, departure: departure)
        case .automobile: throw IntegrationError.invalid("Moda mobil tidak termasuk pilihan busway.")
        }
        let id = "\(from.id)>\(to.id):\(mode.rawValue):\(departure.timeIntervalSince1970)"
        guard let journey else {
            return .init(id: id, mode: mode, status: "unavailable",
                         note: "Belum ada ruas \(mode == .walking ? "jalan kaki" : "TJ") dalam batas halte, layanan dan akses. "
                             + (searchLimited ? "Batas pencarian tercapai; alternatif lain perlu diperiksa. " : "")
                             + walking.failures.suffix(2).joined(separator: " | "))
        }
        return .init(id: id, mode: mode, seconds: journey.seconds,
                     expectedDeparture: departure, expectedArrival: journey.arrival,
                     status: "available", note: journey.summary + (searchLimited ? " Batas kandidat tercapai; alternatif lain mungkin tersedia." : ""), busway: journey)
    }
}
