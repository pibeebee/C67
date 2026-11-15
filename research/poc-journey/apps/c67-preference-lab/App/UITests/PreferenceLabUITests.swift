import XCTest

final class PreferenceLabUITests: XCTestCase {
    @MainActor func fresh(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test", "--reset-state", "--illustrations"] + extra; app.launch(); return app
    }
    @MainActor func startReading(_ app: XCUIApplication) {
        app.buttons["interest-reading"].tap(); app.buttons["begin-exploring"].tap()
        XCTAssertTrue(app.staticTexts["clarification-title"].waitForExistence(timeout: 10))
    }
    @MainActor func testClarifySaveAndRestore() {
        let app = fresh(); startReading(app)
        let save = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "save-")).firstMatch
        save.tap(); XCTAssertTrue(app.staticTexts["saved-count"].label.contains("1"))
        app.buttons["choice-reading-onsite"].tap()
        XCTAssertTrue(app.staticTexts["preference-summary"].label.contains("Membaca buku sendiri"))
        XCTAssertTrue(app.staticTexts["saved-count"].label.contains("1"))
        app.terminate(); app.launchArguments = ["--ui-test", "--illustrations"]; app.launch()
        XCTAssertTrue(app.staticTexts["preference-summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["saved-count"].label.contains("1"))
        app.buttons["open-summary"].tap(); app.buttons["undo-change"].tap(); app.buttons["Selesai"].tap()
        XCTAssertFalse(app.staticTexts["preference-summary"].exists)
        XCTAssertTrue(app.staticTexts["saved-count"].label.contains("1"))
    }
    @MainActor func testSkipAndLocalOnly() {
        let app = fresh(); startReading(app); app.buttons["skip-question"].tap()
        XCTAssertFalse(app.staticTexts["clarification-title"].exists)
        XCTAssertTrue(app.staticTexts["saved-count"].exists)
    }
    @MainActor func testNewTripDoesNotCarryTemporaryPreference() {
        let app = fresh(); startReading(app); app.buttons["choice-reading-buy"].tap()
        app.buttons["open-summary"].tap(); app.buttons["new-trip"].tap(); app.buttons["Selesai"].tap()
        XCTAssertFalse(app.staticTexts["preference-summary"].exists)
        XCTAssertTrue(app.staticTexts["clarification-title"].exists)
    }
    @MainActor func testE5Audit() {
        let app = fresh(["--e5-audit"])
        XCTAssertTrue(app.staticTexts["E5 audit complete"].waitForExistence(timeout: 180))
    }
    @MainActor func testLiveAdvisorAndPlaces() throws {
        guard ProcessInfo.processInfo.environment["PREFERENCE_LIVE_UI"] == "1" else { throw XCTSkip("Opt-in live provider verification") }
        let app = fresh(); startReading(app)
        app.buttons["ask-ai"].tap(); app.alerts.buttons["Gunakan AI"].tap()
        let status = app.staticTexts["advisor-status"]
        let ready = NSPredicate(format: "label CONTAINS %@", "siap")
        expectation(for: ready, evaluatedWith: status); waitForExpectations(timeout: 20)
        app.buttons["choice-reading-onsite"].tap(); app.buttons["open-summary"].tap()
        let search = app.buttons["search-live-places"]
        for _ in 0 ..< 4 where !search.isHittable { app.swipeUp() }
        search.tap()
        XCTAssertTrue(app.staticTexts["google-attribution"].waitForExistence(timeout: 20))
        for _ in 0 ..< 3 where !app.staticTexts.matching(identifier: "live-place-name").firstMatch.exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts.matching(identifier: "live-place-name").firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.staticTexts.matching(identifier: "live-place-name").count, 0)
    }
    @MainActor func testRealPlacesAndCombinedPreferenceKeepSelection() throws {
        guard ProcessInfo.processInfo.environment["PREFERENCE_LIVE_UI"] == "1" else { throw XCTSkip("Opt-in real discovery") }
        let app = XCUIApplication(); app.launchArguments = ["--ui-test", "--reset-state", "--google-places"]; app.launch()
        startReading(app); app.buttons["choice-reading-onsite"].tap()
        let first = app.staticTexts.matching(identifier: "live-place-name").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["Contoh pengalaman ilustratif"].exists)
        let save = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "save-live-")).firstMatch
        for _ in 0 ..< 3 where !save.isHittable { app.swipeUp() }
        save.tap()
        for _ in 0 ..< 4 where !app.buttons["Minat"].isHittable { app.swipeDown() }
        app.buttons["Minat"].tap(); app.buttons["interest-coffee"].tap(); app.buttons["begin-exploring"].tap()
        app.buttons["choice-coffee-reading-together"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 25))
        XCTAssertTrue(app.staticTexts["saved-count"].label.contains("1"))
        let checks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "place-checks-")).firstMatch
        for _ in 0 ..< 3 where !checks.isHittable { app.swipeUp() }
        XCTAssertTrue(checks.isHittable)
        checks.tap()
        let unknown = app.staticTexts.matching(NSPredicate(format: "label == %@", "Belum diketahui")).firstMatch
        XCTAssertTrue(unknown.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Real discovery with retained selection"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testRealPaginationKeepsSavedPlace() throws {
        guard ProcessInfo.processInfo.environment["PREFERENCE_LIVE_UI"] == "1" else { throw XCTSkip("Opt-in real pagination") }
        let app = XCUIApplication(); app.launchArguments = ["--ui-test", "--reset-state", "--google-places"]; app.launch()
        startReading(app); app.buttons["choice-reading-buy"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "live-place-name").firstMatch.waitForExistence(timeout: 25))
        let save = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "save-live-")).firstMatch
        for _ in 0 ..< 3 where !save.isHittable { app.swipeUp() }; save.tap()
        let count = app.staticTexts["live-count"]
        let before = count.label
        let more = app.buttons["more-live-places"]
        for _ in 0 ..< 12 where !more.isHittable { app.swipeUp() }
        guard more.exists else { throw XCTSkip("Provider returned no continuation") }
        more.tap()
        // The header leaves the accessibility viewport while the footer is visible.
        for _ in 0 ..< 12 {
            if count.exists && count.isHittable { break }
            app.swipeDown()
        }
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: count); waitForExpectations(timeout: 25)
        XCTAssertTrue(app.staticTexts["saved-count"].label.contains("1"))
    }
    @MainActor func testEvidenceCatalogKeepsSelectionAndExplainsUnknown() throws {
        guard ProcessInfo.processInfo.environment["PREFERENCE_CATALOG_UI"] == "1" else {
            throw XCTSkip("Requires an activated real evidence catalogue")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-state"]
        app.launch()
        startReading(app)
        app.buttons["choice-reading-onsite"].tap()
        let first = app.staticTexts.matching(identifier: "catalog-place-name").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let save = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "save-catalog-")).firstMatch
        for _ in 0 ..< 3 where !save.isHittable { app.swipeUp() }
        save.tap()
        let evidence = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "catalog-evidence-")).firstMatch
        evidence.tap()
        // DisclosureGroup propagates its identifier to content on this runtime.
        // Assert the visible meaning rather than a child ID overridden by SwiftUI.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Belum diketahui")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Informasi untuk memastikan kegiatan ini belum tersedia."].exists)
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Catalogue evidence explains missing reading permission"
        detail.lifetime = .keepAlways
        add(detail)
        for _ in 0 ..< 5 where !app.staticTexts["saved-count"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["saved-count"].label.contains("1"))
        app.buttons["open-summary"].tap()
        XCTAssertTrue(app.buttons["Batalkan perubahan terakhir"].exists)
        app.buttons["Selesai"].tap()
        app.terminate()
        app.launchArguments = ["--ui-test"]
        app.launch()
        XCTAssertTrue(app.staticTexts["saved-count"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["saved-count"].label.contains("1"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Evidence catalogue with retained selection"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor func testConfiguredAdvisorChoosesQuestion() throws {
        guard ProcessInfo.processInfo.environment["PREFERENCE_CATALOG_UI"] == "1" else {
            throw XCTSkip("Opt-in configured provider verification")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-state"]
        app.launch()
        startReading(app)
        app.buttons["ask-ai"].tap()
        app.alerts.buttons["Gunakan AI"].tap()
        let status = app.staticTexts["advisor-status"]
        expectation(for: NSPredicate(format: "label == %@", "Klarifikasi siap"), evaluatedWith: status)
        waitForExpectations(timeout: 40)
        XCTAssertTrue(app.buttons["choice-reading-onsite"].exists)
        XCTAssertTrue(app.buttons["choice-reading-buy"].exists)
        XCTAssertFalse(app.staticTexts["preference-summary"].exists)
    }
}
