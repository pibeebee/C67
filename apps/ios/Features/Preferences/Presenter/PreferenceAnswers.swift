import Foundation

/// The traveller's answers to the trip preference questions. `nil` means skipped or unanswered.
struct PreferenceAnswers: Equatable, Sendable {
    var interests: Set<TripInterest> = []
    var refinements: Set<String> = []
    var popularity: PlacePopularityPreference?
    var pace: ExplorationPace?
    var timing: TripTiming?
    var dayPart: DayPart?
    var budget: Double?
    var transport: TransportMode?

    /// Q1 continues only after at least one interest is chosen.
    var canContinueFromInterests: Bool { !interests.isEmpty }

    mutating func toggle(_ interest: TripInterest) {
        if interests.contains(interest) {
            interests.remove(interest)
        } else {
            interests.insert(interest)
        }
    }

    /// Removes the answer for a skipped question.
    mutating func clear(_ step: PreferenceStep) {
        switch step {
        case .interests: interests = []; refinements = []
        case .popularity: popularity = nil
        case .pace: pace = nil
        case .timing: timing = nil
        case .dayPart: dayPart = nil
        case .budget: budget = nil
        case .transport: transport = nil
        }
    }
}
