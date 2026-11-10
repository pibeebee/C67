import CryptoKit
import Foundation

public struct MatchedRoadRow: Codable, Sendable {
    public var pairID: String
    public var querySHA256: String
    public var provider: String
    public var mode: RouteMode
    public var order: Int
    public var outcome: String
    public var wallSeconds: Double
    public var pacingSeconds: Double
    public var serviceSeconds: Double
    public var geometryPoints: Int
    public var maximumEndpointGapMeters: Double?
}
public struct MatchedRoadComparison: Codable, Sendable {
    public var pairID: String
    public var mode: RouteMode
    public var bothAvailable: Bool
    public var valhallaToAppleServiceRatio: Double?
    public var valhallaToAppleETARatio: Double?
    public var valhallaToAppleDistanceRatio: Double?
    public var geometryMedianGapMeters: Double?
}
public struct MatchedRoadOutput: Codable, Sendable {
    public var startedAt: Date
    public var appleAPI: String
    public var plannedPairs: Int
    public var stoppedReason: String?
    public var rows: [MatchedRoadRow] = []
    public var comparisons: [MatchedRoadComparison] = []
}
public enum RouteGeometryComparison {
    /// Symmetric sampled point-to-segment difference, not route legality or field accuracy.
    public static func medianGap(_ a: [RoutingPoint], _ b: [RoutingPoint]) -> Double? {
        guard a.count >= 2, b.count >= 2 else { return nil }
        func directed(_ points: [RoutingPoint], _ line: [RoutingPoint]) -> [Double] {
            let samples = min(32, points.count)
            return (0 ..< samples).map { index in
                let point = points[index * (points.count - 1) / max(1, samples - 1)]
                return zip(line, line.dropFirst()).map { segmentGap(point, $0, $1) }.min()!
            }
        }
        let values = (directed(a, b) + directed(b, a)).sorted()
        return values[values.count / 2]
    }
    private static func segmentGap(_ p: RoutingPoint, _ a: RoutingPoint, _ b: RoutingPoint) -> Double {
        let scale = Double.pi * 6371000 / 180, longitudeScale = scale * cos(p.latitude * .pi / 180)
        let ax = (a.longitude - p.longitude) * longitudeScale, ay = (a.latitude - p.latitude) * scale
        let bx = (b.longitude - p.longitude) * longitudeScale, by = (b.latitude - p.latitude) * scale
        let dx = bx - ax, dy = by - ay, squared = dx * dx + dy * dy
        let t = squared > 0 ? min(1, max(0, -(ax * dx + ay * dy) / squared)) : 0
        return hypot(ax + t * dx, ay + t * dy)
    }
}
@MainActor public enum MatchedRoadCampaign {
    public static func queries(manifest: RoutingManifest, repetitions: Int, smoke: Bool, departure: Date) throws -> [(String, RoutingQuery)] {
        try manifest.validate()
        guard manifest.venues.count >= 2, (1 ... 3).contains(repetitions) else { throw RoutingFailure.invalidInput }
        let venues = manifest.venues
        var cases: [(String, RoutingQuery)] = []
        for repetition in 0 ..< repetitions {
            for index in (smoke ? [0] : Array(venues.indices)) {
                let a = venues[index], b = venues[(index + 1) % venues.count]
                for reversed in (smoke ? [false] : [false, true]) {
                    let from = reversed ? b : a, to = reversed ? a : b
                    for mode in RouteMode.allCases {
                        let query = RoutingQuery(from: .init(id: from.id, revision: "sourced-osm-poi", point: from.displayPoint), to: .init(id: to.id, revision: "sourced-osm-poi", point: to.displayPoint), mode: mode, departure: departure, geometry: true)
                        cases.append(("\(from.id)>\(to.id):\(mode.rawValue):r\(repetition)", query))
                    }
                }
            }
        }
        return cases
    }
    public static func fingerprint(_ query: RoutingQuery) throws -> String {
        try query.validate()
        let text = "\(query.from)|\(query.to)|\(query.mode)|\(query.departure.timeIntervalSince1970)|\(query.geometry)"
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public static func run(manifest: RoutingManifest, apple: any RoutingProvider, valhalla: any RoutingProvider, smoke: Bool = false, checkpoint: (MatchedRoadOutput) throws -> Void) async throws -> MatchedRoadOutput {
        let started = Date()
        let departure = Calendar(identifier: .gregorian).dateInterval(of: .minute, for: started.addingTimeInterval(1800))!.start
        let definitions = try queries(manifest: manifest, repetitions: smoke ? 1 : 3, smoke: smoke, departure: departure)
        var output = MatchedRoadOutput(startedAt: started, appleAPI: apple.name, plannedPairs: definitions.count)
        for (index, definition) in definitions.enumerated() {
            try Task.checkCancellation()
            let (id, query) = definition
            let fingerprint = try fingerprint(query)
            var results: [String: RoutingResult] = [:], seconds: [String: Double] = [:]
            let order = index.isMultiple(of: 2) ? ["apple", "valhalla"] : ["valhalla", "apple"]
            for (position, name) in order.enumerated() {
                let provider = name == "apple" ? apple : valhalla
                let clock = ContinuousClock.now
                var result: RoutingResult?, outcome = "available"
                do {
                    result = try await provider.route(query)
                    if result == nil { outcome = "unavailable" }
                    if let result, result.query != query { throw RoutingFailure.invalidResponse }
                } catch is CancellationError { throw CancellationError() }
                catch let error as RoutingFailure {
                    outcome = error.rawValue
                    if [.throttled, .authentication, .budgetExhausted].contains(error) { output.stoppedReason = name + ":" + error.rawValue }
                } catch { outcome = "provider_failure" }
                let wall = RoutingFixtures.seconds(clock)
                let pacing = (provider as? AppleNativeRoutingProvider)?.lastPacingSeconds ?? 0
                let service = max(0, wall - pacing)
                seconds[name] = service
                if let result, outcome == "available" { results[name] = result }
                let gaps = [result?.snappedFrom.flatMap { p in query.from.point.map { p.distance(to: $0) } }, result?.snappedTo.flatMap { p in query.to.point.map { p.distance(to: $0) } }].compactMap { $0 }
                output.rows.append(.init(pairID: id, querySHA256: fingerprint, provider: name, mode: query.mode, order: position, outcome: outcome, wallSeconds: wall, pacingSeconds: min(wall, pacing), serviceSeconds: service, geometryPoints: result?.geometry.count ?? 0, maximumEndpointGapMeters: gaps.max()))
            }
            let a = results["apple"], b = results["valhalla"]
            let both = a != nil && b != nil
            output.comparisons.append(.init(pairID: id, mode: query.mode, bothAvailable: both,
                                            valhallaToAppleServiceRatio: both && (seconds["apple"] ?? 0) > 0 ? seconds["valhalla"]! / seconds["apple"]! : nil,
                                            valhallaToAppleETARatio: both && a!.seconds > 0 ? b!.seconds / a!.seconds : nil,
                                            valhallaToAppleDistanceRatio: both && a!.meters > 0 ? b!.meters / a!.meters : nil,
                                            geometryMedianGapMeters: both ? RouteGeometryComparison.medianGap(a!.geometry, b!.geometry) : nil))
            try checkpoint(output)
            print("PAIRED \(index + 1)/\(definitions.count) \(query.mode.rawValue) apple=\(a == nil ? "unavailable" : "available") valhalla=\(b == nil ? "unavailable" : "available")")
            if output.stoppedReason != nil { break }
        }
        return output
    }
}
