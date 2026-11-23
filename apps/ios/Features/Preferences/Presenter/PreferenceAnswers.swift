import Foundation

/// The traveller's answers to the trip preference questions. `nil` means skipped or unanswered.
struct PreferenceAnswers: Equatable, Sendable {
    static let maximumInterestSelections = 5

    var interests: Set<TripInterest> = []
    var refinements: Set<String> = []
    var popularity: PlacePopularityPreference?
    var pace: ExplorationPace?
    var timing: TripTiming?
    var dayPart: DayPart?
    var budget: Double?
    var transport: TransportMode?

    /// Q1 can continue with a theme, a detailed preference, or both.
    var canContinueFromInterests: Bool { !interests.isEmpty || !refinements.isEmpty }
    var interestSelectionCount: Int { interests.count + refinements.count }
    var canAddInterestSelection: Bool {
        interestSelectionCount < Self.maximumInterestSelections
    }

    mutating func toggle(_ interest: TripInterest) {
        if interests.contains(interest) {
            interests.remove(interest)
        } else if canAddInterestSelection {
            interests.insert(interest)
        }
    }

    mutating func toggleRefinement(_ refinement: String) {
        if refinements.contains(refinement) {
            refinements.remove(refinement)
        } else if canAddInterestSelection {
            refinements.insert(refinement)
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
