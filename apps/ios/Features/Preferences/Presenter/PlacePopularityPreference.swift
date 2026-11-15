import Foundation

/// Answer to "Popular spots or hidden gems?" in the trip preference questions.
enum PlacePopularityPreference: String, CaseIterable, ChoiceOption, Sendable {
    case mustSees
    case hiddenGems
    case both
    case surprise

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .mustSees: "The must-sees"
        case .hiddenGems: "Hidden Gems & Local Favorites"
        case .both: "A bit of Both"
        case .surprise: "Surprise me"
        }
    }
}
