enum TripHomeSheet: String, Identifiable {
    case location
    case account

    var id: String { rawValue }

    /// The place picker is a full-screen page; it shows a map with its own bottom panel.
    var isFullScreen: Bool { self == .location }
}
