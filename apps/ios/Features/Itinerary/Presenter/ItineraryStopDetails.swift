import Foundation

/// Optional presentation metadata; never inferred from a place name or coordinates.
struct ItineraryStopDetails {
    var category: String?
    var photoAsset: String?
    var weatherAdvice: String?
    var weatherSymbol = "cloud.sun"
    var distance: String?
}
