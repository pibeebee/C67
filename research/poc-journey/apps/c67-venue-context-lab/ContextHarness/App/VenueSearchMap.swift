import MapKit
import SwiftUI
import DynamicTripContracts
import PlaceContextEngine

struct VenueSearchMap: View {
    private struct Pin: Identifiable {
        var id: String
        var name: String
        var latitude: Double
        var longitude: Double
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    private let pins: [Pin]

    init(places: [VenuePlace]) {
        pins = places.compactMap { place in
            guard let id = place.id, let point = place.location else { return nil }
            return .init(id: id, name: place.displayName?.text ?? "", latitude: point.latitude, longitude: point.longitude)
        }
    }

    init(candidates: [DynamicAppleCandidate]) {
        pins = candidates.map { .init(id: $0.id, name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        if !pins.isEmpty {
            Map(initialPosition: .automatic) {
                ForEach(pins) { pin in Marker(pin.name, coordinate: pin.coordinate) }
            }
            .id(pins.map(\.id))
            .frame(height: 175)
            .accessibilityLabel("Peta hasil pencarian")
        }
    }
}
