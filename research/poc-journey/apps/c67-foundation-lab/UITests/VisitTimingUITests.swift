import XCTest

@MainActor final class VisitTimingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--timing-ui"]
        app.launch()
        XCTAssertTrue(app.buttons["timing-venue"].waitForExistence(timeout: 15))
        return app
    }
    private func reach(_ element: XCUIElement, app: XCUIApplication, up: Bool) {
        for _ in 0 ..< 14 {
            if element.exists && element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Unreachable: \(element)")
    }
    private func preset(_ id: String, app: XCUIApplication) {
        let button = app.buttons["timing-preset-\(id)"]
        reach(button, app: app, up: true)
        button.tap()
        reach(app.buttons["timing-calculate"], app: app, up: false)
        app.buttons["timing-calculate"].tap()
        reach(app.staticTexts["timing-result"], app: app, up: true)
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
    func testPublishedClosureAndUnknownCases() {
        let app = launch()
        preset("suspended", app: app)
        XCTAssertEqual(app.staticTexts["timing-result"].label, "Usulan ditahan: pengumuman penutupan")
        capture("Official MACAN notice overrides regular hours")
        preset("unknown", app: app)
        XCTAssertEqual(app.staticTexts["timing-result"].label, "Jam layanan belum diketahui")
        capture("Unpublished weekend hours stay unknown")
        preset("monday", app: app)
        XCTAssertEqual(app.staticTexts["timing-result"].label, "Tutup menurut jadwal reguler")
        capture("Ragunan Monday closure")
        app.tabBars.buttons["01 · FM"].tap()
        XCTAssertTrue(app.buttons["onboarding-next"].waitForExistence(timeout: 15))
        app.tabBars.buttons["02 · Minat"].tap()
        XCTAssertTrue(app.buttons["prefer-interest-coffee"].waitForExistence(timeout: 15))
        app.tabBars.buttons["03 · Waktu"].tap()
        reach(app.staticTexts["timing-result"], app: app, up: true)
        XCTAssertEqual(app.staticTexts["timing-result"].label, "Tutup menurut jadwal reguler")
        capture("Completed result survives tab switching")
    }
    func testActualWeekendScheduleHistoryAndExport() {
        let app = launch()
        preset("weekend", app: app)
        XCTAssertEqual(app.staticTexts["timing-result"].label, "Opsi menurut jam layanan")
        capture("Jatinegara sourced weekend options")
        let export = app.buttons["timing-export"]
        reach(export, app: app, up: true)
        export.tap()
        XCTAssertTrue(app.buttons["Bagikan JSON"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Bagikan Markdown"].exists)
        app.terminate()
        app.launch()
        app.buttons["timing-history"].tap()
        let saved = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "timing-history-")
        ).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        reach(app.staticTexts["timing-result"], app: app, up: true)
        capture("Restored dated result")
    }
}
