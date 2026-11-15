import C67Domain

/// Typed destinations keep navigation separate from repository calls.
enum DiscoveryRoute: Hashable {
    case rundown(Rundown)
}
