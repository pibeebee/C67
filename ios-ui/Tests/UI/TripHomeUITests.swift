import XCTest

final class TripHomeUITests: XCTestCase {
    @MainActor func testEmptyHomeNavigationAndPlanningEntry() {
        let app = XCUIApplication()
        app.launchArguments += ["--skip-splash"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homeEmptyState"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(app.buttons["homeAddTrip"].frame.width, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["homeAddTrip"].frame.height, 44)
        XCTAssertLessThanOrEqual(app.buttons["homeAddTrip"].frame.width, 48)
        XCTAssertLessThanOrEqual(app.buttons["homeAddTrip"].frame.height, 48)
        capture(app, name: "HOME EMPTY - Light")

        app.buttons["homeLocation"].tap()
        XCTAssertTrue(app.navigationBars["Starting point"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        app.buttons["Cancel"].tap()

        openTripMenu(app)
        app.buttons["Get Recommendations"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["homeEmptyState"].waitForExistence(timeout: 5))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No trips yet"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Sign-in needs live mode"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Trip"].tap()
        XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 5))
    }

    @MainActor func testEmptyHomeAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments += ["--skip-splash"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homeEmptyState"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["homeAddTrip"].isHittable)
        XCTAssertTrue(app.buttons["homeLocation"].isHittable)
        capture(app, name: "HOME EMPTY - Accessibility XXXL")
        openTripMenu(app)
        app.buttons["Get Recommendations"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
    }

    @MainActor func testSavingMockProposalOpensTripAndReturnsHome() {
        let app = XCUIApplication()
        app.launchArguments += ["--skip-splash"]
        app.launch()
        reviewMockItinerary(app)
        saveMockItinerary(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["homeEmptyState"].exists)
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 12 {
            if element.exists && element.isHittable { return }
            let itinerary = app.scrollViews["itineraryList"]
            let form = itinerary.exists ? itinerary : app.collectionViews.firstMatch
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.85))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.2))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.exists, "Expected planning control after scrolling")
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
