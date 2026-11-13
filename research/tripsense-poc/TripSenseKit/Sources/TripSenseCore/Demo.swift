import Foundation

public enum DemoFixture {
    public static let places: [Place] = [
        .init(id: "demo-museum", name: "DEMO Museum", coordinate: .init(-6.176, 106.822), category: "Museum", themes: [.history, .culture], provenance: "DEMO ONLY synthetic fixture"),
        .init(id: "demo-gallery", name: "DEMO Gallery", coordinate: .init(-6.178, 106.826), category: "Gallery", themes: [.culture], provenance: "DEMO ONLY synthetic fixture"),
        .init(id: "demo-garden", name: "DEMO Garden", coordinate: .init(-6.172, 106.829), category: "Park", themes: [.nature], provenance: "DEMO ONLY synthetic fixture"),
        .init(id: "demo-cafe", name: "DEMO Coffee", coordinate: .init(-6.179, 106.824), category: "Cafe", themes: [.food], provenance: "DEMO ONLY synthetic fixture")
    ]
    public static func recommendations(theme: Theme, count: Int) -> [Recommendation] {
        places.filter { theme == .mixed || $0.themes.contains(theme) }.prefix(count).map {
            Recommendation($0.id, reason: "DEMO ONLY: deterministic \($0.category.lowercased()) fixture")
        }
    }
}
@MainActor public struct FixtureRoutes: RouteProviding {
    public init() {}
    public func route(from: Place, to: Place, mode: TravelMode, departure: Date) async throws -> RouteLeg {
        // Deliberately fixed; no claim that this is a real route or measured ETA.
        RouteLeg(originID: from.id, destinationID: to.id, mode: mode, departure: departure,
                 distance: 600, travelTime: mode == .walking ? 600 : 180,
                 geometry: [], provenance: "DEMO ONLY fixed 600m route/ETA; no route geometry")
    }
}
