import Foundation
import Testing
import UIKit
@testable import C67

@Suite("Preference options match Sketch HI-FI")
struct PreferenceOptionCatalogTests {
    @Test("Q1 interests")
    func interests() {
        #expect(TripInterest.allCases.map(\.titleText) == [
            "Foodie", "Nature", "Photo Spot", "Culture", "Lifestyle", "Art", "Entertainment",
        ])
    }

    @Test("Q1 interest symbols exist in SF Symbols", arguments: TripInterest.allCases)
    func interestSymbolExists(interest: TripInterest) {
        #expect(UIImage(systemName: interest.systemImage) != nil)
    }

    @Test("Q2 popularity")
    func popularity() {
        #expect(PlacePopularityPreference.allCases.map(\.titleText) == [
            "The must-sees", "Hidden Gems & Local Favorites", "A bit of Both", "Surprise me",
        ])
    }

    @Test("Q3 exploration pace")
    func pace() {
        #expect(ExplorationPace.allCases.map(\.titleText) == [
            "Nice and easy (3 stops)", "A little exploring (4 stops)", "Wanna see a lot (5 stops)",
            "I’m up for more",
        ])
    }

    @Test("Q4 timing")
    func timing() {
        #expect(TripTiming.allCases.map(\.titleText) == [
            "Let’s go right now", "Fresh start tomorrow", "In 2–3 days", "Find the best day automatically",
        ])
    }

    @Test("Q5 part of day")
    func dayPart() {
        #expect(DayPart.allCases.map(\.titleText) == [
            "Morning (06:00 - 11:00)", "Afternoon (11:00 - 15:00)", "Evening (15:00 - 18:00)",
            "Night (18:00 - 22:00)",
        ])
    }

    @Test("Q7 transport")
    func transport() {
        #expect(TransportMode.allCases.map(\.titleText) == [
            "Public Transportation", "Private Car", "Motorcycle", "Whatever works",
        ])
    }
}

private extension TripInterest {
    var titleText: String { String(localized: title) }
}

private extension ChoiceOption {
    var titleText: String { String(localized: title) }
}
