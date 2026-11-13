import XCTest

final class ItineraryEditorUITests: XCTestCase {
    @MainActor private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--revision-ui-test"] + (reset ? ["--revision-reset"] : [])
        app.launch()
        app.tabBars.buttons["Rencana"].tap()
        XCTAssertTrue(app.buttons["revision-open"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func tap(_ id: String, in app: XCUIApplication) {
        let element = app.buttons[id]
        for _ in 0 ..< 15 {
            guard element.exists else { app.swipeUp(); continue }
            let screen = app.windows.firstMatch.frame
            let needsSafeRow = id == "revision-calculate" || id == "revision-preview-map"
            let safe = !needsSafeRow || (element.frame.midY > screen.minY + 120 && element.frame.midY < screen.maxY - 110)
            if element.exists && element.isHittable && safe { element.tap(); return }
            if needsSafeRow && element.exists && element.frame.midY <= screen.minY + 120 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTFail("Button unavailable: " + id)
    }
    @MainActor private func select(_ index: Int, in app: XCUIApplication) {
        XCTAssertTrue(app.textFields["revision-search-text"].waitForExistence(timeout: 5))
        app.textFields["revision-search-text"].tap()
        app.textFields["revision-search-text"].typeText("Jakarta\n")
        XCTAssertTrue(app.buttons["revision-search-result-\(index)"].waitForExistence(timeout: 5))
        app.buttons["revision-search-result-\(index)"].tap()
        XCTAssertTrue(app.buttons["revision-confirm-place"].waitForExistence(timeout: 5))
        app.buttons["revision-confirm-place"].tap()
    }
    @MainActor func testReplaceReorderDeleteAddTransitPreviewApplyAndHistory() {
        let app = launch()
        tap("revision-open", in: app)
        tap("revision-replace-0", in: app); select(2, in: app)
        tap("revision-down-0", in: app)
        tap("revision-delete-0", in: app)
        XCTAssertTrue(app.alerts["Hapus tujuan wajib?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Hapus tujuan"].tap()
        tap("revision-add", in: app); select(3, in: app)
        for _ in 0 ..< 10 { if app.buttons["revision-transport"].isHittable { break }; app.swipeDown() }
        app.buttons["revision-transport"].tap()
        app.buttons["TJ + jalan kaki"].tap()
        tap("revision-calculate", in: app)
        for _ in 0 ..< 8 {
            if app.staticTexts["revision-preview-status"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["revision-preview-status"].waitForExistence(timeout: 10))
        tap("revision-apply", in: app)
        XCTAssertTrue(app.buttons["revision-open"].waitForExistence(timeout: 5))
        app.terminate()
        _ = launch(reset: false)
        XCTAssertTrue(app.buttons["revision-history"].exists)
        XCTAssertTrue(app.buttons["revision-history"].label.contains("2"))
        app.buttons["revision-history"].tap()
        XCTAssertTrue(app.navigationBars["Riwayat itinerary"].waitForExistence(timeout: 5))
    }
    @MainActor func testSavedDraftRelaunchAndCancelKeepAcceptedVersion() {
        let app = launch()
        tap("revision-open", in: app)
        tap("revision-down-0", in: app)
        tap("revision-save-draft", in: app)
        app.terminate()
        _ = launch(reset: false)
        tap("revision-open", in: app)
        XCTAssertTrue(app.staticTexts["revision-stop-0"].label.contains("Museum"))
        tap("revision-cancel", in: app)
        XCTAssertTrue(app.buttons["revision-open"].waitForExistence(timeout: 5))
        tap("revision-open", in: app)
        XCTAssertTrue(app.staticTexts["revision-stop-0"].label.contains("Taman"))
        tap("revision-cancel", in: app)
    }
    @MainActor func testTransitMapOpensSelectsLegAndReturnsToDraft() {
        let app = launch(); tap("revision-open", in: app)
        app.buttons["revision-transport"].tap(); app.buttons["TJ + jalan kaki"].tap()
        tap("revision-calculate", in: app)
        tap("revision-preview-map", in: app)
        XCTAssertTrue(app.navigationBars["Peta itinerary"].waitForExistence(timeout: 10))
        tap("personal-route-leg-0", in: app)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Synthetic TJ revision map"; attachment.lifetime = .keepAlways; add(attachment)
        tap("personal-route-all", in: app)
        tap("personal-route-close", in: app)
        tap("revision-save-draft", in: app)
    }

}
