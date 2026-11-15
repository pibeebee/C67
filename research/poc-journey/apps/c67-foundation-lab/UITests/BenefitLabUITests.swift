import XCTest

@MainActor final class BenefitLabUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--benefit-ui"]
        app.launch()
        XCTAssertTrue(app.buttons["benefit-preset-currency"].waitForExistence(timeout: 20))
        return app
    }
    func reach(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0 ..< 15 {
            if element.exists && element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testActualEmbeddingComparisonSourcesExportAndHistory() {
        let app = launch()
        app.buttons["benefit-preset-currency"].tap()
        let compare = app.buttons["benefit-compare"]
        reach(compare, app: app)
        compare.tap()
        let result = app.staticTexts["benefit-result"]
        reach(result, app: app)
        XCTAssertEqual(result.label, "comparison_completed")
        capture("Four methods with authored relevance and actual local E5")
        let source = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "benefit-source-")
        ).firstMatch
        reach(source, app: app)
        source.tap()
        capture("Source backed description separate from venue name masking")
        let export = app.buttons["benefit-export"]
        reach(export, app: app)
        export.tap()
        XCTAssertTrue(app.buttons["Bagikan JSON"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        app.buttons["benefit-history"].tap()
        let item = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "benefit-history-")
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        reach(result, app: app)
        XCTAssertEqual(result.label, "comparison_completed")
        app.tabBars.buttons["04 · Cocok"].tap()
        XCTAssertTrue(app.buttons["quality-preset-combo"].waitForExistence(timeout: 10))
    }
    func testImpossibleCombinationAndUnconfirmedNegationSkipModelRanking() {
        let app = launch()
        app.buttons["benefit-preset-impossible"].tap()
        let compare = app.buttons["benefit-compare"]
        reach(compare, app: app)
        compare.tap()
        let result = app.staticTexts["benefit-result"]
        reach(result, app: app)
        XCTAssertEqual(result.label, "no_verified_match")
        capture("No invented coffee-reading-quiet combination")
        let review = app.buttons["benefit-preset-review"]
        reach(review, app: app, up: false)
        review.tap()
        reach(compare, app: app)
        compare.tap()
        reach(result, app: app)
        XCTAssertEqual(result.label, "preference_review_required")
        capture("Unconfirmed constraints do not reach embeddings")
    }
}
