import Foundation

/// The messages shown while the itinerary is being built (Sketch HI-FI `PREFERENCES PROCESSING 2–4`).
///
/// They describe the work in order; they are not measured progress, so the screen pairs them
/// with an indeterminate spinner and stays on the last message until the plan is ready.
enum TripProcessingStage: Int, CaseIterable, Sendable {
    case puttingTogether
    case checkingWeather
    case scanningTraffic

    /// How long each message stays before the next one.
    static let interval: Duration = .seconds(1.8)

    /// The following message, or nil on the last one.
    var next: TripProcessingStage? { TripProcessingStage(rawValue: rawValue + 1) }
}
