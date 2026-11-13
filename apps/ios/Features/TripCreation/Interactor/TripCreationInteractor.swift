import Foundation
import C67Domain

@MainActor protocol TripPlaceSearching {
    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace]
}

@MainActor struct TripCreationInteractor {
    let searcher: any TripPlaceSearching

    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        try await searcher.search(query, near: origin)
    }
}
