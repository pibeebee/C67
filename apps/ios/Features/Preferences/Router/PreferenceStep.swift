import Foundation

/// The trip preference questions, in Sketch HI-FI order (Q1–Q7).
enum PreferenceStep: Int, CaseIterable, Hashable, Sendable {
    case interests = 1
    case popularity
    case pace
    case timing
    case dayPart
    case budget
    case transport

    /// The following question, or `nil` after the last one.
    var next: PreferenceStep? { PreferenceStep(rawValue: rawValue + 1) }
}
