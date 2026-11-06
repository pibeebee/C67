import XCTest

@MainActor final class NativePlannerPortabilityTests: XCTestCase {
    func testFixtureConfirmationReportNavigationAndInvalidImport() {
        let app = XCUIApplication()
        app.launchArguments = ["--native-itinerary", "--jakarta-ui-testing"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Rencana"].waitForExistence(timeout: 15))

        app.buttons["Kelola rencana"].tap()
        app.buttons["Muat simulasi penyimpanan"].tap()
        let confirm = app.buttons["Muat simulasi lokal"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let report = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Lihat itinerary")).firstMatch
        reveal(report, in: app, upward: true)
        report.tap()
        XCTAssertTrue(app.navigationBars["Hasil itinerary"].waitForExistence(timeout: 10))
        app.navigationBars["Hasil itinerary"].buttons["Rencana"].tap()

        let importButton = app.buttons["Muat input JSON"]
        reveal(importButton, in: app, upward: false)
        importButton.tap()
        let input = app.textFields["JSON rencana"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("{")
        app.buttons["Gunakan input JSON"].tap()
        XCTAssertTrue(app.staticTexts["native-draft-import-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Ganti input"].exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool) {
        for _ in 0 ..< 12 {
            if element.exists, element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }
}
