import Foundation
import C67Domain

/// Explicit mock-only search. No Sketch sample venue is injected into app data.
@MainActor final class SyntheticTripPlaceSearch: TripPlaceSearching {
    private let ids = [UUID(), UUID(), UUID()]
    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        try Task.checkCancellation()
        let origin = origin ?? .init(latitude: -6.19, longitude: 106.84)
        return ["Synthetic coffee shop", "Synthetic museum", "Synthetic pizza place"].enumerated().map { index, name in
            RecommendedPlace(place: .init(id: ids[index], name: name,
                                          location: .init(latitude: origin.latitude + Double(index + 1) * 0.001,
                                                          longitude: origin.longitude), visitSeconds: 2700))
        }
    }
}
