import XCTest

@MainActor final class QualityLabUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--quality-ui", "--quality-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["quality-preset-combo"].waitForExistence(timeout: 15))
        return app
    }
    func reach(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0 ..< 14 {
            if element.exists && element.isHittable && element.frame.midY < app.frame.maxY - 150 {
                return
            }
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
    func testCombinedNeedsCorrectionsHistoryAndExport() {
        let app = launch()
        app.buttons["quality-preset-combo"].tap()
        app.buttons["quality-compare"].tap()
        let result = app.staticTexts["quality-result"]
        reach(result, app: app)
        XCTAssertEqual(result.label, "comparison_completed")
        capture("Actual E5 and same-area coffee-reading comparison")
        let ranking = app.buttons["quality-ranking-Gabungan"]
        reach(ranking, app: app)
        ranking.tap()
        XCTAssertEqual(ranking.value as? String, "Terbuka")
        reach(app.staticTexts["Ruang Temu RBBJ"], app: app)
        capture("Only source-supported combined venue area")
        let export = app.buttons["quality-export"]
        reach(export, app: app)
        export.tap()
        XCTAssertTrue(app.buttons["Bagikan JSON"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--quality-ui"]
        app.launch()
        app.buttons["quality-history"].tap()
        let item = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "quality-history-")
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        reach(result, app: app)
        XCTAssertEqual(result.label, "comparison_completed")
        let impossible = app.buttons["quality-preset-impossible"]
        reach(impossible, app: app, up: false)
        impossible.tap()
        app.buttons["quality-compare"].tap()
        reach(result, app: app)
        XCTAssertEqual(result.label, "no_verified_match")
        capture("Unknown quietness is not promoted to a verified combined match")
        app.tabBars.buttons["03 · Waktu"].tap()
        XCTAssertTrue(app.buttons["timing-venue"].waitForExistence(timeout: 10))
    }
    func testLikeLearnsOnlySelectedFacetAndReranks() {
        let app = launch()
        app.buttons["quality-preset-soft"].tap()
        app.buttons["quality-compare"].tap()
        reach(app.staticTexts["quality-result"], app: app)
        let ranking = app.buttons["quality-ranking-Kategori"]
        reach(ranking, app: app)
        ranking.tap()
        let like = app.buttons["quality-like-bdt-silent"]
        reach(like, app: app)
        like.tap()
        app.buttons["Membaca di tempat"].tap()
        let summary = app.staticTexts["quality-like-summary"]
        reach(summary, app: app, up: false)
        XCTAssertTrue(summary.label.contains("Membaca di tempat"))
        app.buttons["quality-compare"].tap()
        reach(app.staticTexts["quality-result"], app: app)
        let current = app.buttons["quality-ranking-Gabungan"]
        reach(current, app: app)
        current.tap()
        XCTAssertFalse(app.buttons["quality-like-bdt-silent"].exists)
        capture("Explicit liked facet with identity exclusion")
    }
    func testUnconfirmedNegationRequiresCorrection() {
        let app = launch()
        let field = app.descendants(matching: .any).matching(identifier: "quality-direction").firstMatch
        reach(field, app: app)
        field.tap()
        field.typeText("Saya mau membaca tetapi tidak ingin kopi")
        app.buttons["quality-compare"].tap()
        reach(app.staticTexts["quality-result"], app: app)
        XCTAssertEqual(app.staticTexts["quality-result"].label, "preference_review_required")
        capture("Negation is not silently interpreted by embeddings")
        let correction = app.buttons["quality-preset-avoid"]
        reach(correction, app: app, up: false)
        correction.tap()
        app.buttons["quality-compare"].tap()
        reach(app.staticTexts["quality-result"], app: app)
        XCTAssertEqual(app.staticTexts["quality-result"].label, "comparison_completed")
        let ranking = app.buttons["quality-ranking-Gabungan"]
        reach(ranking, app: app)
        ranking.tap()
        XCTAssertTrue(app.staticTexts["Ruang Baca Hening"].waitForExistence(timeout: 5))
        capture("Structured correction selects a source-supported no-coffee reading room")
    }
}
