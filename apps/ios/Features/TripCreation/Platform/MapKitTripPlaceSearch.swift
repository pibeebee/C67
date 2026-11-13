import Foundation
@preconcurrency import MapKit
import C67Domain

@MainActor final class MapKitTripPlaceSearch: TripPlaceSearching {
    private var identities: [String: UUID] = [:]

    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let origin {
            request.region = .init(center: .init(latitude: origin.latitude, longitude: origin.longitude),
                                   latitudinalMeters: 20_000, longitudinalMeters: 20_000)
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
            let key = "\(name.lowercased())|\(point.latitude)|\(point.longitude)"
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
