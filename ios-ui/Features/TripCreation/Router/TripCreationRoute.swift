import Foundation

enum TripCreationRoute: Hashable {
    case availability
    case question(PreferenceStep)
    case places
    case recommendations
    case mainSpot
    case stay
    case review
}
