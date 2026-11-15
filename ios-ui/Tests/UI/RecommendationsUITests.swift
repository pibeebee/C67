import XCTest

final class RecommendationsUITests: XCTestCase {
    @MainActor func testSelectedPlacesRemoveButtonHasUsableTarget() {
        let app = XCUIApplication()
        app.launchArguments = ["--recommendations-added-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["My Places"].waitForExistence(timeout: 10))
        app.buttons["My Places"].tap()
        let remove = app.buttons["Remove ALDI’S BURGER"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(remove.frame.width, 44)
        XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "PLACES - remove button"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        remove.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: remove)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["Remove FamiCafé by FamilyMart"].exists)
    }

    @MainActor func testSpecificPlaceMenuOpensSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash"]
        app.launch()
        XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 10))
        openTripMenu(app)
        XCTAssertTrue(app.buttons["Get Recommendations"].waitForExistence(timeout: 5))
        app.buttons["Add Specific Place"].tap()
        XCTAssertTrue(app.navigationBars["Add Specific Place"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["addPlacesSearch"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 5))
    }

    @MainActor func testMockRecommendationSelectionAndNext() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash"]
        app.launch()
        openMockCreation(app, recommendations: true)
        XCTAssertTrue(app.navigationBars["Recommendations"].waitForExistence(timeout: 10))
        let candidate = app.buttons["Synthetic tourist attraction 1"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 places selected"].exists)
        candidate.tap()
        XCTAssertTrue(app.staticTexts["4 places selected"].exists)
        app.buttons["My Places"].tap()
        XCTAssertTrue(app.navigationBars["Places"].waitForExistence(timeout: 5))
        app.buttons["Remove Synthetic tourist attraction 1"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["3 places selected"].waitForExistence(timeout: 5))
        candidate.tap()
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 10))
    }

    @MainActor func testCanSelectMoreThanThreeAndUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["--recommendations-added-preview"]
        app.launch()
        XCTAssertTrue(app.staticTexts["3 places selected"].waitForExistence(timeout: 10))
        let first = app.buttons["ALDI’S BURGER"]
        let pizza = app.buttons["Pizza 4P's Indonesia"]
        XCTAssertTrue(pizza.isEnabled)
        pizza.tap()
        XCTAssertTrue(app.staticTexts["4 places selected"].exists)
        first.tap()
        XCTAssertTrue(app.staticTexts["3 places selected"].exists)
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.alerts["Design preview"].waitForExistence(timeout: 5))
    }

    @MainActor func testRecommendationsRemainUsableAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--recommendations-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["0 places selected"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["My Places"].isHittable)
        XCTAssertTrue(app.buttons["recommendationsNext"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "PLACES LISTS - Accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["My Places"].tap()
        XCTAssertTrue(app.navigationBars["Places"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 12 {
            if element.exists && element.isHittable { return }
            let form = app.collectionViews.firstMatch
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.85))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.2))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTFail("Expected planning control after scrolling")
    }
}
