import Foundation
import CoreLocation
import MapKit

struct CalculatedRoute {
    let polyline: MKPolyline
    let distance: Double
    let expectedTravelTime: Double
    let instructions: [String]
}

@MainActor protocol DirectionsProviding {
    func calculate(origin: CLLocationCoordinate2D, target: CLLocationCoordinate2D) async throws -> CalculatedRoute
    func cancel()
}

@MainActor final class AppleDirectionsProvider: DirectionsProviding {
    private var active: MKDirections?

    func calculate(origin: CLLocationCoordinate2D, target: CLLocationCoordinate2D) async throws -> CalculatedRoute {
        let request = MKDirections.Request()
        if #available(iOS 26.0, *) {
            request.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
            request.destination = MKMapItem(location: CLLocation(latitude: target.latitude, longitude: target.longitude), address: nil)
        } else {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target))
        }
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        active = directions
        defer { if active === directions { active = nil } }
        let response = try await directions.calculate()
        try Task.checkCancellation()
        guard let route = response.routes.first else { throw MKError(.directionsNotFound) }
        return CalculatedRoute(polyline: route.polyline, distance: route.distance,
                               expectedTravelTime: route.expectedTravelTime,
                               instructions: route.steps.map(\.instructions).filter { !$0.isEmpty })
    }

    func cancel() { active?.cancel(); active = nil }
}
