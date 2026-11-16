import Foundation
import C67Domain
@testable import C67

@MainActor final class TripSearchStub: TripPlaceSearching {
    var started = false
    var failing = false
    var failedQueries: Set<String> = []
    var queries: [String] = []
    var delay: Duration?
    var placesByQuery: [String: [RecommendedPlace]] = [:]
    private var defaultIDs: [String: UUID] = [:]
    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        started = true
        queries.append(query)
        if let delay { try? await Task.sleep(for: delay) }
        if query == "old" { try? await Task.sleep(for: .milliseconds(80)) }
        if failing || failedQueries.contains(query) { throw PlanningError.unavailable }
        if let places = placesByQuery[query] { return places }
        let id = defaultIDs[query] ?? UUID()
        defaultIDs[query] = id
        return [.init(place: .init(id: id, name: query, location: TripDiscoveryArea.center, visitSeconds: 1800))]
    }
}
