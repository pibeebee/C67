import Foundation
import Testing
@testable import C67

@Suite("Preference answers")
struct PreferenceAnswersTests {
    @Test("Q1 Next is disabled until an interest is chosen")
    func interestsGateNext() {
        var answers = PreferenceAnswers()
        #expect(!answers.canContinueFromInterests)

        answers.toggle(.foodie)
        answers.toggle(.culture)
        #expect(answers.interests == [.foodie, .culture])
        #expect(answers.canContinueFromInterests)

        answers.toggle(.foodie)
        answers.toggle(.culture)
        #expect(!answers.canContinueFromInterests)
    }

    @Test("Clearing a step removes only that answer", arguments: PreferenceStep.allCases)
    func clearRemovesOnlyThatAnswer(step: PreferenceStep) {
        var answers = PreferenceAnswers.everythingAnswered
        answers.clear(step)

        var expected = PreferenceAnswers.everythingAnswered
        switch step {
        case .interests: expected.interests = []
        case .popularity: expected.popularity = nil
        case .pace: expected.pace = nil
        case .timing: expected.timing = nil
        case .dayPart: expected.dayPart = nil
        case .budget: expected.budget = nil
        case .transport: expected.transport = nil
        }
        #expect(answers == expected)
    }

    @Test("Budget values snap to the slider range and steps", arguments: [
        (0.0, 50_000.0),
        (50_000.0, 50_000.0),
        (74_000.0, 50_000.0),
        (76_000.0, 100_000.0),
        (500_000.0, 500_000.0),
        (9_000_000.0, 500_000.0),
    ])
    func budgetNormalization(input: Double, expected: Double) {
        #expect(BudgetScale.normalized(input) == expected)
    }

    @Test("Budget shows rupiah in the Indonesian format from Sketch")
    func budgetFormatsAsRupiah() {
        let text = BudgetScale.currency.locale(Locale(identifier: "id_ID")).format(50_000)
        #expect(text.contains("Rp"))
        #expect(text.contains("50.000"))
    }
}

extension PreferenceAnswers {
    static let everythingAnswered = PreferenceAnswers(
        interests: [.nature, .art],
        popularity: .hiddenGems,
        pace: .moderate,
        timing: .tomorrow,
        dayPart: .morning,
        budget: 150_000,
        transport: .publicTransport
    )
}
