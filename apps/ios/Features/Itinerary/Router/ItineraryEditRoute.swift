import C67Domain

enum ItineraryEditRoute: Identifiable {
    /// Place pickers are full-screen pages; they show a map with their own bottom panel.
    var picksPlace: Bool {
        switch self {
        case .addPlace, .startingPoint, .endPoint: true
        case .visit, .tripTime, .estimatedDeparture: false
        }
    }

    case visit(PlanningPlace)
    case addPlace
    case startingPoint
    case endPoint
    case tripTime
    case estimatedDeparture

    var id: String {
        switch self {
        case .visit(let place): place.id.uuidString
        case .addPlace: "add-place"
        case .startingPoint: "starting-point"
        case .endPoint: "end-point"
        case .tripTime: "trip-time"
        case .estimatedDeparture: "estimated-departure"
        }
    }
}
