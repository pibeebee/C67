import Foundation

/// UI themes are groups over the existing taxonomy, not new venue labels.
public enum PreferenceTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case foodie, nature, photoSpot, culture, lifestyle, art, entertainment
    public var id: String { "theme." + rawValue }
    public var title: String {
        switch self {
        case .foodie: "Foodie"
        case .nature: "Nature"
        case .photoSpot: "Photo Spot"
        case .culture: "Culture"
        case .lifestyle: "Lifestyle"
        case .art: "Art"
        case .entertainment: "Entertainment"
        }
    }
    public var categories: Set<String> {
        switch self {
        case .foodie: ["cafe", "restaurant", "bakery", "dessert_shop", "tea_house", "food_court", "street_food_area", "specialty_coffee", "brunch_cafe", "dessert_cafe", "indonesian_cuisine", "japanese_cuisine", "korean_cuisine"]
        case .nature: ["park", "botanical_garden", "urban_forest", "public_square", "waterfront_walk"]
        case .photoSpot: []
        case .culture: ["museum", "cultural_center", "heritage_site", "history_museum", "science_museum"]
        case .lifestyle: ["library", "book_store", "coworking_space", "shopping_mall", "traditional_market", "thrift_shop", "record_store", "craft_shop", "used_books", "comics", "childrens_books"]
        case .art: ["art_gallery", "art_museum", "creative_studio", "workshop_venue", "performance_venue"]
        case .entertainment: ["cinema", "performance_venue", "live_music_venue", "karaoke", "sports_center", "swimming_pool", "climbing_gym", "bowling_alley", "arcade", "playground", "cycling_track"]
        }
    }
    public var features: Set<Facet> {
        switch self {
        case .nature: [.nature]
        case .photoSpot: [.architecture, .city_view, .public_art]
        case .culture: [.heritage]
        case .art: [.public_art]
        default: []
        }
    }
    public var query: String {
        switch self {
        case .foodie: "restaurants cafes"
        case .nature: "parks gardens"
        case .photoSpot: "landmarks architecture"
        case .culture: "museums cultural centers"
        case .lifestyle: "bookstores shopping"
        case .art: "art galleries museums"
        case .entertainment: "cinema recreation"
        }
    }
    public static func from(interest: String) -> Self? {
        allCases.first { $0.id == interest }
    }
}

extension Profile {
    /// One representative per theme; refinements narrow that theme instead of broadening it by OR.
    public var interests: Set<String> {
        let grouped = Set(themes.flatMap(\.categories))
        return Set(themes.map(\.id)).union(categories.map(Interests.canonical).filter { !grouped.contains($0) })
    }
    public func matches(_ interest: String, venue: Venue, at date: Date) -> Bool {
        guard let theme = PreferenceTheme.from(interest: interest) else {
            return Interests.matches(interest, categories: venue.effectiveCategories(at: date))
        }
        let refined = Set(categories.map(Interests.canonical)).intersection(theme.categories)
        let labels = refined.isEmpty ? theme.categories : refined
        if labels.contains(where: { Interests.matches($0, categories: venue.effectiveCategories(at: date)) }) { return true }
        return refined.isEmpty && theme.features.contains { venue.status($0, at: date) == .supported }
    }
    public func query(for interest: String) -> String {
        guard let theme = PreferenceTheme.from(interest: interest) else { return Interests.query(interest) }
        let refined = Set(categories.map(Interests.canonical)).intersection(theme.categories).sorted()
        return refined.isEmpty ? theme.query : refined.map(Interests.query).joined(separator: " ")
    }
}
