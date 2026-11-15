import Foundation

/// Answer to "How long are we hanging out at <place>?".
enum StayDuration: String, CaseIterable, ChoiceOption, Sendable {
    case thirtyMinutes
    case oneHour
    case ninetyMinutes
    case flexible

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .ninetyMinutes: "1 hr 30 mins"
        case .flexible: "Flexible"
        }
    }

    /// Visit length for planning; nil retains the draft duration required by the current contract.
    var visitSeconds: Int? {
        switch self {
        case .thirtyMinutes: 1800
        case .oneHour: 3600
        case .ninetyMinutes: 5400
        case .flexible: nil
        }
    }
}
