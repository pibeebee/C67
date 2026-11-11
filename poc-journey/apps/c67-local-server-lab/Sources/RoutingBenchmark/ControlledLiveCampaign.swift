import Foundation
import TripIntegration

public struct ControlledLiveRow: Codable, Sendable {
    public var caseID: String
    public var evidence: String
    public var bothAvailable: Bool
    public var appleOutcome: String
    public var valhallaOutcome: String
    public var appleCalls: Int
    public var valhallaCalls: Int
    public var appleWallSeconds: Double
    public var valhallaWallSeconds: Double
    public var valhallaToAppleTravelRatio: Double?
    public var valhallaToAppleElapsedRatio: Double?
    public var appleDeadlineMet: Bool?
    public var valhallaDeadlineMet: Bool?
    public var appleRides: [String]?
    public var valhallaRides: [String]?
    public var sourceSHA256: String?
}
/// Live road estimates with explicitly controlled visit rules, not live venue facts.
@MainActor public enum ControlledLiveCampaign {
    public static func run(manifest: RoutingManifest, apple: any RoutingProvider, valhalla: any RoutingProvider, transitOnly: Bool = false, checkpoint: ([ControlledLiveRow]) throws -> Void) async throws -> [ControlledLiveRow] {
        try manifest.validate()
        guard manifest.venues.count >= 7 else { throw RoutingFailure.invalidInput }
        var rows: [ControlledLiveRow] = []
        let departure = Date(timeIntervalSince1970: floor(Date().addingTimeInterval(1800).timeIntervalSince1970 / 60) * 60)
        for count in (transitOnly ? [] : [1, 3, 6]) {
            for mode in RouteMode.allCases {
                let venues = Array(manifest.venues.prefix(count + 1)) + [manifest.venues[0]]
                var totals: [String: Double] = ["apple": 0, "valhalla": 0], walls = totals
                var calls: [String: Int] = ["apple": 0, "valhalla": 0], outcomes = ["apple": "available", "valhalla": "available"]
                var cursor = departure
                for (index, pair) in zip(venues, venues.dropFirst()).enumerated() {
                    let query = RoutingQuery(from: .init(id: pair.0.id, revision: "sourced-osm-poi", point: pair.0.displayPoint), to: .init(id: pair.1.id, revision: "sourced-osm-poi", point: pair.1.displayPoint), mode: mode, departure: cursor)
                    var durations: [Double] = []
                    for name in index.isMultiple(of: 2) ? ["apple", "valhalla"] : ["valhalla", "apple"] {
                        try Task.checkCancellation()
                        let clock = ContinuousClock.now
                        calls[name]! += 1
                        do {
                            if let result = try await (name == "apple" ? apple : valhalla).route(query) {
                                guard result.query == query else { throw RoutingFailure.invalidResponse }
                                totals[name]! += result.seconds; durations.append(result.seconds)
                            } else { outcomes[name] = "unavailable" }
                        } catch is CancellationError { throw CancellationError() }
                        catch let error as RoutingFailure {
                            outcomes[name] = error.rawValue
                            if [.throttled, .authentication, .budgetExhausted].contains(error) { throw error }
                        } catch { outcomes[name] = "provider_failure" }
                        walls[name]! += RoutingFixtures.seconds(clock)
                    }
                    // The next leg uses one common conservative departure for both providers.
                    cursor = Date(timeIntervalSince1970: ceil((cursor.timeIntervalSince1970 + (durations.max() ?? 0) + (index < count ? 1800 : 0)) / 60) * 60)
                }
                let both = outcomes.values.allSatisfy { $0 == "available" }, a = totals["apple"]!, v = totals["valhalla"]!, dwell = Double(count * 1800)
                rows.append(.init(caseID: "fixed-n\(count)-\(mode.rawValue)", evidence: "LIVE_ROUTING_CONTROLLED_VISITS_30MIN_12H_DEADLINE_COMMON_LEG_DEPARTURES", bothAvailable: both, appleOutcome: outcomes["apple"]!, valhallaOutcome: outcomes["valhalla"]!, appleCalls: calls["apple"]!, valhallaCalls: calls["valhalla"]!, appleWallSeconds: walls["apple"]!, valhallaWallSeconds: walls["valhalla"]!, valhallaToAppleTravelRatio: both && a > 0 ? v / a : nil, valhallaToAppleElapsedRatio: both && a + dwell > 0 ? (v + dwell) / (a + dwell) : nil, appleDeadlineMet: outcomes["apple"] == "available" ? a + dwell <= 43200 : nil, valhallaDeadlineMet: outcomes["valhalla"] == "available" ? v + dwell <= 43200 : nil))
                try checkpoint(rows)
            }
        }
        let feed = try BuswayFeed.network()
        // Published stop coordinates with controlled 55 m offsets, not verified station entrances.
        let cases = transitOnly ? [("tj-ragunan-kota", "G00304", "G00061"), ("tj-jak74-candidate", "B03484P", "B05723P")] : [("tj-hi-blokm", "G00031", "P00017"), ("tj-blokm-hi", "P00017", "G00031")]
        for (caseID, startID, endID) in cases {
            guard let from = feed.stops.first(where: { $0.id == startID }), let to = feed.stops.first(where: { $0.id == endID }) else { throw RoutingFailure.invalidInput }
            let start = PlacePin(id: "start-" + startID, name: "Controlled approach", address: "Unverified approach", latitude: from.latitude + 0.0005, longitude: from.longitude)
            let end = PlacePin(id: "end-" + endID, name: "Controlled approach", address: "Unverified approach", latitude: to.latitude + 0.0005, longitude: to.longitude)
            var trips: [String: BuswayJourney] = [:], outcomes = [String: String](), calls = [String: Int](), walls = [String: Double]()
            for name in caseID == "tj-hi-blokm" ? ["apple", "valhalla"] : ["valhalla", "apple"] {
                let memo = RoutingMemo(base: name == "apple" ? apple : valhalla, limit: 32)
                let walker = try RoutingWalkingAdapter(provider: memo, provenance: name == "apple" ? "mapkit_walking" : "valhalla_osm_walking")
                let service = try BuswayRoutingService(feed: feed, walking: walker, now: Date())
                let clock = ContinuousClock.now
                do {
                    if let trip = try await service.route(from: start, to: end, departure: departure) {
                        try trip.validate(); trips[name] = trip; outcomes[name] = "available"
                    } else { outcomes[name] = "unavailable" }
                } catch is CancellationError { throw CancellationError() }
                catch let error as RoutingFailure {
                    outcomes[name] = error.rawValue
                    if [.throttled, .authentication].contains(error) { throw error }
                } catch { outcomes[name] = "provider_failure" }
                calls[name] = memo.calls; walls[name] = RoutingFixtures.seconds(clock)
            }
            let a = trips["apple"], v = trips["valhalla"], both = a != nil && v != nil
            rows.append(.init(caseID: caseID, evidence: "STATIC_GTFS_LIVE_WALKING_CONTROLLED_APPROACH_NOT_REALTIME_TJ", bothAvailable: both, appleOutcome: outcomes["apple"]!, valhallaOutcome: outcomes["valhalla"]!, appleCalls: calls["apple"]!, valhallaCalls: calls["valhalla"]!, appleWallSeconds: walls["apple"]!, valhallaWallSeconds: walls["valhalla"]!, valhallaToAppleTravelRatio: both && a!.seconds > 0 ? v!.seconds / a!.seconds : nil, appleRides: a?.rides.map { $0.pattern.effectiveRouteID }, valhallaRides: v?.rides.map { $0.pattern.effectiveRouteID }, sourceSHA256: feed.source.sourceSHA256))
            try checkpoint(rows)
        }
        return rows
    }
}
