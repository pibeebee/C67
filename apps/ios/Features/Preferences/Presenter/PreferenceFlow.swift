import Foundation

/// Navigation and answer state for the Q1–Q7 preference questions.
struct PreferenceFlow: Equatable, Sendable {
    var answers = PreferenceAnswers()
    var path: [PreferenceStep] = []
    private(set) var isFinished = false

    /// The question on top of the navigation stack.
    var currentStep: PreferenceStep { path.last ?? .interests }

    /// Moves past `step`.
    ///
    /// Ignores calls for a question that is no longer on top, so a repeated tap cannot push twice.
    /// Returns the answers once, after the last question.
    @discardableResult
    mutating func advance(from step: PreferenceStep) -> PreferenceAnswers? {
        guard !isFinished, step == currentStep else { return nil }
        guard let next = step.next else {
            isFinished = true
            return answers
        }
        path.append(next)
        return nil
    }

    /// Clears the question's answer, then moves past it.
    @discardableResult
    mutating func skip(_ step: PreferenceStep) -> PreferenceAnswers? {
        guard !isFinished, step == currentStep else { return nil }
        answers.clear(step)
        return advance(from: step)
    }
}
