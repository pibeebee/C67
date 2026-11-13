enum TripHomeSheet: String, Identifiable {
    case planning
    case specificPlace
    case location
    case account

    var id: String { rawValue }
}
