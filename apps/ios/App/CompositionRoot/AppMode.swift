import Foundation

/// Which audience this build is for, set per build configuration through `C67_APP_MODE`:
/// Debug is `developer`, Staging is `staging` (TestFlight before release), Release is `production`.
/// Debug builds also accept a `-C67_APP_MODE <mode>` launch argument, which the C67 Staging scheme uses.
enum AppMode: String, Sendable {
    case developer
    case staging
    case production

    static let current: AppMode = {
        #if DEBUG
            // The C67 Staging scheme runs a Debug build (so previews work) with `-C67_APP_MODE staging`.
            if let override = UserDefaults.standard.string(forKey: "C67_APP_MODE").flatMap(AppMode.init(rawValue:)) {
                return override
            }
        #endif
        let value = Bundle.main.object(forInfoDictionaryKey: "C67_APP_MODE") as? String
        return value.flatMap(AppMode.init(rawValue:)) ?? .production
    }()

    /// Planner diagnostics on the itinerary — "Before you go", opening hours, trip details and the
    /// return leg — are for developers only; staging and production builds hide them.
    var showsPlanningDiagnostics: Bool { self == .developer }
}
