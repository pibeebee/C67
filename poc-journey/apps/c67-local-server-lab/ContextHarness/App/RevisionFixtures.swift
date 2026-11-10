import Foundation
import DynamicTripContracts
import PlaceContextEngine

@MainActor enum RevisionFixtures {
    static func prepared(_ id: String) throws -> DynamicPreparedPlace { try ItineraryRevisionReplay.prepared(id) }
    static func initial() async throws -> LocalItineraryRevision { try await ItineraryRevisionReplay.initial() }
    static func preview(_ input: ItineraryRevisionInput) async throws -> ItineraryRevisionPreview {
        try await Task.sleep(for: .milliseconds(150))
        return try await ItineraryRevisionReplay.preview(input)
    }
    static func search(_ query: String) -> [GooglePlace] {
        ItineraryRevisionReplay.ids.compactMap { id in
            guard let prepared = try? prepared(id), let data = try? JSONSerialization.data(withJSONObject: ["id": id, "displayName": ["text": prepared.name]]) else { return nil }
            return try? JSONDecoder().decode(GooglePlace.self, from: data)
        }
    }
}
