import XCTest

/// Frozen synthetic personas; completed test != accepted recommendation.
@MainActor final class SyntheticUserUITests: XCTestCase {
    private var journal: [[String: Any]] = []
    private func record(_ name: String, _ app: XCUIApplication, extra: [String: Any] = [:]) {
        var entry = extra; entry["step"] = name
        entry["texts"] = app.staticTexts.allElementsBoundByIndex.map(\.label)
        entry["buttons"] = app.buttons.allElementsBoundByIndex.map{["id": $0.identifier, "label": $0.label, "enabled": String($0.isEnabled)]}
        journal.append(entry)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func export(_ id: String) {
        let data = try! JSONSerialization.data(withJSONObject: ["persona": id, "journal": journal], options: [.prettyPrinted, .sortedKeys])
        let item = XCTAttachment(data: data, uniformTypeIdentifier: "public.json"); item.name = id + "-synthetic-observations"; item.lifetime = .keepAlways; add(item)
    }
    private func tap(_ el: XCUIElement, _ app: XCUIApplication, up: Bool = true) -> Bool {
        for _ in 0 ..< 10 {
            let top = max(120, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 8 : 120)
            let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 12 : app.frame.maxY - 40
            if el.exists && el.isEnabled && el.isHittable && el.frame.midY > top && el.frame.midY < bottom {
                el.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap(); return true
            }
            if el.exists && el.frame.midY < top { app.swipeDown() }
            else if el.exists && el.frame.midY >= bottom { app.swipeUp() }
            else if up { app.swipeUp() } else { app.swipeDown() }
        }
        return false
    }
    private func chooseMenu(_ prefix: String, _ value: String, _ app: XCUIApplication) -> Bool {
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        guard tap(picker, app, up: false)else{return false}
        return tap(app.buttons[value], app)
    }
    private func fill(_ field: XCUIElement, _ value: String, _ app: XCUIApplication) -> Bool {
        guard field.waitForExistence(timeout: 5)else{return false}
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let old = field.value as? String ?? ""
        let length = old.contains("Jakarta") ? old.count : 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: length) + value)
        return (field.value as? String) == value
    }
    private func campaign(id: String, interests: [String], pace: String, area: String, start: String, end: String, origin: String, primary: String, secondary: String, afternoon: Bool = false)throws {
        let app = XCUIApplication(); app.launchArguments = ["--personal-ui-test", "--personal-reset-test", "--personal-full-layout"]
        app.launchEnvironment = ["PERSONAL_TEST_DAY": "2026-11-10", "PERSONAL_CAMPAIGN_LABEL": "synthetic-user-" + id + (id == "U3" ? "-frozen-v3" : "-frozen-v1")]
        app.launch(); defer{export(id)}
        XCTAssertTrue(app.buttons["interest-" + interests[0]].waitForExistence(timeout: 10))
        for interest in interests { app.buttons["interest-" + interest].tap() }
        if pace == "Santai" { app.segmentedControls.buttons["Santai"].tap() }
        XCTAssertTrue(tap(app.buttons["personal-onboarding-done"], app))
        guard fill(app.textFields["personal-area"], area, app), chooseMenu("Mulai WIB,", start, app), chooseMenu("Selesai WIB,", end, app)else {record(id + "-input-harness-error", app); XCTFail("Frozen input could not be applied"); return}
        record(id + "-frozen-input", app)
        var ready = false
        for attempt in 1 ... 2 {
            XCTAssertTrue(tap(app.buttons["personal-recommend"], app, up: false))
            let done = NSPredicate{_, _ in app.buttons["personal-candidate-0"].exists || app.staticTexts["personal-error"].exists}
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: done, object: app)], timeout: 25), .completed)
            record(id + "-recommendation-\(attempt)", app)
            if app.buttons["personal-candidate-0"].exists {ready = true; break}
        }
        guard ready else {record(id + "-unavailable", app); return}
        // Inspect all supplied cards before selecting; do not tune the request from results.
        var cards: [(Int, String)] = []
        for index in 0 ..< 6 {
            let card = app.buttons["personal-candidate-\(index)"]
            guard card.exists else {continue}
            cards.append((index, card.label))
            guard tap(card, app)else{XCTFail("Cannot open issued card"); return}
            XCTAssertTrue(app.buttons["Tutup"].waitForExistence(timeout: 5))
            record(id + "-detail-\(index)-top", app)
            app.swipeUp(); record(id + "-detail-\(index)-bottom", app)
            app.buttons["Tutup"].tap()
        }
        guard let first = cards.first(where: {$0.1.contains(primary)})else{record(id + "-missing-primary-category", app); return}
        let second = cards.first(where: {$0.0 != first.0 && $0.1.contains(secondary)})
        let selections = [first] + (second.map{[$0]} ?? [])
        record(id + "-selection-frozen-before-route", app, extra: ["selected": selections.map{["card": $0.0, "label": $0.1]}, "criterion": "First supported card per requested category; unresolved detailed needs stay conditional"])
        var confirmed = 0
        for (position, item)in selections.enumerated() {
            XCTAssertTrue(tap(app.buttons["personal-candidate-\(item.0)"], app, up: false))
            XCTAssertTrue(tap(app.buttons[position == 0 ? "personal-select-required" : "personal-select-optional"], app))
            let done = NSPredicate{_, _ in app.buttons["personal-apple-0"].exists || app.staticTexts["personal-error"].exists}
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: done, object: app)], timeout: 30), .completed)
            record(id + "-identity-\(position)", app)
            let apple = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND enabled == true", "personal-apple-")).firstMatch
            guard apple.exists else {
                record(id + "-identity-blocked-\(position)", app)
                if app.buttons["Batal"].exists {app.buttons["Batal"].tap()}
                if position == 0{return}else{continue}
            }
            XCTAssertTrue(tap(apple, app)); confirmed += 1
        }
        app.tabBars.buttons["Rencana"].tap()
        guard fill(app.textFields["personal-origin-query"], origin, app)else{record(id + "-origin-input-error", app); XCTFail("Origin input"); return}
        XCTAssertTrue(tap(app.buttons["personal-origin-search"], app))
        XCTAssertTrue(app.buttons["personal-origin-result-0"].waitForExistence(timeout: 30))
        XCTAssertTrue(tap(app.buttons["personal-origin-result-0"], app))
        XCTAssertTrue(app.buttons["personal-apple-0"].waitForExistence(timeout: 30)); record(id + "-origin-identity", app)
        // Origin must be the selected mall itself, not a tenant whose name contains the mall.
        let apple = id == "U3" ? app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@ AND enabled == true", "personal-apple-", "Plaza Blok M,")).firstMatch : app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND enabled == true", "personal-apple-")).firstMatch
        guard apple.exists else{record(id + "-origin-identity-blocked", app); return}
        XCTAssertTrue(tap(apple, app))
        // U2 second activity is45 min and prefers15–16 start; U3 defaults60/60 are its frozen dwell.
        if id == "U2" && confirmed > 1 {
            let duration = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Durasi,")).element(boundBy: 1)
            if tap(duration, app) {XCTAssertTrue(tap(app.buttons["45 menit"], app))}else{record(id + "-duration-control-error", app); XCTFail("Duration control"); return}
            if afternoon {
                let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "Utamakan mulai 15–16 WIB")).element(boundBy: 1)
                XCTAssertTrue(tap(toggle, app))
            }
        }
        let stepper = app.steppers.firstMatch
        guard tap(stepper.buttons["Decrement"], app)else{record(id + "-waiting-control-error", app); XCTFail("Waiting control"); return}
        for _ in 0 ..< 2{stepper.buttons["Decrement"].tap()}
        record(id + "-plan-input", app, extra: ["confirmedStops": confirmed])
        XCTAssertTrue(tap(app.buttons["personal-plan"], app))
        let done = NSPredicate{_, _ in app.staticTexts["personal-plan-status"].exists || app.staticTexts["personal-error"].exists}
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: done, object: app)], timeout: 190), .completed)
        record(id + "-plan-result", app)
        app.swipeUp(); record(id + "-plan-result-bottom", app)
    }
    func testU2ArtsAndArchitecture()throws{try campaign(id: "U2", interests: ["arts", "architecture"], pace: "Seimbang", area: "Kota Tua Jakarta", start: "13.00", end: "19.00", origin: "Stasiun Jakarta Kota", primary: "Seni dan kreativitas", secondary: "Arsitektur", afternoon: true)}
    func testU3VegetarianAndShopping()throws{try campaign(id: "U3", interests: ["food", "shopping"], pace: "Santai", area: "Blok M Jakarta", start: "11.00", end: "16.00", origin: "Blok M Plaza Jakarta", primary: "Kuliner", secondary: "Belanja")}
}
