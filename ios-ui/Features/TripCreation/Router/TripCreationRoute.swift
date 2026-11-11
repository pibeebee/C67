import Foundation

enum TripCreationRoute: Hashable {
    case question(PreferenceStep)
    case places
    case confirmation
    case recommendations
    case mainSpot
    case stay
    case review
}
