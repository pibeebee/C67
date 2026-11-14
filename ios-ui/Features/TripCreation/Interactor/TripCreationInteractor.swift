import Foundation
import C67Domain

@MainActor protocol TripPlaceSearching {
    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace]
    func recommendations(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace]
}

extension PreferenceAnswers {
    /// Temporary deterministic search vocabulary. E5 matching is a separate integration.
    /// These terms express wishes; a search match does not verify facilities or access.
    var discoveryQueries: [String] {
        let overrides = [
            "visual_art": "art gallery", "contemporary_museum": "contemporary art museum",
            "history": "history museum", "maritime_culture": "maritime museum",
            "transportation_focus": "transport museum", "science": "science museum",
            "textiles": "textile museum", "wayang": "wayang museum", "ceramics": "ceramic gallery",
            "photography_focus": "photography gallery", "architecture": "historic architecture",
            "astronomy": "planetarium", "rare_collections": "museum",
            "picnic": "picnic park", "jogging": "jogging park", "walking": "walking park",
            "photography_activity": "scenic viewpoint", "sunset_viewing": "sunset viewpoint",
            "camping": "campground", "fishing": "fishing pond", "surfing": "surfing beach",
            "live_music_activity": "live music venue", "reading": "library",
            "working": "coworking cafe", "board_games": "board game cafe",
            "drink_tasting": "coffee tasting", "baseball": "baseball field",
            "basketball": "basketball court", "futsal": "futsal court",
            "mini_soccer": "mini soccer field", "tennis": "tennis court",
            "volleyball": "volleyball court", "beach_volleyball": "beach volleyball court",
        ]
        func term(_ option: TripPreferenceCatalog.Option) -> String {
            if let override = overrides[option.id] { return override }
            var resource = option.title
            resource.locale = Locale(identifier: "en")
            return String(localized: resource).replacingOccurrences(of: " cuisine", with: " restaurant")
        }
        let settingsGroup = "setting-facilities-and-access"
        let focused = TripPreferenceCatalog.groups.filter { $0.id != settingsGroup }
            .flatMap(\.options).filter { refinements.contains($0.id) }.map(term)
        let themed = TripInterest.allCases.filter { interests.contains($0) }.flatMap { interest -> [String] in
            switch interest {
            case .foodie: ["restaurant", "cafe"]
            case .nature: ["park", "botanical garden"]
            case .photoSpot: ["scenic viewpoint", "historic architecture"]
            case .culture: ["museum", "historic site"]
            case .lifestyle: ["bookstore", "shopping mall"]
            case .art: ["art gallery", "art museum"]
            case .entertainment: ["cinema", "amusement park"]
            }
        }
        let base = focused.isEmpty ? (themed.isEmpty ? ["tourist attraction", "cafe", "park"] : themed) : focused
        let settings = TripPreferenceCatalog.groups.first { $0.id == settingsGroup }?.options
            .filter { refinements.contains($0.id) }.map(term) ?? []
        // Offer each setting separately rather than inventing every combination of preferences.
        let variants = settings.enumerated().map { index, setting in "\(setting) \(base[index % base.count])" }
        var seen: Set<String> = []
        return (base + variants + themed).filter { seen.insert($0.lowercased()).inserted }
    }
}

extension TripPlaceSearching {
    func recommendations(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        try await search(query, near: origin)
    }
}

@MainActor struct TripCreationInteractor {
    let searcher: any TripPlaceSearching

    func search(_ query: String, near origin: PlanningPoint?) async throws -> [RecommendedPlace] {
        try await searcher.search(query, near: origin)
    }

    /// A small session search, independent of trip dates, the catalog and itinerary planning.
    func recommend(queries: [String], near origin: PlanningPoint?, synthetic: Bool) async throws -> RecommendationsBatch {
        var groups: [[RecommendedPlace]] = []
        var warnings: [String] = []
        var lastError: (any Error)?
        for query in queries {
            try Task.checkCancellation()
            do {
                let found = try await searcher.recommendations(query, near: origin)
                groups.append(found)
                if found.isEmpty { warnings.append("No results for \"\(query)\". Try another preference or refresh.") }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                lastError = error
                warnings.append("Search for \"\(query)\" is unavailable. Refresh to try again.")
            }
        }
        try Task.checkCancellation()
        if groups.isEmpty, let lastError { throw lastError }
        // Interleave query groups so a broad query does not occupy the entire first screen.
        var places: [RecommendedPlace] = []
        var seen: Set<UUID> = []
        for index in 0 ..< (groups.map(\.count).max() ?? 0) {
            for group in groups where index < group.count {
                let item = group[index]
                if seen.insert(item.id).inserted { places.append(item) }
            }
        }
        return .init(places: places, warnings: warnings, synthetic: synthetic)
    }
}
