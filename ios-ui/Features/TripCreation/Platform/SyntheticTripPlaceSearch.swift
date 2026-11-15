import Foundation
import C67Domain
#if DEBUG
    import C67Data
#endif

/// Explicit mock-only search. No Sketch sample venue is injected into app data.
@MainActor final class SyntheticTripPlaceSearch: TripPlaceSearching {
    private let ids = [UUID(), UUID(), UUID()]
    private var recommendationIDs: [String: [UUID]] = [:]

    func recommendations(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        try Task.checkCancellation()
        let origin = origin.flatMap { TripDiscoveryArea.contains($0) ? $0 : nil } ?? TripDiscoveryArea.center
        let ids = recommendationIDs[query] ?? (0 ..< 12).map { _ in UUID() }
        recommendationIDs[query] = ids
        return ids.enumerated().map { index, id in
            RecommendedPlace(place: .init(id: id, name: "Synthetic \(query) \(index + 1)",
                                          location: .init(latitude: origin.latitude + Double(index + 1) * 0.001,
                                                          longitude: origin.longitude), visitSeconds: 2700),
                             category: "Synthetic place")
        }
    }

    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        try Task.checkCancellation()
        let origin = origin.flatMap { TripDiscoveryArea.contains($0) ? $0 : nil } ?? TripDiscoveryArea.center
        return ["Synthetic coffee shop", "Synthetic museum", "Synthetic pizza place"].enumerated().map { index, name in
            RecommendedPlace(place: .init(id: ids[index], name: name,
                                          location: .init(latitude: origin.latitude + Double(index + 1) * 0.001,
                                                          longitude: origin.longitude), visitSeconds: 2700))
        }
    }
}

#if DEBUG
    @MainActor final class PocketFixtureTripPlaceSearch: TripPlaceSearching {
        func recommendations(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
            try Task.checkCancellation()
            return try PocketIntegrationFixture.searchablePlaces().map {
                RecommendedPlace(place: $0, category: "Synthetic fixture")
            }
        }

        func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
            try await recommendations(query, near: origin).filter { $0.place.name.localizedCaseInsensitiveContains(query) }
        }
    }
#endif
