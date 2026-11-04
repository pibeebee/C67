import Foundation
import Observation

public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(_ latitude: Double, _ longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    public var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
    // Used only for ordering, never reported as route distance.
    public func distance(to other: Self) -> Double {
        let lat = (other.latitude - latitude) * .pi / 180
        let lon = (other.longitude - longitude) * .pi / 180
        let a = pow(sin(lat / 2), 2) + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180) * pow(sin(lon / 2), 2)
        return 6371000 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}

public enum Theme: String, CaseIterable, Codable, Sendable {
    case history, culture, nature, food, mixed
}
public enum TravelMode: String, CaseIterable, Codable, Sendable { case walking, driving }
public struct Place: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var coordinate: Coordinate
    public var category: String
    public var address: String
    public var themes: Set<Theme>
    public var provenance: String
    public var websiteURL: URL?
    public init(id: String, name: String, coordinate: Coordinate, category: String, address: String = "Unknown", themes: Set<Theme>, provenance: String = "MapKit", websiteURL: URL? = nil) {
        self.id = id; self.name = name; self.coordinate = coordinate; self.category = category
        self.address = address; self.themes = themes; self.provenance = provenance; self.websiteURL = websiteURL
    }
}
public struct Recommendation: Sendable {
    public var placeID: String
    public var reason: String
    public init(_ placeID: String, reason: String) { self.placeID = placeID; self.reason = reason }
}
public struct TripPreferences: Sendable {
    public var origin: Coordinate
    public var start: Date
    public var duration: TimeInterval
    public var theme: Theme
    public var mode: TravelMode
    public var count: Int
    public var visitDuration: TimeInterval
    public var buffer: TimeInterval
    public var timeZoneID: String
    public var requireHours: Bool
    public init(origin: Coordinate = .init(-6.1754, 106.8272), start: Date, duration: TimeInterval = 18000,
                theme: Theme = .history, mode: TravelMode = .walking, count: Int = 4,
                visitDuration: TimeInterval = 2700, buffer: TimeInterval = 300,
                timeZoneID: String = "Asia/Jakarta", requireHours: Bool = false) {
        self.origin = origin; self.start = start; self.duration = duration; self.theme = theme
        self.mode = mode; self.count = count; self.visitDuration = visitDuration; self.buffer = buffer
        self.timeZoneID = timeZoneID; self.requireHours = requireHours
    }
}
public struct RouteLeg: Codable, Sendable {
    public var originID: String
    public var destinationID: String
    public var mode: TravelMode
    public var departure: Date
    public var distance: Double
    public var travelTime: TimeInterval
    public var geometry: [Coordinate]
    public var provenance: String
    public init(originID: String, destinationID: String, mode: TravelMode, departure: Date, distance: Double,
                travelTime: TimeInterval, geometry: [Coordinate] = [], provenance: String = "MKDirections") {
        self.originID = originID; self.destinationID = destinationID; self.mode = mode; self.departure = departure
        self.distance = distance; self.travelTime = travelTime; self.geometry = geometry; self.provenance = provenance
    }
}
public struct HoursWindow: Sendable {
    public var opens: Date
    public var closes: Date
    public init(opens: Date, closes: Date) { self.opens = opens; self.closes = closes }
}
public enum OpeningHours: Sendable {
    case unknown
    case unknownDetail(String)
    case verified(windows: [HoursWindow], source: String)
    case demo(windows: [HoursWindow])
    case sourced(windows: [HoursWindow], metadata: HoursMetadata)
    public var label: String {
        switch self {
        case .unknown: "Unknown — verify before visiting"
        case .unknownDetail(let reason): "Unknown — \(reason)"
        case .verified(_, let source): "Verified: \(source)"
        case .demo: "DEMO ONLY — synthetic opening hours"
        case .sourced: "Hours according to OpenStreetMap — special hours may differ"
        }
    }
    public var windows: [HoursWindow]? {
        switch self { case .unknown, .unknownDetail: nil; case .verified(let w, _), .demo(let w), .sourced(let w, _): w }
    }
}
public struct HoursMetadata: Sendable {
    public var objectID: String
    public var expression: String
    public var sourceURL: URL
    public var websiteURL: URL?
    public var fetchedAt: Date
    public var checkedDate: String?
    public init(objectID: String, expression: String, sourceURL: URL, websiteURL: URL?, fetchedAt: Date, checkedDate: String?) {
        self.objectID = objectID; self.expression = expression; self.sourceURL = sourceURL
        self.websiteURL = websiteURL; self.fetchedAt = fetchedAt; self.checkedDate = checkedDate
    }
}
public struct OptimizationReport: Sendable {
    public var evaluatedOrders: Int = 0
    public var matrixComplete = false
    public var matrixRequests: Int = 0
    public var detailRequests: Int = 0
    public var snapshotTravelTime: TimeInterval?
    public var baselineTravelTime: TimeInterval?
    public var initialBaselineTravelTime: TimeInterval?
    public var heuristicBaselineTravelTime: TimeInterval?
    public var networkRequests: Int?
    public var cacheHits: Int?
    public var validatedAlternatives: Int = 0
    public var failures: [String] = []
    public init() {}
}
public struct ScheduledStop: Identifiable, Sendable {
    public var id: String { place.id }
    public var place: Place
    public var arrival: Date
    public var departure: Date
    public var leg: RouteLeg
    public var hours: OpeningHours
    public var reason: String
    public var score: Double
}
public struct Itinerary: Sendable {
    public var stops: [ScheduledStop]
    public var baselineTravelTime: TimeInterval? = nil
    public var report: OptimizationReport? = nil
    public var startedAt: Date? = nil
    public var bufferPerStop: TimeInterval = 0
    public var waitingTime: TimeInterval {
        var current = startedAt ?? stops.first?.leg.departure ?? Date(timeIntervalSince1970: 0)
        var total: TimeInterval = 0
        for stop in stops { total += max(0, stop.arrival.timeIntervalSince(current) - stop.leg.travelTime - bufferPerStop); current = stop.departure }
        return total
    }
    public var distance: Double { stops.reduce(0) { $0 + $1.leg.distance } }
    public var travelTime: TimeInterval { stops.reduce(0) { $0 + $1.leg.travelTime } }
    public var visitTime: TimeInterval { stops.reduce(0) { $0 + $1.departure.timeIntervalSince($1.arrival) } }
}
public enum PlanningError: Error, LocalizedError, Equatable {
    case invalidInput, invalidIDs, noPlaces, unavailableModel, unavailableRoute, incompleteMatrix, insufficientTime, hoursConflict(String), toolBudget, deadlineExceeded, throttled
    public var errorDescription: String? {
        switch self {
        case .invalidInput: "Check coordinates, date, duration and stop count."
        case .invalidIDs: "The model returned duplicate or unrecognized place IDs. Generate again."
        case .noPlaces: "No matching places were retrieved. Try another theme or starting location."
        case .unavailableModel: "Apple Intelligence is unavailable. Enable it and wait for model assets, or explicitly choose the fixture demo."
        case .unavailableRoute: "MapKit could not provide a valid route. No travel estimate was invented."
        case .incompleteMatrix: "Route estimates are incomplete. Check the network and try again."
        case .throttled: "Apple Maps is receiving too many requests. Please try again later."
        case .deadlineExceeded: "Route planning timed out. Try fewer stops."
        case .insufficientTime: "No schedule fits the current route estimates, available hours and time budget. Reduce stops or increase duration."
        case .hoursConflict(let id): "Opening hours conflict for \(id). Choose another date or fewer stops."
        case .toolBudget: "The experiment's bounded tool-call budget was reached."
        }
    }
}

@MainActor public protocol RouteProviding {
    var networkRequests: Int? { get }
    var cacheHits: Int? { get }
    func route(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg
    func estimate(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg
}
public extension RouteProviding {
    var networkRequests: Int? { nil }
    var cacheHits: Int? { nil }
    func estimate(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg {
        try await route(from: from, to: to, mode: mode, departure: departure)
    }
}
@MainActor public protocol OpeningHoursProviding {
    func hours(for place: Place) -> OpeningHours
    func fetchHours(for places: [Place], start: Date, end: Date, timeZone: TimeZone) async -> [String: OpeningHours]
}
public extension OpeningHoursProviding {
    func fetchHours(for places: [Place], start: Date, end: Date, timeZone: TimeZone) async -> [String: OpeningHours] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, hours(for: $0)) })
    }
}
public struct DiagnosticEvent: Identifiable, Sendable {
    public let id = UUID()
    public var message: String
}
@MainActor @Observable public final class Diagnostics {
    public var events: [DiagnosticEvent] = []
    public var phase = "Preparing trip…"
    public init() {}
    public func record(_ message: String) { events.append(.init(message: message)); if events.count > 100 { events.removeFirst() } }
}
