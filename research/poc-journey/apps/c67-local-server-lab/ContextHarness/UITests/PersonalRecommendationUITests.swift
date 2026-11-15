import XCTest

@MainActor final class PersonalRecommendationUITests: XCTestCase {
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIApplication().screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0 ..< 9 {
            if element.exists {
                let y = element.frame.midY
                if element.isHittable && y > 190 && y < 780 { return }
                if y <= 190 { app.swipeDown() } else if y >= 780 { app.swipeUp() }
                else if up { app.swipeUp() } else { app.swipeDown() }
            } else if up { app.swipeUp() } else { app.swipeDown() }
        }
    }
    private func tap(_ element: XCUIElement, app: XCUIApplication, up: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        reveal(element, app: app, up: up)
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription, file: file, line: line)
        if element.exists && element.isHittable { element.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap() }
    }
    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--personal-ui-test", "--personal-full-layout"] + (reset ? ["--personal-reset-test"] : [])
        app.launchEnvironment["PERSONAL_TEST_DAY"] = "2026-11-10"
        app.launchEnvironment["PERSONAL_CAMPAIGN_LABEL"] = name + ":v7"
        app.launch()
        if reset {
            XCTAssertTrue(app.buttons["interest-coffee"].waitForExistence(timeout: 10))
            app.buttons["interest-coffee"].tap(); app.buttons["interest-culture"].tap(); app.buttons["interest-outdoors"].tap()
            shot("onboarding-three-interests")
            tap(app.buttons["personal-onboarding-done"], app: app)
        }
        return app
    }
    private func waitForRecommendation(_ app: XCUIApplication, label: String, previous: String?) -> Bool {
        let predicate = NSPredicate { _, _ in
            let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "personal-candidate-")).firstMatch
            let error = app.staticTexts["personal-error"]
            return (candidate.exists && (candidate.value as? String) != previous) || (error.exists && (error.value as? String) != previous)
        }
        let success = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 25) == .completed
        XCTAssertTrue(success, app.debugDescription); shot(label)
        let current = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "personal-candidate-")).firstMatch
        return success && current.exists && (current.value as? String) != previous && !app.staticTexts["personal-error"].exists
    }
    private func runRecommendation(_ app: XCUIApplication, button: XCUIElement, label: String, up: Bool = true) -> Bool {
        for attempt in 0 ..< 2 {
            let old = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "personal-candidate-")).firstMatch, error = app.staticTexts["personal-error"]
            let previous = old.exists ? old.value as? String : error.exists ? error.value as? String : nil
            tap(button, app: app, up: up)
            if waitForRecommendation(app, label: label + "-attempt\(attempt)", previous: previous) { return true }
            XCTAssertTrue(app.staticTexts["personal-error"].exists, "Provider failure must be explicit")
            XCTAssertFalse(app.buttons["personal-candidate-0"].exists, "No non-LLM fallback is allowed")
            // One explicit user-style retry, a new operation recorded separately, never hidden in latency.
        }
        return false
    }
    func testEnglishEmbeddingFixture()throws {
        let app = launch()
        let ready = runRecommendation(app, button: app.buttons["personal-fixture"], label: "english-e5-en-v1")
        XCTAssertTrue(ready); if !ready { return }
        tap(app.buttons["Pengukuran dan batas eksperimen"], app: app)
        let info = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "E5 English inputs en-v1")).firstMatch
        reveal(info, app: app)
        XCTAssertTrue(info.exists, "Actual E5 must report the English input representation")
        shot("english-e5-runtime-and-input-version")
    }
    func testControlledRecommendationCampaignAndProfilePersistence()throws {
        let app = launch()
        for index in 0 ..< 4 {
            let button = app.buttons[index < 2 ? "personal-fixture" : "personal-fixture-unknown"]
            let ok = runRecommendation(app, button: button, label: "controlled-\(index)")
            XCTAssertTrue(ok, app.debugDescription); if !ok { return }
        }
        tap(app.buttons["personal-candidate-0"], app: app, up: false)
        tap(app.buttons["personal-save"], app: app)
        app.tabBars.buttons["Profil"].tap()
        let facets = app.staticTexts["personal-facet-count"]
        XCTAssertTrue(facets.waitForExistence(timeout: 5)); XCTAssertFalse(facets.label.hasPrefix("0 "))
        shot("profile-learned-within-interests")
        app.terminate()
        let restored = launch(reset: false); restored.tabBars.buttons["Profil"].tap()
        XCTAssertEqual(restored.buttons["interest-coffee"].value as? String, "Dipilih")
        XCTAssertEqual(restored.buttons["interest-culture"].value as? String, "Dipilih")
        XCTAssertEqual(restored.buttons["interest-outdoors"].value as? String, "Dipilih")
        let restoredFacets = restored.staticTexts["personal-facet-count"]
        XCTAssertTrue(restoredFacets.exists); XCTAssertFalse(restoredFacets.label.hasPrefix("0 "))
        shot("profile-restored-after-relaunch")
    }
    func testInvalidContextShowsErrorWithoutCandidates()throws {
        let app = launch()
        let field = app.textFields["personal-area"]; field.tap()
        if let value = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        app.buttons["personal-recommend"].tap()
        XCTAssertTrue(app.staticTexts["personal-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["personal-candidate-0"].exists); shot("invalid-context-no-candidates")
    }
    func testLiveRecommendationCampaignAndPlan()throws {
        let app = launch()
        for index in 0 ..< 3 {
            let ok = runRecommendation(app, button: app.buttons["personal-recommend"], label: "live-recommendation-\(index)", up: false)
            XCTAssertTrue(ok, app.debugDescription); if !ok { return }
        }
        for index in 0 ..< 3 {
            let candidate: XCUIElement
            if index == 0 {
                candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "personal-candidate-", "Loko Cafe")).firstMatch
            } else if index == 1 {
                candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "personal-candidate-", "Taman Pandang Istana")).firstMatch
            } else {
                // The development run exposed Monas' internal museum matching Fatahillah (4.7 km).
                // Select a different issued museum whose identity can be independently confirmed.
                candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@ AND NOT label CONTAINS[c] %@", "personal-candidate-", "Museum", "Sejarah Nasional")).firstMatch
            }
            tap(candidate, app: app)
            shot("live-candidate-detail-\(index)")
            tap(app.buttons[index == 0 ? "personal-select-required" : "personal-select-optional"], app: app)
            XCTAssertTrue(app.buttons["personal-apple-0"].waitForExistence(timeout: 30), app.debugDescription)
            shot("live-apple-confirmation-\(index)")
            XCTAssertTrue(app.buttons["personal-apple-0"].isEnabled, "Distant identity must be rejected, not auto-confirmed")
            app.buttons["personal-apple-0"].tap()
        }
        app.tabBars.buttons["Rencana"].tap()
        let origin = app.textFields["personal-origin-query"]
        XCTAssertTrue(origin.waitForExistence(timeout: 5)); origin.tap(); origin.typeText("Hotel Indonesia Kempinski Jakarta")
        app.buttons["personal-origin-search"].tap()
        XCTAssertTrue(app.buttons["personal-origin-result-0"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["personal-origin-result-0"].tap()
        XCTAssertTrue(app.buttons["personal-apple-0"].waitForExistence(timeout: 30), app.debugDescription)
        shot("live-origin-apple-confirmation"); app.buttons["personal-apple-0"].tap()
        XCTAssertTrue(app.staticTexts["personal-chosen-origin"].waitForExistence(timeout: 5))
        tap(app.buttons["personal-plan"], app: app)
        XCTAssertTrue(app.staticTexts["personal-plan-status"].waitForExistence(timeout: 180), app.debugDescription)
        let result = app.staticTexts["personal-plan-status"]
        reveal(result, app: app)
        XCTAssertTrue(result.label.hasPrefix("candidate"), app.debugDescription)
        shot("live-itinerary-required-and-optional")
    }
}
