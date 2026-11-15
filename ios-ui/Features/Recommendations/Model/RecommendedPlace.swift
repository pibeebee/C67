import Foundation
import MapKit
import C67Domain

/// Optional display metadata is supplied only when it is actually available.
struct RecommendedPlace: Identifiable, Equatable, Sendable {
    var place: PlanningPlace
    var category: String?
    var address: String?
    var previewImage: String?

    var id: UUID { place.id }

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
