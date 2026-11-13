import Foundation
import MapKit

@MainActor public final class MapServices: RouteProviding {
    public private(set) var places: [Place] = []
    private var etaCache: [String: RouteLeg] = [:]
    private var routeCache: [String: RouteLeg] = [:]
    private let diagnostics: Diagnostics
    private var searchCalls = 0
    private var routeCalls = 0
    private var hits = 0
    public var networkRequests: Int? { routeCalls }
    public var cacheHits: Int? { hits }
    public init(diagnostics: Diagnostics) { self.diagnostics = diagnostics }

    public func resolveOrigin(_ query: String) async throws -> Coordinate {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlanningError.invalidInput }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = String(query.prefix(160))
        let response = try await MKLocalSearch(request: request).start()
        guard let result = response.mapItems.first else { throw PlanningError.noPlaces }
        let coordinate = result.location.coordinate
        diagnostics.record("Origin resolved with MKLocalSearch. Query/address/coordinates redacted; review map before planning.")
        return Coordinate(coordinate.latitude, coordinate.longitude)
    }

    public func search(query: String, center: Coordinate, radius: Double, theme: Theme, limit: Int) async throws -> [Place] {
        guard searchCalls < 5 else { throw PlanningError.toolBudget }
        guard center.isValid, radius.isFinite, (100 ... 20000).contains(radius), (1 ... 8).contains(limit) else { throw PlanningError.invalidInput }
        searchCalls += 1
        diagnostics.record("Tool searchPlaces #\(searchCalls): query/location redacted; radius=\(Int(radius)), theme=\(theme.rawValue), max=\(limit)")
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = String(query.prefix(120))
        request.region = MKCoordinateRegion(center: center.mapCoordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        request.regionPriority = .required
        request.resultTypes = .pointOfInterest
        let response: MKLocalSearch.Response
        do { response = try await MKLocalSearch(request: request).start() }
        catch let error as MKError where error.code == .placemarkNotFound {
            diagnostics.record("searchPlaces: MapKit returned no matching places")
            return []
        }
        catch { diagnostics.record("searchPlaces failed: MapKit error (details redacted)"); throw error }
        try Task.checkCancellation()
        var results: [Place] = []
        for item in response.mapItems {
            let c = Coordinate(item.location.coordinate.latitude, item.location.coordinate.longitude)
            guard c.isValid, center.distance(to: c) <= radius, let name = item.name else { continue }
            // MapKit region is a search hint/bounds, explicitly enforce the requested circle.
            let existing = places.first { $0.name == name && $0.coordinate.distance(to: c) < 30 }
            let id = existing?.id ?? item.identifier?.rawValue ?? "place-\(places.count + 1)"
            if results.contains(where: { $0.id == id }) { continue }
            let category = item.pointOfInterestCategory?.rawValue ?? "Unknown category"
            let place = Place(id: id, name: name, coordinate: c, category: category,
                              address: item.address?.fullAddress ?? "Unknown address",
                              themes: Self.themes(category: category, name: name), websiteURL: item.url)
            if !places.contains(where: { $0.id == id }) { places.append(place) }
            results.append(place)
            if results.count == limit { break }
        }
        diagnostics.record("searchPlaces returned \(results.count) real results; hours unknown. IDs: \(results.map(\.id).joined(separator: ", "))")
        return results
    }

    public static func themes(category: String, name: String) -> Set<Theme> {
        let text = (category + " " + name).lowercased()
        var themes: Set<Theme> = []
        if ["museum", "historic", "monument", "memorial"].contains(where: text.contains) { themes.formUnion([.history, .culture]) }
        if ["theater", "theatre", "gallery", "art", "cultural"].contains(where: text.contains) { themes.insert(.culture) }
        if ["park", "garden", "beach", "forest", "nature"].contains(where: text.contains) { themes.insert(.nature) }
        if ["cafe", "café", "coffee", "restaurant", "bakery", "food"].contains(where: text.contains) { themes.insert(.food) }
        return themes
    }

    public func beginOptimization() { routeCalls = 0; hits = 0 }

    private func request(from: Place, to: Place, mode: TravelMode, departure: Date) throws -> MKDirections.Request {
        guard routeCalls < 72 else { throw PlanningError.toolBudget }
        routeCalls += 1
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.coordinate.latitude, longitude: from.coordinate.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.coordinate.latitude, longitude: to.coordinate.longitude), address: nil)
        request.transportType = mode == .walking ? .walking : .automobile
        request.departureDate = departure
        return request
    }
    private func key(from: Place, to: Place, mode: TravelMode, departure: Date) -> String {
        "\(from.id)|\(from.coordinate)|\(to.id)|\(to.coordinate)|\(mode)|\(departure.timeIntervalSince1970)"
    }
    public func estimate(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg {
        let key = key(from: from, to: to, mode: mode, departure: departure)
        if let hit = etaCache[key] { hits += 1; return hit }
        let operation = DirectionOperation(request: try request(from: from, to: to, mode: mode, departure: departure))
        let response: MKDirections.ETAResponse
        do { response = try await operation.eta() }
        catch let error as MKError where error.code == .directionsNotFound { throw PlanningError.unavailableRoute }
        catch let error as MKError where error.code == .loadingThrottled { throw PlanningError.throttled }
        try Task.checkCancellation()
        let leg = RouteLeg(originID: from.id, destinationID: to.id, mode: mode, departure: departure,
                           distance: response.distance, travelTime: response.expectedTravelTime, provenance: "MKDirections ETA snapshot")
        etaCache[key] = leg
        return leg
    }
    public func route(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg {
        let key = key(from: from, to: to, mode: mode, departure: departure)
        if let cached = routeCache[key] { hits += 1; diagnostics.record("Route cache hit: \(from.id) → \(to.id)"); return cached }
        let operation = DirectionOperation(request: try request(from: from, to: to, mode: mode, departure: departure))
        let response: MKDirections.Response
        do { response = try await operation.directions() }
        catch let error as MKError where error.code == .directionsNotFound { throw PlanningError.unavailableRoute }
        catch let error as MKError where error.code == .loadingThrottled { throw PlanningError.throttled }
        try Task.checkCancellation()
        guard let route = response.routes.first else { throw PlanningError.unavailableRoute }
        let geometry = (0 ..< route.polyline.pointCount).map {
            let c = route.polyline.points()[$0].coordinate
            return Coordinate(c.latitude, c.longitude)
        }
        let result = RouteLeg(originID: from.id, destinationID: to.id, mode: mode, departure: departure,
                              distance: route.distance, travelTime: route.expectedTravelTime, geometry: geometry)
        routeCache[key] = result
        diagnostics.record("MKDirections \(from.id) → \(to.id), \(mode.rawValue): route \(Int(result.distance))m, ETA \(Int(result.travelTime))s, geometry \(geometry.count) points")
        return result
    }

}

public extension Coordinate {
    var mapCoordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

@MainActor private final class DirectionOperation {
    private let directions: MKDirections
    init(request: MKDirections.Request) { directions = MKDirections(request: request) }
    func eta() async throws -> MKDirections.ETAResponse {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await directions.calculateETA()
        } onCancel: {
            Task { @MainActor in self.directions.cancel() }
        }
    }
    func directions() async throws -> MKDirections.Response {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await directions.calculate()
        } onCancel: {
            Task { @MainActor in self.directions.cancel() }
        }
    }
}
