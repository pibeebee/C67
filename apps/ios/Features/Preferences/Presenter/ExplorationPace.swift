import Foundation

/// Q3 "How much exploring are we up for?" — how many stops to plan.
enum ExplorationPace: String, CaseIterable, ChoiceOption, Sendable {
    case easy
    case moderate
    case packed
    case more

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .easy: "Nice and easy (3 stops)"
        case .moderate: "A little exploring (4 stops)"
        case .packed: "Wanna see a lot (5 stops)"
        case .more: "I’m up for more"
        }
    }
}
