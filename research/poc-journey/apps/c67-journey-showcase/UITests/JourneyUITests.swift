import XCTest

@MainActor final class JourneyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(_ name: String = UUID().uuidString) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--journey-test-id", name]
        app.launch()
        return app
    }
    private func tap(_ id: String, in app: XCUIApplication) {
        let button = ["Jakarta", "Blok M"].contains(id) ? app.segmentedControls["catalog-area"].buttons[id] : app.buttons[id]
        for _ in 0 ..< 24 {
            let footer = ["new-trip", "next-preferences", "find-places", "review-places", "generate-itinerary", "save-itinerary", "back-home"].contains(id)
            let toolbar = id == "close-leg"
            if button.waitForExistence(timeout: 1) {
                let aboveFooter = toolbar || footer || button.frame.maxY < app.frame.maxY - 130
                if button.isHittable, button.isEnabled, aboveFooter { button.tap(); return }
                if button.frame.maxY < 105 { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        XCTFail("Unreachable action \(id). \(app.debugDescription)")
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func create(_ app: XCUIApplication, car: Bool = false, personalized: Bool = false) {
        tap("new-trip", in: app)
        tap("Blok M", in: app)
        if car { tap("transport-automobile", in: app) }
        tap("next-preferences", in: app)
        if personalized { tap("interest-coffee", in: app); tap("interest-wifi", in: app) }
        tap("find-places", in: app)
        tap("review-places", in: app)
        tap("generate-itinerary", in: app)
        XCTAssertTrue(app.staticTexts["itinerary-status"].waitForExistence(timeout: 30))
    }
    func testHomeShowsCreateAction() {
        let app = launch()
        XCTAssertTrue(app.buttons["new-trip"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["new-trip"].isEnabled, app.debugDescription)
        tap("new-trip", in: app)
        XCTAssertTrue(app.buttons["next-preferences"].waitForExistence(timeout: 5), app.debugDescription)
    }
    func testMapZoomFullScreenAndRoadLoadingControls() {
        let app = launch()
        create(app)
        tap("map-zoom-in", in: app)
        XCTAssertEqual(app.buttons["map-zoom-in"].value as? String, "1 perubahan zoom")
        tap("map-zoom-out", in: app)
        XCTAssertEqual(app.buttons["map-zoom-in"].value as? String, "2 perubahan zoom")
        tap("map-fullscreen", in: app)
        XCTAssertTrue(app.buttons["close-full-map"].waitForExistence(timeout: 5))
        tap("full-map-zoom-in", in: app)
        tap("full-map-zoom-out", in: app)
        tap("full-map-fit", in: app)
        XCTAssertTrue(app.staticTexts["full-map-route-status"].exists)
        capture("Journey full road map", app: app)
        tap("close-full-map", in: app)
        XCTAssertTrue(app.buttons["save-itinerary"].waitForExistence(timeout: 5))
    }
    func testCityCatalogAndTimeBudgetActionsAreReachable() {
        let app = launch()
        tap("new-trip", in: app)
        tap("Jakarta", in: app)
        XCTAssertTrue(app.textFields["origin-query"].exists)
        tap("budget-longer", in: app)
        tap("budget-shorter", in: app)
        XCTAssertTrue(app.staticTexts["time-budget"].exists)
        capture("Journey time budget controls", app: app)
        tap("next-preferences", in: app)
        XCTAssertTrue(app.buttons["find-places"].waitForExistence(timeout: 5))
    }
    func testTJGuidedJourneyDetailSaveRelaunchAndExport() {
        let app = launch()
        capture("Journey home", app: app)
        create(app)
        capture("Journey itinerary", app: app)
        tap("leg-0", in: app)
        XCTAssertTrue(app.otherElements["tj-detail"].waitForExistence(timeout: 5) || app.staticTexts["TransJakarta"].exists)
        capture("Journey TJ detail", app: app)
        tap("tj-stop-list", in: app)
        tap("close-leg", in: app)
        tap("save-itinerary", in: app)
        XCTAssertTrue(app.staticTexts["itinerary-saved"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        tap("open-saved", in: app)
        XCTAssertTrue(app.staticTexts["itinerary-saved"].waitForExistence(timeout: 5))
        tap("export-itinerary", in: app)
        XCTAssertTrue(app.buttons["share-md"].waitForExistence(timeout: 10))
    }
    func testCarJourneyWithCoffeeWifiPreferences() {
        let app = launch()
        create(app, car: true, personalized: true)
        XCTAssertTrue(app.staticTexts["itinerary-status"].exists)
        tap("save-itinerary", in: app)
        XCTAssertTrue(app.staticTexts["itinerary-saved"].waitForExistence(timeout: 10))
        capture("Journey personalized car itinerary", app: app)
    }
    func testDraftRestoresAcrossRelaunch() {
        let app = launch()
        tap("new-trip", in: app); tap("next-preferences", in: app)
        tap("interest-art", in: app); tap("find-places", in: app)
        XCTAssertTrue(app.buttons["review-places"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate(); app.launch()
        tap("resume-draft", in: app)
        XCTAssertTrue(app.buttons["review-places"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testLargeTextDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--journey-test-id", UUID().uuidString, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        tap("new-trip", in: app); tap("next-preferences", in: app)
        capture("Journey accessibility dark", app: app)
        tap("find-places", in: app)
        XCTAssertTrue(app.buttons["review-places"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func testCustomOriginAreaAndSpotFlow() {
        let app = launch()
        tap("new-trip", in: app)
        tap("Jakarta", in: app)
        let origin = app.textFields["origin-query"]
        tap("clear-origin", in: app)
        origin.tap()
        origin.typeText("Senayan\n")
        tap("origin-result-demo-origin-Senayan", in: app)
        XCTAssertTrue(app.staticTexts["chosen-origin"].exists)
        tap("transport-automobile", in: app)
        tap("next-preferences", in: app)
        tap("area-cikini", in: app)
        tap("Cari & pilih spot dalam katalog", in: app)
        tap("desired-spot-cikini", in: app)
        tap("find-places", in: app)
        tap("review-places", in: app)
        tap("generate-itinerary", in: app)
        XCTAssertTrue(app.staticTexts["itinerary-status"].waitForExistence(timeout: 30))
        capture("Custom Senayan origin and Cikini spot", app: app)
        tap("save-itinerary", in: app)
        XCTAssertTrue(app.staticTexts["itinerary-saved"].waitForExistence(timeout: 10))
    }

}
