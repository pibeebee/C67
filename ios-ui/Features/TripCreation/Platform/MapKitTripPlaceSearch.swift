import Foundation
import SwiftUI
@preconcurrency import MapKit
import C67Domain

@MainActor final class MapKitTripPlaceSearch: TripPlaceSearching {
    private var identities: [String: UUID] = [:]

    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        try await find(query, near: origin, pointsOfInterestOnly: false)
    }

    func recommendations(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        try await find(query, near: origin ?? .init(latitude: -6.20, longitude: 106.84), pointsOfInterestOnly: true)
    }

    private func find(_ query: String, near origin: PlanningPoint?, pointsOfInterestOnly: Bool) async throws -> [RecommendedPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = pointsOfInterestOnly ? [.pointOfInterest] : [.pointOfInterest, .address]
        if let origin {
            request.region = .init(center: .init(latitude: origin.latitude, longitude: origin.longitude),
                                   latitudinalMeters: pointsOfInterestOnly ? 45_000 : 20_000,
                                   longitudinalMeters: pointsOfInterestOnly ? 45_000 : 20_000)
        }
        let search = MKLocalSearch(request: request)
        let response = try await withTaskCancellationHandler {
            try await search.start()
        } onCancel: {
            Task { @MainActor in search.cancel() }
        }
        try Task.checkCancellation()
        var seen: Set<String> = []
        return response.mapItems.prefix(12).compactMap { item in
            let point = item.placemark.coordinate
            let name = item.name ?? "Selected place"
            let key = item.identifier?.rawValue ?? "\(name.lowercased())|\(point.latitude)|\(point.longitude)"
            guard seen.insert(key).inserted else { return nil }
            let id = identities[key] ?? UUID()
            identities[key] = id
            return RecommendedPlace(place: .init(id: id, name: name,
                                                 location: .init(latitude: point.latitude, longitude: point.longitude),
                                                 visitSeconds: 2700, website: item.url),
                                    address: item.placemark.title)
        }
    }
}

/// Apple search results remain in the current UI session and can also be viewed on Apple's map.
struct TripRecommendationsMap: View {
    let places: [RecommendedPlace]

    var body: some View {
        Map {
            ForEach(places) { item in
                Marker(item.place.name, coordinate: .init(latitude: item.place.location.latitude,
                                                          longitude: item.place.location.longitude))
            }
        }
        .accessibilityLabel("Recommended places on the map")
    }
}
