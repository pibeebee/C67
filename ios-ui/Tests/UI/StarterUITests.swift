import XCTest

final class StarterUITests: XCTestCase {
    @MainActor func testMockDiscoveryDetailAndTrip() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Mock • memory only"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kota Tua Photo Walk")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1. Fatahillah Square"].waitForExistence(timeout: 5))
        app.buttons["Save as my trip"].tap()
        XCTAssertTrue(app.alerts["Trip saved"].waitForExistence(timeout: 5))
        app.alerts["Trip saved"].buttons["OK"].tap()
    }
}
