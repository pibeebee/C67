import Foundation
import MapKit
import CoreLocation
import C67Domain

/// Optional display metadata is supplied only when it is actually available.
struct RecommendedPlace: Identifiable, Equatable, Sendable {
    var place: PlanningPlace
    var category: String?
    var address: String?
    var previewImage: String?

    var id: UUID { place.id }

    func straightLineDistance(from origin: PlanningPoint?) -> CLLocationDistance? {
        guard let origin else { return nil }
        let source = CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
        let destination = CLLocationCoordinate2D(latitude: place.location.latitude, longitude: place.location.longitude)
        guard CLLocationCoordinate2DIsValid(source), CLLocationCoordinate2DIsValid(destination) else { return nil }
        return CLLocation(latitude: source.latitude, longitude: source.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
    }

    func distanceDescription(from origin: PlanningPoint?) -> String {
        guard let meters = straightLineDistance(from: origin), meters.isFinite else {
            return String(localized: "Distance unavailable")
        }
        if meters < 1_000 {
            let rounded = Int((meters / 10).rounded() * 10)
            return String(localized: "≈ \(rounded) m away")
        }
        let kilometers = (meters / 1_000).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "≈ \(kilometers) km away")
    }

    var poiPresentation: (label: String, symbol: String)? {
        guard let raw = place.categories.first else { return nil }
        switch MKPointOfInterestCategory(rawValue: raw) {
        case .restaurant: return (String(localized: "Restaurant"), "fork.knife")
        case .cafe: return (String(localized: "Café"), "cup.and.saucer.fill")
        case .bakery: return (String(localized: "Bakery"), "birthday.cake")
        case .museum: return (String(localized: "Museum"), "building.columns")
        case .library: return (String(localized: "Library"), "books.vertical")
        case .park: return (String(localized: "Park"), "tree")
        case .beach: return (String(localized: "Beach"), "sun.horizon")
        case .movieTheater: return (String(localized: "Cinema"), "film")
        case .theater: return (String(localized: "Theater"), "theatermasks")
        case .amusementPark: return (String(localized: "Amusement park"), "ticket")
        case .aquarium: return (String(localized: "Aquarium"), "fish")
        case .zoo: return (String(localized: "Zoo"), "pawprint")
        case .store: return (String(localized: "Store"), "bag")
        case .nightlife: return (String(localized: "Nightlife"), "wineglass")
        default: return nil
        }
    }
}
