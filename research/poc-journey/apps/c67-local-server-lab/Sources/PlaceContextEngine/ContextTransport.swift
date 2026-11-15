import Foundation

public enum ContextTransport: String, Codable, Sendable, CaseIterable { case automobile, transjakarta }
public enum ContextVisitOrder: String, Codable, Sendable { case optimized, fixed }

public struct ContextRoutePoint: Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}
public struct ContextRouteSegment: Codable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var label: String
    public var from: ContextRoutePoint
    public var to: ContextRoutePoint
    public var points: [ContextRoutePoint]
    public var geometryStatus: String
    public var departure: Date?
    public var arrival: Date?
    public init(id: String, kind: String, label: String, from: ContextRoutePoint, to: ContextRoutePoint, points: [ContextRoutePoint] = [], geometryStatus: String = "load_road", departure: Date? = nil, arrival: Date? = nil) {
        self.id = id; self.kind = kind; self.label = label; self.from = from; self.to = to; self.points = points; self.geometryStatus = geometryStatus; self.departure = departure; self.arrival = arrival
    }
}
public struct ContextTransportDetails: Codable, Sendable {
    public var mode: String
    public var walkingSeconds: Double
    public var transitWaitingSeconds: Double
    public var summary: String
    public var segments: [ContextRouteSegment]
    public var sourceSHA256: String?
    public var attributionURL: URL?
    public var licenseURL: URL?
    public var sourceCheckedAt: Date?
    public var sourcePublisher: String?
    public var searchLimited: Bool
    public init(mode: String, walkingSeconds: Double = 0, transitWaitingSeconds: Double = 0, summary: String = "", segments: [ContextRouteSegment] = [], sourceSHA256: String? = nil, searchLimited: Bool = false) {
        self.mode = mode; self.walkingSeconds = walkingSeconds; self.transitWaitingSeconds = transitWaitingSeconds
        self.summary = summary; self.segments = segments; self.sourceSHA256 = sourceSHA256; self.searchLimited = searchLimited
    }
}

extension ContextItineraryResult {
    /// Travel already includes transit waiting. Keep elapsed arithmetic unchanged.
    public var transitWaitingSeconds: Double { legs.reduce(0) { $0 + ($1.evidence.details?.transitWaitingSeconds ?? 0) } }
    public var totalWaitingSeconds: Double { waitingSeconds + transitWaitingSeconds }
    public var walkingSeconds: Double { legs.reduce(0) { $0 + ($1.evidence.details?.walkingSeconds ?? 0) } }
}
