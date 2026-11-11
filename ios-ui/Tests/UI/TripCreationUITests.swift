import XCTest

final class TripCreationUITests: XCTestCase {
    @MainActor func testSpecificPlacesSelectionAndSheet() {
        let app = launch()
        app.buttons["homeAddTrip"].tap()
        app.buttons["Add Specific Place"].tap()
        XCTAssertTrue(app.textFields["addPlacesSearch"].waitForExistence(timeout: 5))
        app.textFields["addPlacesSearch"].tap()
        app.textFields["addPlacesSearch"].typeText("pizza\n")
        let add = app.buttons["Add Synthetic pizza place"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        app.buttons["addPlacesSelection"].tap()
        let remove = app.scrollViews["selectedPlacesList"].buttons["Remove Synthetic pizza place"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Add Synthetic pizza place"].waitForExistence(timeout: 5))
        capture(app, "ADD PLACES SEARCH")
    }

    @MainActor func testRecommendationFlowKeepsRequiredPlaces() {
        let app = launch()
        openMockCreation(app, recommendations: true)
        XCTAssertTrue(app.navigationBars["Recommendations"].waitForExistence(timeout: 10))
        app.buttons["Continue with my places"].tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 10))
        saveMockItinerary(app)
    }

    @MainActor func testSaveRenameRequiresSecondReviewAndArrivalKeepsTripActive() {
        let app = launch()
        reviewMockItinerary(app)
        let save = app.buttons["Save this trip"]
        scrollToTripControl(save, in: app)
        save.tap()
        let alert = app.alerts["Save Itinerary"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "Weekend plan")
        alert.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 10))
        scrollToTripControl(save, in: app)
        save.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertEqual(alert.textFields.firstMatch.value as? String, "Weekend plan")
        capture(app, "ITINERARY LIST SAVE")
        alert.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Weekend plan"].waitForExistence(timeout: 10))
        scrollToTripControl(save, in: app)
        save.tap()
        XCTAssertTrue(app.buttons["confirmTripArrival"].waitForExistence(timeout: 10))
        capture(app, "TRIP STARTED - mock status")
        app.buttons["confirmTripArrival"].tap()
        XCTAssertTrue(app.staticTexts["You’ve arrived"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["completeTripVisit"].exists)
        XCTAssertFalse(app.staticTexts["Trip completed"].exists)
        capture(app, "TRIP DONE - first arrival")
        app.buttons["completeTripVisit"].tap()
        XCTAssertTrue(app.buttons["confirmTripArrival"].waitForExistence(timeout: 10))
    }

    @MainActor func testSpecificFlowAtAccessibilityTextSize() {
        let app = launch(large: true)
        reviewMockItinerary(app)
        capture(app, "ITINERARY - accessibility XXXL")
        scrollToTripControl(app.buttons["Save this trip"], in: app)
        XCTAssertTrue(app.buttons["Save this trip"].isHittable)
    }

    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
