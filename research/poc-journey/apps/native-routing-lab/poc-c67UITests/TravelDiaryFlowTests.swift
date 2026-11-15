import XCTest

final class TravelDiaryFlowTests: XCTestCase {
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func open(_ mode: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--diary-ui-testing", "--diary-demo", mode, "--diary-seed-photo"]
        app.launch()
        let open = app.buttons["diary-open-memory"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        XCTAssertTrue(app.buttons["diary-add-footprint"].waitForExistence(timeout: 10))
        return app
    }

    func testOutsideAndUncertainLocationsKeepUploadLocked() {
        for mode in ["outside", "uncertain"] {
            let app = open(mode)
            XCTAssertFalse(app.buttons["diary-add-footprint"].isEnabled)
            capture("\(mode)-locked", app: app)
            app.terminate()
        }
    }

    func testInsideDemoCanCreatePairedLocalMemory() {
        let app = open("inside")
        let add = app.buttons["diary-add-footprint"]
        XCTAssertTrue(add.isEnabled)
        capture("inside-unlocked", app: app)
        add.tap()
        let name = app.textFields["diary-visitor-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Raka")
        app.swipeUp()
        let upload = app.buttons["diary-upload"]
        XCTAssertTrue(upload.waitForExistence(timeout: 5))
        XCTAssertTrue(upload.isEnabled)
        upload.tap()
        XCTAssertTrue(app.staticTexts["diary-upload-success"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Same place,\ndifferent time."].exists)
        capture("shared-postcard", app: app)
    }

    /// Run with simctl driving location at Monas and When-In-Use permission already granted.
    func testCoreLocationProviderCanConfirmFreshUpload() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--diary-ui-testing", "--diary-seed-photo"]
        app.launch()
        let open = app.buttons["diary-open-memory"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        capture("map-device-provider", app: app)
        open.tap()
        let enable = app.buttons["diary-enable-location"]
        XCTAssertTrue(enable.waitForExistence(timeout: 10))
        enable.tap()
        let add = app.buttons["diary-add-footprint"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: add)
        waitForExpectations(timeout: 20)
        capture("corelocation-arrived", app: app)
        add.tap()
        let name = app.textFields["diary-visitor-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Raka")
        app.swipeUp()
        let upload = app.buttons["diary-upload"]
        expectation(for: enabled, evaluatedWith: upload)
        waitForExpectations(timeout: 10)
        upload.tap()
        XCTAssertTrue(app.staticTexts["diary-upload-success"].waitForExistence(timeout: 20))
        capture("corelocation-postcard", app: app)
    }
}
