import XCTest

extension XCTestCase {
    /// Tap the trailing edge before deleting, including when a long value scrolls horizontally.
    @MainActor func replaceTripName(_ field: XCUIElement, with name: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let empty = NSPredicate { _, _ in
            (field.value as? String ?? "").isEmpty || field.value as? String == field.placeholderValue
        }
        for _ in 0 ..< 8 {
            let value = field.value as? String ?? ""
            if empty.evaluate(with: nil) { break }
            field.coordinate(withNormalizedOffset: .init(dx: 0.98, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.utf16.count))
        }
        let cleared = XCTNSPredicateExpectation(predicate: empty, object: nil)
        guard XCTWaiter.wait(for: [cleared], timeout: 3) == .completed else {
            let screenshot = XCTAttachment(screenshot: field.screenshot())
            screenshot.name = "Trip name field after clearing"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTFail("Trip name was not cleared: value=\(String(describing: field.value)), placeholder=\(String(describing: field.placeholderValue))")
            return
        }
        guard !name.isEmpty else { return }
        field.tap()
        field.typeText(name)
        XCTAssertEqual(field.value as? String, name, "Verify the exact name before saving")
    }

    @MainActor func scrollToTripControl(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 18 {
            if element.exists && element.isHittable { return }
            let itinerary = app.scrollViews["itineraryList"]
            let scroll = itinerary.exists ? itinerary : app.collectionViews.firstMatch
            let start = scroll.coordinate(withNormalizedOffset: .init(dx: 0.97, dy: 0.82))
            let end = scroll.coordinate(withNormalizedOffset: .init(dx: 0.97, dy: 0.22))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Control should be reachable")
    }

    @MainActor func openTripMenu(_ app: XCUIApplication) {
        let button = app.buttons["homeAddTrip"]
        let option = app.buttons["Get Recommendations"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        if option.waitForExistence(timeout: 5) { return }
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Trip menu should open")
    }

    @MainActor func openMockCreation(_ app: XCUIApplication, recommendations: Bool = false) {
        openTripMenu(app)
        app.buttons[recommendations ? "Get Recommendations" : "Add Specific Place"].tap()
        if recommendations {
            XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
            app.buttons["Skip"].tap()
        } else {
            XCTAssertTrue(app.buttons["addPlacesNext"].waitForExistence(timeout: 5))
            app.buttons["addPlacesNext"].tap()
        }
    }

    @MainActor func reviewMockItinerary(_ app: XCUIApplication) {
        openMockCreation(app)
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 10))
    }

    @MainActor func saveMockItinerary(_ app: XCUIApplication) {
        let save = app.buttons["Save this trip"]
        scrollToTripControl(save, in: app)
        save.tap()
        XCTAssertTrue(app.alerts["Save Itinerary"].waitForExistence(timeout: 5))
        app.alerts["Save Itinerary"].buttons["Save"].tap()
        let go = app.buttons["Save this trip"]
        XCTAssertTrue(app.navigationBars["Synthetic coffee afternoon"].waitForExistence(timeout: 10))
        scrollToTripControl(go, in: app)
        XCTAssertEqual(go.label, "Go Trip")
    }

    @MainActor func openSavedTripFromHome(named name: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.navigationBars["Itinerary"].exists)
        XCTAssertFalse(app.navigationBars[name].exists)
        XCTAssertFalse(app.buttons["Save this trip"].exists)
        let trip = app.staticTexts[name]
        XCTAssertTrue(trip.waitForExistence(timeout: 5), app.debugDescription)
        trip.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), app.debugDescription)
    }
}
