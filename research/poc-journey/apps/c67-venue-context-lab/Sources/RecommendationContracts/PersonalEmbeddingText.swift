import Foundation

/// Controlled English input for the personal flow's on-device E5 helper.
/// Display names, addresses and arbitrary provider prose are never translated or embedded here.
/// E5Embedding adds query:/passage: itself. Bump the version when this representation changes.
public enum PersonalEmbeddingText {
    public static let version = "en-v1"
    private static let interests: [PersonalInterest: String] = [
        .coffee: "coffee and cafes", .reading: "books and reading", .food: "food and dining",
        .outdoors: "parks and outdoor activities", .culture: "history and culture",
        .shopping: "shopping", .entertainment: "entertainment",
        .architecture: "architecture and historic buildings", .arts: "art and creative activities"
    ]
    // These are sourced provider type identifiers, not claims about finer venue characteristics.
    private static let providerTypes: Set<String> = [
        "cafe", "coffee_shop", "library", "book_store", "restaurant", "food", "bakery",
        "meal_takeaway", "indonesian_restaurant", "park", "national_park", "botanical_garden",
        "garden", "zoo", "museum", "historical_landmark", "cultural_center", "historical_place",
        "shopping_mall", "market", "department_store", "amusement_park", "movie_theater",
        "aquarium", "tourist_attraction", "cultural_landmark", "art_gallery", "art_studio",
        "art_museum", "performing_arts_theater"
    ]
    private static func labels(_ values: [PersonalInterest]) -> [String] {
        PersonalInterest.allCases.filter { values.contains($0) }.compactMap { interests[$0] }
    }
    public static func query(profile: PersonalProfile) -> String {
        let chosen = labels(profile.interests)
        return chosen.isEmpty ? "Find places for general exploration."
            : "Find places matching these interests: " + chosen.joined(separator: "; ") + "."
    }
    public static func passage(candidate: PersonalCandidate) -> String {
        let types = Set(candidate.facetKeys.compactMap { key -> String? in
            let parts = key.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let category = PersonalInterest(rawValue: String(parts[0])),
                  candidate.categories.contains(category), providerTypes.contains(String(parts[1])) else { return nil }
            return String(parts[1]).replacingOccurrences(of: "_", with: " ")
        }).sorted()
        let categories = labels(candidate.categories)
        return "Provider categories: " + (types.isEmpty ? "not provided" : types.joined(separator: "; "))
            + ". Broad interests supported by category data: "
            + (categories.isEmpty ? "not provided" : categories.joined(separator: "; "))
            + ". Other venue characteristics are unknown."
    }
}
