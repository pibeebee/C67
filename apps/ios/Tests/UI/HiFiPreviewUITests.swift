import XCTest

final class HiFiPreviewUITests: XCTestCase {
    @MainActor func testNewSketchStatesRender() {
        let arguments = ["--add-places-preview", "--add-places-selected-preview", "--places-sheet-preview",
                         "--home-added-preview", "--saved-trip-preview", "--active-trip-preview", "--arrival-preview", "--save-name-preview"]
        for argument in arguments {
            let app = XCUIApplication()
            app.launchArguments = [argument, "-AppleInterfaceStyle", "Light"]
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
            let expected = argument == "--arrival-preview" ? "You’ve arrived" : argument == "--active-trip-preview" ? "80 m" : nil
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
