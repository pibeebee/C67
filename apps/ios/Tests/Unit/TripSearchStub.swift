import Foundation
import C67Domain
@testable import C67

@MainActor final class TripSearchStub: TripPlaceSearching {
    var started = false
    var failing = false
    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        started = true
        if query == "old" { try? await Task.sleep(for: .milliseconds(80)) }
        if failing { throw PlanningError.unavailable }
        return [.init(place: .init(id: UUID(), name: query, location: .init(latitude: 0, longitude: 0), visitSeconds: 1800))]
    }
}
