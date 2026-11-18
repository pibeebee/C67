import XCTest

final class TripCreationUITests: XCTestCase {
    @MainActor func testNewTripDoesNotReusePreviousPlaceSelection() {
        let app = launch()
        openTripMenu(app)
        app.buttons["Add Specific Place"].tap()
        let search = app.textFields["addPlacesSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("coffee\n")
        let oldPlace = app.buttons["Add Synthetic coffee shop"]
        XCTAssertTrue(oldPlace.waitForExistence(timeout: 8))
        oldPlace.tap()
        app.buttons["tripCreationCancel"].tap()

        openTripMenu(app)
        app.buttons["Add Specific Place"].tap()
        XCTAssertTrue(app.staticTexts["0 places selected"].waitForExistence(timeout: 5))
        search.tap()
        search.typeText("museum\n")
        let newPlace = app.buttons["Add Synthetic museum"]
        XCTAssertTrue(newPlace.waitForExistence(timeout: 8))
        newPlace.tap()
        app.buttons["addPlacesNext"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic museum"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic coffee shop"].exists)
    }

    @MainActor func testDraggingStopRecalculatesAndPreservesOrder() throws {
        continueAfterFailure = false
        let app = launch()
        openTripMenu(app)
        app.buttons["Add Specific Place"].tap()
        let search = app.textFields["addPlacesSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("coffee\n")
        for name in ["Synthetic coffee shop", "Synthetic museum"] {
            let add = app.buttons["Add \(name)"]
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
        }
        app.buttons["addPlacesNext"].tap()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 10))

        let coffee = app.staticTexts["Synthetic coffee shop"]
        let museum = app.staticTexts["Synthetic museum"]
        let handles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "itineraryReorder-"))
        XCTAssertTrue(museum.waitForExistence(timeout: 5))
        let coffeeFirst = coffee.frame.midY < museum.frame.midY
        let first = coffeeFirst ? coffee : museum
        let second = coffeeFirst ? museum : coffee
        let source = handles.element(boundBy: 0)
        let target = handles.element(boundBy: 1)
        XCTAssertTrue(source.isHittable)
        XCTAssertTrue(target.isHittable)
        // Drop on the destination card rather than its own drag handle.
        let destination = target.coordinate(withNormalizedOffset: CGVector(dx: -2, dy: 0.5))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.2, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 1)
        let reordered = NSPredicate { _, _ in second.exists && first.exists && second.frame.midY < first.frame.midY }
        expectation(for: reordered, evaluatedWith: nil)
        waitForExpectations(timeout: 20)
        XCTAssertTrue(app.buttons["Save this trip"].exists)
        capture(app, "ITINERARY - reordered")
        let save = app.buttons["Save this trip"]
        scrollToTripControl(save, in: app)
        save.tap()
        let dialog = app.alerts["Save Itinerary"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        let name = try XCTUnwrap(dialog.textFields.firstMatch.value as? String)
        dialog.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))
        XCTAssertTrue(first.exists && second.exists)
        XCTAssertLessThan(second.frame.midY, first.frame.midY)
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

    @MainActor func testSpecificPlacesOpenMainSpotAndProcessDirectly() {
        let app = launch()
        openTripMenu(app)
        app.buttons["Add Specific Place"].tap()
        XCTAssertTrue(app.buttons["addPlacesNext"].waitForExistence(timeout: 5))
        app.buttons["addPlacesNext"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Let Travelant decide")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirmTripInput"].exists)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.staticTexts["3 places selected"].exists)
        app.buttons["recommendationsNext"].tap()
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
        replaceTripName(field, with: "Weekend plan")
        guard field.value as? String == "Weekend plan" else { return }
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
