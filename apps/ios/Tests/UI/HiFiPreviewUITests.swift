import XCTest

final class HiFiPreviewUITests: XCTestCase {
    @MainActor func testTripCompletionKeepsDoneAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["--completed-trip-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Trip complete"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Done"].isHittable)
    }

    @MainActor func testNavigationAndArrivalControlsAreVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--active-trip-preview", "-AppleInterfaceStyle", "Light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["450 m"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Navigate with Apple Maps"].isHittable)
        XCTAssertTrue(app.buttons["Back to trip"].isHittable)
        XCTAssertTrue(app.buttons["confirmTripArrival"].isHittable)
        app.terminate()

        app.launchArguments = ["--arrival-preview", "-AppleInterfaceStyle", "Light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["You’ve arrived"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["completeTripVisit"].isHittable)
    }

    @MainActor func testNavigationActionsRemainReachableAtAccessibilitySize() {
        let app = XCUIApplication()
        app.launchArguments = ["--active-trip-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["On your way"].waitForExistence(timeout: 10))
        for identifier in ["Navigate with Apple Maps", "confirmTripArrival", "Back to trip"] {
            let button = app.buttons[identifier]
            for _ in 0 ..< 8 where !button.isHittable { app.scrollViews["tripProgressPanel"].swipeUp() }
            XCTAssertTrue(button.isHittable, "\(identifier) should remain reachable")
        }
    }

    @MainActor func testNewSketchStatesRender() {
        let arguments = ["--add-places-preview", "--add-places-selected-preview", "--places-sheet-preview",
                         "--home-added-preview", "--saved-trip-preview", "--active-trip-preview", "--arrival-preview", "--save-name-preview"]
        for argument in arguments {
            let app = XCUIApplication()
            app.launchArguments = [argument, "-AppleInterfaceStyle", "Light"]
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
            let expected = argument == "--arrival-preview" ? "You’ve arrived" : argument == "--active-trip-preview" ? "On your way" : nil
            if let expected { XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 5)) }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = argument
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    @MainActor func testAddPlacesAccessibleReadingWidth() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--add-places-preview", "-AppleInterfaceStyle", "Light"]
        app.launch()
        XCTAssertTrue(app.buttons["addPlacesNext"].waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(app.buttons["addPlacesNext"].frame.width, 640)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .textClipped])
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ADD PLACES - Reading width and accessibility"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testArrivalAtAccessibilitySizeInDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--arrival-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["You’ve arrived"].waitForExistence(timeout: 10))
        let complete = app.buttons["completeTripVisit"]
        for _ in 0 ..< 12 {
            if complete.exists && complete.isHittable { break }
            app.scrollViews["tripProgressPanel"].swipeUp()
        }
        XCTAssertTrue(complete.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arrival - Dark Accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
