import XCTest

final class RecommendationsUITests: XCTestCase {
    @MainActor func testSpecificPlaceCanBeInspectedOnMap() {
        let app = XCUIApplication()
        app.launchArguments = ["--add-places-preview"]
        app.launch()
        let mapButton = app.buttons.matching(identifier: "View on map").firstMatch
        XCTAssertTrue(mapButton.waitForExistence(timeout: 10))
        mapButton.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["addPlacesNext"].exists)
    }
    @MainActor func testPreferenceSearchAndSelectionRemainAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash"]
        app.launch()
        XCTAssertTrue(app.buttons["homePlanTrip"].waitForExistence(timeout: 10))
        app.buttons["homePlanTrip"].tap()
        let search = app.textFields["preferenceSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("museum")
        let option = app.buttons["pocketLabel-museum"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        app.buttons["Clear search"].tap()
        XCTAssertTrue(app.buttons["selectedPreference-museum"].waitForExistence(timeout: 5))
        app.buttons["selectedPreference-museum"].tap()
        XCTAssertTrue(app.buttons["pocketLabel-museum"].waitForExistence(timeout: 5))
    }

    @MainActor func testSelectedQuickPickMovesAndReturnsWhenRemoved() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash"]
        app.launch()
        XCTAssertTrue(app.buttons["homePlanTrip"].waitForExistence(timeout: 10))
        app.buttons["homePlanTrip"].tap()
        let quickPick = app.buttons["pocketLabel-matcha"]
        let selected = app.buttons["selectedPreference-matcha"]
        XCTAssertTrue(quickPick.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        quickPick.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertFalse(quickPick.exists)
        XCTAssertTrue(app.buttons["Next"].isHittable)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Preferences with a selected interest"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        selected.tap()
        XCTAssertTrue(quickPick.waitForExistence(timeout: 5))
        XCTAssertFalse(selected.exists)
    }

    @MainActor func testRecommendationShowsShortAddressAndDistance() {
        let app = XCUIApplication()
        app.launchArguments = ["--recommendations-added-preview"]
        app.launch()
        let first = app.buttons["ALDI’S BURGER"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue((first.value as? String ?? "").contains("away"))
        XCTAssertTrue((first.value as? String ?? "").contains("Jl. Cemp. Putih Tim. 12 No.8A"))
    }

    @MainActor func testSearchIsAvailableFromSelectedPlaces() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash"]
        app.launch()
        openMockCreation(app, recommendations: true)
        XCTAssertTrue(app.navigationBars["Recommendations"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Search for a place"].exists)
        XCTAssertTrue(app.staticTexts["0 places selected"].exists)
        app.buttons["My Places"].tap()
        let search = app.buttons["selectedPlacesSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.textFields["addPlacesSearch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["0 places selected"].exists)
    }

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
        XCTAssertTrue(app.staticTexts["0 places selected"].exists)
        candidate.tap()
        XCTAssertTrue(app.staticTexts["1 places selected"].exists)
        app.buttons["My Places"].tap()
        XCTAssertTrue(app.navigationBars["Places"].waitForExistence(timeout: 5))
        app.buttons["Remove Synthetic tourist attraction 1"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["0 places selected"].waitForExistence(timeout: 5))
        // The trip needs at least three places before it can be planned.
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recommendation-"))
        for index in 0 ..< 3 { rows.element(boundBy: index).tap() }
        XCTAssertTrue(app.staticTexts["3 places selected"].waitForExistence(timeout: 5))
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Here’s your itinerary"].waitForExistence(timeout: 10))
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
