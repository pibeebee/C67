import C67Domain

enum ItineraryEditRoute: Identifiable {
    case visit(PlanningPlace)
    case addPlace

    var id: String {
        switch self {
        case .visit(let place): place.id.uuidString
        case .addPlace: "add-place"
        }
    }
}
