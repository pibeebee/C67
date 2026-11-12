import XCTest

final class ItineraryUITests: XCTestCase {
    @MainActor func testSketchPreviewHasTimelineAndExpandableContext() {
        let app = XCUIApplication()
        app.launchArguments += ["--skip-splash"]
        app.launchArguments = ["--itinerary-preview"]
        if ProcessInfo.processInfo.environment["C67_TEST_LARGE_TEXT"] == "1" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["All set! Here’s your itinerary"].waitForExistence(timeout: 10))
        capture(app, name: "ITINERARY LIST - Departure")
        let first = app.staticTexts["ALDI’S BURGER"]
        scrollTo(first, in: app)
        XCTAssertTrue(first.exists)
        let context = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Behind the scenes of your plan")).firstMatch
        scrollTo(context, in: app)
        context.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sample content from the supplied Sketch design")).firstMatch.exists)
        let save = app.buttons["Save this trip"]
        scrollTo(save, in: app)
        XCTAssertTrue(save.isEnabled)
        capture(app, name: "ITINERARY LIST - Map and sources")
        save.tap()
        XCTAssertTrue(app.alerts["Design preview"].waitForExistence(timeout: 5))
    }

    @MainActor func testGeneratedItineraryCanEditVisitAndReplan() {
        let app = XCUIApplication()
        app.launchArguments += ["--skip-splash"]
        app.launch()
        reviewMockItinerary(app)
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "itineraryEdit-")).firstMatch
        scrollTo(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit visit"].waitForExistence(timeout: 5))
        app.steppers.firstMatch.buttons.element(boundBy: 1).tap()
        app.buttons["Update itinerary"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 10))
        let addPlace = app.buttons["itineraryAddPlace"]
        scrollTo(addPlace, in: app)
        addPlace.tap()
        XCTAssertTrue(app.navigationBars["Add a place"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        app.navigationBars["Add a place"].buttons["Cancel"].tap()
        let save = app.buttons["Save this trip"]
        scrollTo(save, in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        saveMockItinerary(app)
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 20 {
            if element.exists && element.isHittable { return }
            let itinerary = app.scrollViews["itineraryList"]
            let scroll = itinerary.exists ? itinerary : app.collectionViews.firstMatch
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.85))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.25))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTFail("Expected itinerary control after scrolling")
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
