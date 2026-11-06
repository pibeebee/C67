import XCTest

@MainActor final class LivePreferenceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(slow: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["--preference-live-fixture", "--preference-reset"]
                + (slow ? ["--preference-slow-fixture"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["prefer-interest-coffee"].waitForExistence(timeout: 15))
        return app
    }
    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0 ..< 10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(
            element.exists && element.isHittable, "Missing or unreachable control: \(element)")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testSearchLikeRefreshRestoreAndExport() {
        let app = launch()
        app.buttons["prefer-interest-coffee"].tap()
        app.buttons["prefer-interest-reading"].tap()
        capture("Live entry with labeled replay provider")
        app.buttons["compare-preferences-toolbar"].tap()
        XCTAssertTrue(app.staticTexts["preference-result-title"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["live-search-provenance"].label.contains("Injected replay"))
        let like = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "result-like-"))
            .firstMatch
        XCTAssertTrue(like.exists)
        let removedID = like.identifier
        scrollTo(like, app: app)
        like.tap()
        let refresh = app.buttons["refresh-live-preferences"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        scrollTo(refresh, app: app)
        refresh.tap()
        XCTAssertTrue(app.staticTexts["preference-result-title"].waitForExistence(timeout: 30))
        XCTAssertFalse(
            app.buttons[removedID].exists, "Liked place must be excluded from refreshed recommendations")
        capture("Fresh ranking after liking a place")
        app.terminate()
        app.launchArguments = ["--preference-live-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["preference-experiments"].waitForExistence(timeout: 15))
        app.buttons["preference-experiments"].tap()
        let history = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "MapKit langsung"))
            .firstMatch
        scrollTo(history, app: app)
        history.tap()
        let open = app.buttons["open-preference-result"]
        for _ in 0 ..< 5 {
            if open.exists && open.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(open.exists)
        let export = app.buttons["export-preference-run"]
        scrollTo(export, app: app)
        export.tap()
        XCTAssertTrue(app.buttons["Bagikan JSON"].exists)
        XCTAssertTrue(app.buttons["Bagikan Markdown"].exists)
        capture("Restored history and export")
    }
    func testCancellationAndLegacyTabRemainAvailable() {
        let app = launch(slow: true)
        app.buttons["prefer-interest-coffee"].tap()
        app.buttons["compare-preferences-toolbar"].tap()
        let cancel = app.buttons["cancel-live-preferences"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertFalse(app.staticTexts["preference-result-title"].exists)
        app.tabBars.buttons["01 · FM"].tap()
        XCTAssertTrue(app.buttons["onboarding-next"].waitForExistence(timeout: 15))
        capture("Original Foundation journey remains accessible")
    }
}
