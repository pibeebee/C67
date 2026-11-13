import Foundation

/// Q4 "When are we doing this?" — when the trip should start.
enum TripTiming: String, CaseIterable, ChoiceOption, Sendable {
    case now
    case tomorrow
    case inAFewDays
    case bestDay

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .now: "Let’s go right now"
        case .tomorrow: "Fresh start tomorrow"
        case .inAFewDays: "In 2–3 days"
        case .bestDay: "Find the best day automatically"
        }
    }
}
