import XCTest

@MainActor final class ContextLabUITests: XCTestCase {
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testControlledWeatherAndHoursCampaign() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--context-legacy"]
        app.launch()
        app.tabBars.buttons["Eksperimen"].tap()
        let button = app.buttons["controlled-benchmark-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        screenshot("controlled-start")
        button.tap()
        XCTAssertTrue(app.staticTexts["benchmark-complete"].waitForExistence(timeout: 180), app.debugDescription)
        XCTAssertFalse(app.staticTexts["operation-error"].exists)
        screenshot("controlled-complete")
    }

    func testGBKDynamicSearchAndPreparation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--context-legacy"]
        app.launch()
        let query = app.textFields["place-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap(); query.typeText("GBK")
        app.buttons["search-button"].tap()
        let result = app.buttons["search-result-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 40), app.debugDescription)
        screenshot("gbk-google-search")
        result.tap()
        let confirmed = app.staticTexts["operation-status"]
        let predicate = NSPredicate(format: "label CONTAINS %@", "Konfirmasi lokasi Apple")
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: confirmed)], timeout: 60) == .completed, app.debugDescription)
        let candidate = app.buttons["apple-option-0"]
        for _ in 0 ..< 8 {
            if candidate.exists && candidate.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(candidate.exists && candidate.isHittable, app.debugDescription)
        screenshot("gbk-apple-candidates")
        candidate.tap()
        for _ in 0 ..< 8 where !app.staticTexts["operation-status"].exists { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["operation-status"].label.contains("1 tujuan dipilih"))
        screenshot("gbk-selected")
    }
    private func runLive(_ filename: String, count: Int, selective: Bool = false, beam: Bool = false) {
        let app = XCUIApplication()
        app.launchEnvironment["CONTEXT_SELECTION_FILE"] = filename
        if selective || beam {
            app.launchEnvironment["CONTEXT_LIVE_POLICY"] = beam ? "beam" : "selectiveOrders"
            app.launchEnvironment["CONTEXT_LIVE_REPETITIONS"] = "1"
        }
        app.launch()
        let status = app.staticTexts["operation-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("Pilihan runtime siap"), app.debugDescription)
        let button = app.buttons["live-benchmark-button"]
        for _ in 0 ..< 12 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable, app.debugDescription)
        screenshot("live-\(count)-input")
        button.tap()
        let complete = app.staticTexts["live-benchmark-complete"]
        // Scroll back to the action/result boundary after asynchronous layout changes.
        let finish = Date().addingTimeInterval(600)
        while !complete.exists && Date() < finish && !app.staticTexts["operation-error"].exists { _ = complete.waitForExistence(timeout: 10) }
        XCTAssertTrue(complete.exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["operation-error"].exists)
        for _ in 0 ..< 6 { app.swipeUp() }
        screenshot("live-\(count)-result")
    }
    func testLiveThreeStops() { runLive("selection-three.json", count: 3) }
    func testBeamThreeStops() { runLive("selection-three.json", count: 3, beam: true) }
    func testSelectiveThreeStops() { runLive("selection-three.json", count: 3, selective: true) }
    func testLiveFiveStops() { runLive("selection-five.json", count: 5) }

}
