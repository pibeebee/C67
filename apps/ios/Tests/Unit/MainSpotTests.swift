import Foundation
import SwiftUI
import Testing
import UIKit
@testable import C67

@Suite("Main spot and stay length match Sketch HI-FI")
struct MainSpotTests {
    @Test("Only a chosen place asks how long to stay")
    func stayQuestionFollowsChoice() {
        let id = UUID()
        #expect(MainSpotChoice.automatic.placeID == nil)
        #expect(!MainSpotChoice.automatic.asksForStay)
        #expect(MainSpotChoice.place(id).placeID == id)
        #expect(MainSpotChoice.place(id).asksForStay)
    }

    @Test("Stay options use the Sketch copy, in order")
    func stayCopy() {
        #expect(StayDuration.allCases.map { String(localized: $0.title) } == [
            "30 minutes", "1 hour", "1 hr 30 mins", "Flexible",
        ])
    }

    @Test("Stay options map to visit lengths; Flexible lets the planner decide", arguments: [
        (StayDuration.thirtyMinutes, 1800), (.oneHour, 3600), (.ninetyMinutes, 5400),
    ])
    func staySeconds(duration: StayDuration, seconds: Int) {
        #expect(duration.visitSeconds == seconds)
    }

    @Test("Flexible has no fixed length")
    func flexibleStay() {
        #expect(StayDuration.flexible.visitSeconds == nil)
    }

    @MainActor
    @Test("Picking a place moves the checkmark away from Let Travelant decide")
    func checkmarkFollowsSelection() throws {
        func png(_ isSelected: Bool) throws -> Data {
            let renderer = ImageRenderer(
                content: CheckmarkRow(title: Text("Let Travelant decide"), isSelected: isSelected, action: {})
                    .frame(width: 340)
            )
            renderer.scale = 1
            return try #require(renderer.uiImage?.pngData())
        }
        #expect(try png(true) != png(false))
    }
}
