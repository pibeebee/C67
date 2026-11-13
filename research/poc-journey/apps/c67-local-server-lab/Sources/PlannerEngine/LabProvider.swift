import Foundation

public struct LabETAQuery: Codable, Hashable, Sendable {
    public var fromID: String; public var toID: String
    public var fromLatitude: Double; public var fromLongitude: Double
    public var toLatitude: Double; public var toLongitude: Double
    public var mode: String; public var departure: Date
    public init(fromID: String, toID: String, fromLatitude: Double, fromLongitude: Double,
                toLatitude: Double, toLongitude: Double, mode: String, departure: Date) {
        self.fromID = fromID; self.toID = toID; self.fromLatitude = fromLatitude
        self.fromLongitude = fromLongitude; self.toLatitude = toLatitude
        self.toLongitude = toLongitude; self.mode = mode; self.departure = departure
    }
    var nativeKey: String { "\(fromID)>\(toID):\(mode):\(mode == "walking" ? 0 : departure.timeIntervalSince1970)" }
    public var groupKey: String { "\(fromLatitude):\(fromLongitude):\(mode):\(departure.timeIntervalSince1970)" }
}
public struct LabETAValue: Codable, Sendable {
    public var query: LabETAQuery; public var seconds: Double?; public var distance: Double?
    public var status: String; public var note: String
    public init(query: LabETAQuery, seconds: Double? = nil, distance: Double? = nil,
                status: String = "available", note: String = "") {
        self.query = query; self.seconds = seconds; self.distance = distance
        self.status = status; self.note = note
    }
    var native: NativeTripETA {
        let valid = seconds.map { $0.isFinite && $0 >= 0 } ?? false
        return .init(id: query.nativeKey, mode: NativeTripMode(rawValue: query.mode) ?? .automobile,
                     seconds: valid ? seconds : nil, distance: distance,
                     expectedDeparture: query.departure,
                     expectedArrival: valid ? query.departure.addingTimeInterval(seconds!) : nil,
                     status: valid ? status : "unavailable", note: note)
    }
}
public struct LabProviderMetrics: Codable, Sendable {
    public var calls = 0; public var cells = 0; public var failures = 0
    public var deduplicated = 0; public var cacheHits = 0
    public var requests: [[LabETAQuery]] = []
    public init() {}
}
@MainActor public protocol LabETAProvider: Sendable {
    var metrics: LabProviderMetrics { get }
    func values(_ queries: [LabETAQuery]) async throws -> [LabETAValue]
}
@MainActor public final class LabOracle: LabETAProvider {
    public private(set) var metrics = LabProviderMetrics()
    public let fault: String?
    public init(fault: String? = nil) { self.fault = fault }
    public func values(_ queries: [LabETAQuery]) async throws -> [LabETAValue] {
        try Task.checkCancellation()
        guard !queries.isEmpty, queries.count <= 10,
              Set(queries.map(\.groupKey)).count == 1 else { throw IntegrationError.invalid("Invalid oracle batch") }
        metrics.calls += 1; metrics.cells += queries.count; metrics.requests.append(queries)
        return queries.map { q in
            if fault == "all_eta_unavailable" || (fault == "partial_eta" && q.toID == "gbk") {
                metrics.failures += 1
                return .init(query: q, status: "unavailable", note: "Declared synthetic fault")
            }
            let a = NativeTripPoint(id: q.fromID, title: q.fromID, query: q.fromID,
                                    latitude: q.fromLatitude, longitude: q.fromLongitude)
            let b = NativeTripPoint(id: q.toID, title: q.toID, query: q.toID,
                                    latitude: q.toLatitude, longitude: q.toLongitude)
            let distance = a.distance(to: b)
            let minute = TripClock.minute(q.departure)
            let peak = (420 ..< 600).contains(minute) || (960 ..< 1140).contains(minute)
            let seconds = (300 + distance / 8) * (peak ? 1.35 : 1)
            return .init(query: q, seconds: seconds, distance: distance,
                         note: "Synthetic distance/time oracle v1; NOT observed travel")
        }
    }
}
/// Explicit grouping, stable identity, and per-operation deduplication. No provider persistence.
@MainActor public final class LabAcquisition {
    let provider: any LabETAProvider
    public init(_ provider: any LabETAProvider) { self.provider = provider }
    public func fetch(_ queries: [LabETAQuery], bulk: Bool) async throws -> [LabETAValue] {
        var unique: [LabETAQuery] = []; var seen = Set<LabETAQuery>()
        for q in queries { if seen.insert(q).inserted { unique.append(q) } }
        var result: [LabETAQuery: LabETAValue] = [:]
        var groups: [[LabETAQuery]] = []
        for q in unique {
            if bulk, let index = groups.firstIndex(where: { $0[0].groupKey == q.groupKey && $0.count < 10 }) {
                groups[index].append(q)
            } else { groups.append([q]) }
        }
        for group in groups {
            try Task.checkCancellation()
            let values = try await provider.values(group)
            guard values.count == group.count, Set(values.map(\.query)) == Set(group),
                  Set(values.map(\.query)).count == values.count else { throw IntegrationError.invalid("Invalid batch identity/coverage") }
            for value in values { result[value.query] = value }
        }
        return queries.map { result[$0]! }
    }
}
