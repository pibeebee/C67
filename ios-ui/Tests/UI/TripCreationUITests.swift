import XCTest

final class TripCreationUITests: XCTestCase {
    @MainActor func testDraggingStopRecalculatesAndPreservesOrder() {
        let app = launch()
        reviewMockItinerary(app)
        let first = app.staticTexts["Synthetic stop 1"]
        let second = app.staticTexts["Synthetic stop 2"]
        let handles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "itineraryReorder-"))
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let source = handles.element(boundBy: 0)
        let target = handles.element(boundBy: 1)
        XCTAssertTrue(source.isHittable)
        XCTAssertTrue(target.isHittable)
        print("REORDER_DIAGNOSTIC source=\(source.frame) target=\(target.frame) screen=\(app.frame)")
        // Drop on the destination card rather than its own drag handle.
        let destination = target.coordinate(withNormalizedOffset: CGVector(dx: -2, dy: 0.5))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: destination)
        let reordered = NSPredicate { _, _ in second.exists && first.exists && second.frame.midY < first.frame.midY }
        expectation(for: reordered, evaluatedWith: nil)
        waitForExpectations(timeout: 20)
        XCTAssertTrue(app.buttons["Save this trip"].exists)
        capture(app, "ITINERARY - reordered")
        saveMockItinerary(app)
        XCTAssertTrue(app.staticTexts["Synthetic stop 1"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic stop 2"].exists)
        XCTAssertLessThan(app.staticTexts["Synthetic stop 2"].frame.midY, app.staticTexts["Synthetic stop 1"].frame.midY)
    }

    @MainActor func testReviewNavigationSeparatesBackAndCancel() {
        let app = launch()
        reviewMockItinerary(app)
        let bar = app.navigationBars["Itinerary"]
        let back = bar.buttons.element(boundBy: 0)
        let cancel = bar.buttons["tripCreationCancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        XCTAssertTrue(cancel.isHittable)
        XCTAssertLessThan(back.frame.midX, bar.frame.midX)
        XCTAssertGreaterThan(cancel.frame.midX, bar.frame.midX)
        capture(app, "ITINERARY - navigation")
        back.tap()
        XCTAssertFalse(app.navigationBars["Itinerary"].exists)
        app.buttons["tripCreationCancel"].tap()
        XCTAssertTrue(app.staticTexts["homeEmptyState"].waitForExistence(timeout: 5))
    }

    @MainActor func testConfirmationContinueIsProminentAndOpensNextStep() {
        let app = launch()
        openTripMenu(app)
        app.buttons["Add Specific Place"].tap()
        XCTAssertTrue(app.buttons["addPlacesNext"].waitForExistence(timeout: 5))
        app.buttons["addPlacesNext"].tap()
        let button = app.buttons["confirmTripInput"]
        scrollToTripControl(button, in: app)
        XCTAssertTrue(button.isEnabled)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        XCTAssertGreaterThan(button.frame.width, app.frame.width * 0.6)
        capture(app, "CONFIRM TRIP - Continue")
        button.tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
    }

    @MainActor func testSpecificPlacesSelectionAndSheet() {
        let app = launch()
        openTripMenu(app)
        app.buttons["Add Specific Place"].tap()
        XCTAssertTrue(app.textFields["addPlacesSearch"].waitForExistence(timeout: 5))
        app.textFields["addPlacesSearch"].tap()
        app.textFields["addPlacesSearch"].typeText("pizza\n")
        let keyboardDismissed = NSPredicate(format: "exists == false")
        expectation(for: keyboardDismissed, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        let add = app.buttons["Add Synthetic pizza place"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        XCTAssertTrue(app.staticTexts["4 places selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addPlacesSelection"].waitForExistence(timeout: 5))
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
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "Weekend plan")
        XCTAssertEqual(field.value as? String, "Weekend plan")
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
