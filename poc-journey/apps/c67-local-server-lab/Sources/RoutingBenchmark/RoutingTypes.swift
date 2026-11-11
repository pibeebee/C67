import Foundation
import PlaceContextEngine

public enum RoutingFailure: String, Error, Codable, Sendable {
    case invalidInput, missingConfiguration, missingVisitContext, disabledByScope, missingAccess, privateAccess, unavailable, invalidResponse, budgetExhausted, authentication, throttled, transport, staleResult, deadlineExceeded
}
public enum RouteMode: String, Codable, Sendable, CaseIterable { case automobile, walking }
public enum RouteBackend: String, Codable, Sendable, CaseIterable { case applePin = "apple_pin", appleAccess = "apple_access", googlePlaceID = "google_place_id", valhallaAccess = "valhalla_access" }
public struct RoutingPoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(_ latitude: Double, _ longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    public var valid: Bool { latitude.isFinite && longitude.isFinite && (-6.6 ... -5.9).contains(latitude) && (106.5 ... 107.2).contains(longitude) }
    public func distance(to b: Self) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((b.latitude - latitude) * r / 2), 2) + cos(latitude * r) * cos(b.latitude * r) * pow(sin((b.longitude - longitude) * r / 2), 2)
        return 6371000 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}
public enum AccessKind: String, Codable, Sendable { case pedestrianEntrance, vehicleAccess, dropoff, parking }
public enum AccessStatus: String, Codable, Sendable { case synthetic, sourceSupported, unverified }
public struct AccessPoint: Codable, Sendable {
    public var id: String
    public var revision: Int
    public var point: RoutingPoint
    public var kind: AccessKind
    public var modes: [RouteMode]
    public var publicAccess: Bool?
    public var sourceURL: String
    public var checkedAt: Date
    public var status: AccessStatus
    public init(id: String, revision: Int = 1, point: RoutingPoint, kind: AccessKind, modes: [RouteMode], publicAccess: Bool?, sourceURL: String, checkedAt: Date, status: AccessStatus) {
        self.id = id; self.revision = revision; self.point = point; self.kind = kind; self.modes = modes; self.publicAccess = publicAccess; self.sourceURL = sourceURL; self.checkedAt = checkedAt; self.status = status
    }
}
public struct RoutingVenue: Codable, Sendable {
    public var id: String
    public var name: String
    public var area: String
    public var displayPoint: RoutingPoint
    public var applePoint: RoutingPoint?
    public var googlePlaceID: String?
    public var accesses: [AccessPoint]
    public var reference: AccessPoint?
    public var sourceURL: String
    public init(id: String, name: String, area: String, displayPoint: RoutingPoint, applePoint: RoutingPoint? = nil, googlePlaceID: String? = nil, accesses: [AccessPoint] = [], reference: AccessPoint? = nil, sourceURL: String) {
        self.id = id; self.name = name; self.area = area; self.displayPoint = displayPoint; self.applePoint = applePoint; self.googlePlaceID = googlePlaceID; self.accesses = accesses; self.reference = reference; self.sourceURL = sourceURL
    }
    public func endpoint(backend: RouteBackend, mode: RouteMode, now: Date, synthetic: Bool = false) throws -> RoutingEndpoint {
        if backend == .googlePlaceID {
            guard let googlePlaceID, GooglePlacesClient.validID(googlePlaceID) else { throw RoutingFailure.missingConfiguration }
            return .init(id: id, revision: "google-place-id", point: nil, googlePlaceID: googlePlaceID)
        }
        if backend == .applePin {
            guard let applePoint, applePoint.valid else { throw RoutingFailure.missingConfiguration }
            return .init(id: id, revision: "apple-pin", point: applePoint)
        }
        let candidates = accesses.filter { $0.modes.contains(mode) && (mode == .walking ? $0.kind == .pedestrianEntrance : $0.kind != .pedestrianEntrance) }
        guard !candidates.contains(where: { $0.publicAccess == false }) || candidates.contains(where: { $0.publicAccess == true }) else { throw RoutingFailure.privateAccess }
        guard let access = candidates.first(where: {
            $0.publicAccess == true && $0.point.valid && !$0.sourceURL.isEmpty && $0.checkedAt <= now.addingTimeInterval(300) && now.timeIntervalSince($0.checkedAt) < 30 * 86400 && ($0.status == .sourceSupported || (synthetic && $0.status == .synthetic))
        }) else { throw RoutingFailure.missingAccess }
        return .init(id: id, revision: "\(access.id):\(access.revision)", point: access.point)
    }
}
public struct RoutingEndpoint: Codable, Hashable, Sendable {
    public var id: String
    public var revision: String
    public var point: RoutingPoint?
    public var googlePlaceID: String?
    public init(id: String, revision: String, point: RoutingPoint?, googlePlaceID: String? = nil) { self.id = id; self.revision = revision; self.point = point; self.googlePlaceID = googlePlaceID }
    public func validate() throws {
        guard !id.isEmpty, !revision.isEmpty, (point?.valid == true) != (googlePlaceID != nil), googlePlaceID.map(GooglePlacesClient.validID) ?? true else { throw RoutingFailure.invalidInput }
    }
}
public struct RoutingQuery: Hashable, Sendable {
    public var from: RoutingEndpoint
    public var to: RoutingEndpoint
    public var mode: RouteMode
    public var departure: Date
    public var geometry = false
    public init(from: RoutingEndpoint, to: RoutingEndpoint, mode: RouteMode, departure: Date, geometry: Bool = false) { self.from = from; self.to = to; self.mode = mode; self.departure = departure; self.geometry = geometry }
    public func validate() throws {
        try from.validate(); try to.validate()
        guard departure.timeIntervalSince1970.isFinite else { throw RoutingFailure.invalidInput }
    }
}
/// Ephemeral provider content. Deliberately not Codable: no raw route export path.
public struct RoutingResult: Sendable {
    public var query: RoutingQuery
    public var seconds: Double
    public var meters: Double
    public var snappedFrom: RoutingPoint?
    public var snappedTo: RoutingPoint?
    public var geometry: [RoutingPoint]
    public var source: String
    public var traffic: String
    public init(query: RoutingQuery, seconds: Double, meters: Double, snappedFrom: RoutingPoint? = nil, snappedTo: RoutingPoint? = nil, geometry: [RoutingPoint] = [], source: String, traffic: String) throws {
        try query.validate()
        guard seconds.isFinite, seconds >= 0, meters.isFinite, meters >= 0, !source.isEmpty,
              snappedFrom.map(\.valid) ?? true, snappedTo.map(\.valid) ?? true, geometry.allSatisfy(\.valid),
              geometry.count <= 100000 else { throw RoutingFailure.invalidResponse }
        self.query = query; self.seconds = seconds; self.meters = meters; self.snappedFrom = snappedFrom; self.snappedTo = snappedTo; self.geometry = geometry; self.source = source; self.traffic = traffic
    }
}
@MainActor public protocol RoutingProvider: Sendable {
    var name: String { get }
    func route(_ query: RoutingQuery) async throws -> RoutingResult?
}
@MainActor public final class RoutingBudget {
    public private(set) var requests = 0
    public private(set) var elements = 0
    public let requestLimit: Int
    public let elementLimit: Int
    public init(requestLimit: Int = 200, elementLimit: Int = 1000) throws {
        guard (1 ... 200).contains(requestLimit), (0 ... 1000).contains(elementLimit) else { throw RoutingFailure.invalidInput }
        self.requestLimit = requestLimit; self.elementLimit = elementLimit
    }
    public func reserve(elements count: Int = 0) throws {
        guard count >= 0, requests < requestLimit, count <= elementLimit - elements else { throw RoutingFailure.budgetExhausted }
        requests += 1; elements += count
    }
}
public enum AccessEvaluation {
    public static func status(venue: RoutingVenue, result: RoutingResult, selectionSource: String?) -> String {
        guard let reference = venue.reference, reference.publicAccess == true, reference.status == .sourceSupported,
              reference.modes.contains(result.query.mode), reference.point.valid,
              reference.checkedAt <= result.query.departure, result.query.departure.timeIntervalSince(reference.checkedAt) < 30 * 86400,
              let end = result.snappedTo else { return "unverified" }
        if reference.sourceURL == selectionSource { return "same_source_consistency_only" }
        // Distance alone is diagnostic, never a certificate of public door connectivity.
        return end.distance(to: reference.point) <= 25 ? "near_reference_connectivity_unverified" : "reference_mismatch"
    }
}
