import C67Domain

enum ItineraryEditRoute: Identifiable {
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
