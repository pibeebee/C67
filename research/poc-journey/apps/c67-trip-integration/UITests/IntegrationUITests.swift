import XCTest

@MainActor final class IntegrationUITests: XCTestCase {
    private func app(arguments: [String] = ["--p3-replay"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
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
    func testBlokMReplayJourneyCanBeReviewedAndAccepted() {
        let app = app(arguments: ["--p3-blok-m-replay"])
        XCTAssertTrue(app.staticTexts["blok-m-mode"].waitForExistence(timeout: 5))
        proposal(app)
        XCTAssertTrue(app.staticTexts["REPLAY SINTETIS"].exists)
        tap("accept-plan", app: app)
        XCTAssertTrue(app.staticTexts["Versi tersimpan; tidak diubah oleh input baru."].waitForExistence(timeout: 5))
    }
    func testBuswayReplayCanBeReviewedAndAccepted() {
        let app = app(arguments: ["--p3-busway-replay"])
        XCTAssertTrue(app.staticTexts["busway-assumptions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["transport-mode"].exists)
        proposal(app)
        XCTAssertTrue(app.staticTexts["REPLAY SINTETIS"].exists)
        tap("accept-plan", app: app)
        XCTAssertTrue(app.staticTexts["Versi tersimpan; tidak diubah oleh input baru."].waitForExistence(timeout: 5))
        for _ in 0 ..< 12 {
            if app.staticTexts["busway-leg"].firstMatch.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["busway-leg"].firstMatch.exists)
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
