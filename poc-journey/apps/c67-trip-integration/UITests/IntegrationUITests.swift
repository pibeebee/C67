import XCTest

@MainActor final class IntegrationUITests: XCTestCase {
    private func app() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--p3-replay"]
        app.launch()
        return app
    }
    private func tap(_ id: String, app: XCUIApplication) {
        let button = app.buttons[id]
        for _ in 0 ..< 18 {
            // Form rows are created lazily. Scroll before treating an off-screen row
            // as missing; a pre-scroll existence assertion incorrectly fails the journey.
            if !button.exists { _ = button.waitForExistence(timeout: 1) }
            if button.exists && button.isHittable && button.isEnabled { button.tap(); return }
            app.swipeUp()
        }
        XCTFail("Control not reachable: \(id)")
    }
    private func proposal(_ app: XCUIApplication) {
        tap("recommend", app: app)
        tap("verify-locations", app: app)
        tap("calculate-plan", app: app)
        XCTAssertTrue(app.buttons["proposal"].waitForExistence(timeout: 30))
        tap("proposal", app: app)
        XCTAssertTrue(app.staticTexts["plan-status"].waitForExistence(timeout: 5))
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "P3 replay reviewed schedule"
        evidence.lifetime = .keepAlways
        add(evidence)
    }
    func testReplayJourneyCanBeReviewedAndAccepted() {
        let app = app(); proposal(app)
        XCTAssertTrue(app.staticTexts["REPLAY SINTETIS"].exists)
        tap("accept-plan", app: app)
        XCTAssertTrue(app.staticTexts["Versi tersimpan; tidak diubah oleh input baru."].waitForExistence(timeout: 5))
    }
    func testReplayCannotBeMistakenForWeatherKitDiagnosis() {
        let app = app()
        for _ in 0 ..< 18 {
            let button = app.buttons["Diagnosis dan bukti cuaca"]
            if button.isHittable { button.tap(); break }
            app.swipeUp()
        }
        XCTAssertFalse(app.buttons["Jalankan diagnosis WeatherKit"].isEnabled)
    }
}
