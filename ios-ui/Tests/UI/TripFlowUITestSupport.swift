import XCTest

extension XCTestCase {
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

    @MainActor func openMockCreation(_ app: XCUIApplication, recommendations: Bool = false) {
        XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 10))
        app.buttons["homeAddTrip"].tap()
        app.buttons[recommendations ? "Get Recommendations" : "Add Specific Place"].tap()
        if recommendations {
            for _ in 0 ..< 7 {
                XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
                app.buttons["Skip"].tap()
            }
        } else {
            XCTAssertTrue(app.buttons["addPlacesNext"].waitForExistence(timeout: 5))
            app.buttons["addPlacesNext"].tap()
        }
        let confirm = app.buttons["confirmTripInput"]
        scrollToTripControl(confirm, in: app)
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
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
}
