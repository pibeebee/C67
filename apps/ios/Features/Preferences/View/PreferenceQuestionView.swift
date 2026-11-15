import SwiftUI
import C67Domain

/// Shows the screen for one preference question and reports answers to the flow.
struct PreferenceQuestionView: View {
    let step: PreferenceStep
    let answers: PreferenceAnswers
    let update: (PreferenceAnswers) -> Void
    let advance: () -> Void
    let skip: () -> Void
    var refinementOptions: [PlanningPreferenceLabel] = []

    var body: some View {
        switch step {
        case .interests:
            TripInterestQuestionView(
                selection: answers.interests,
                toggle: { interest in edit { $0.toggle(interest) } },
                next: advance,
                skip: skip,
                supportedRefinements: refinementOptions,
                selectedRefinements: answers.refinements,
                toggleRefinement: { value in edit { $0.refinements.formSymmetricDifference([value]) } }
            )
        case .popularity:
            PlacePopularityQuestionView(
                selection: answers.popularity,
                select: { value in answer { $0.popularity = value } },
                skip: skip
            )
        case .pace:
            ExplorationPaceQuestionView(
                selection: answers.pace,
                select: { value in answer { $0.pace = value } },
                skip: skip
            )
        case .timing:
            TripTimingQuestionView(
                selection: answers.timing,
                select: { value in answer { $0.timing = value } },
                skip: skip
            )
        case .dayPart:
            DayPartQuestionView(
                selection: answers.dayPart,
                select: { value in answer { $0.dayPart = value } },
                skip: skip
            )
        case .budget:
            BudgetQuestionView(
                initialBudget: answers.budget,
                next: { value in answer { $0.budget = value } },
                skip: skip
            )
        case .transport:
            TransportModeQuestionView(
                selection: answers.transport,
                select: { value in answer { $0.transport = value } },
                skip: skip
            )
        }
    }

    private func edit(_ change: (inout PreferenceAnswers) -> Void) {
        var updated = answers
        change(&updated)
        update(updated)
    }

    private func answer(_ change: (inout PreferenceAnswers) -> Void) {
        edit(change)
        advance()
    }
}
