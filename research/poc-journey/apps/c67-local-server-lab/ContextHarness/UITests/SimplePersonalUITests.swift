import XCTest

@MainActor final class SimplePersonalUITests: XCTestCase {
    private let app = XCUIApplication()
    private func shot(_ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func wait(_ seconds: Double, for condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate{_, _ in condition()}, object: nil)], timeout: seconds) == .completed
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line)throws {
        for _ in 0 ..< 5 {
            if element.exists && element.isHittable && element.frame.midY > 130 && element.frame.midY < app.frame.height - 95 { break }
            if element.exists && element.frame.midY < 130 {app.swipeDown()} else {app.swipeUp()}
        }
        guard element.exists && element.isHittable else {
            XCTFail(app.debugDescription, file: file, line: line); throw Stop.notVisible
        }
        element.tap()
    }
    private enum Stop: Error {case notVisible}

    func testDiscoverMoreKeepsParkThenAutomaticWeatherAndAppleRoute()throws {
        let date = DateFormatter()
        date.calendar = Calendar(identifier: .gregorian); date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = TimeZone(identifier: "Asia/Jakarta"); date.dateFormat = "yyyy-MM-dd"
        // Use a date inside the actual forecast horizon.
        app.launchEnvironment["PERSONAL_TEST_DAY"] = date.string(from: Date().addingTimeInterval(86400))
        app.launchEnvironment["PERSONAL_CAMPAIGN_LABEL"] = ProcessInfo.processInfo.environment["SIMPLE_CAMPAIGN"] ?? "simple-flow-v1"
        app.launchArguments = ["--personal-ui-test", "--personal-reset-test"]; app.launch()

        let coffee = app.buttons["interest-coffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 10))
        coffee.tap(); app.buttons["interest-culture"].tap(); app.buttons["interest-outdoors"].tap()
        try tap(app.buttons["personal-onboarding-done"])
        XCTAssertTrue(app.tabBars.buttons["Jelajah"].exists); XCTAssertTrue(app.tabBars.buttons["Rencana"].exists)

        let find = app.buttons["simple-find"]
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "simple-candidate-"))
        let error = app.descendants(matching: .any).matching(identifier: "simple-discovery-error").firstMatch
        for _ in 0 ..< 2 {
            XCTAssertTrue(find.waitForExistence(timeout: 10))
            try tap(find)
            _ = wait(28, for: {cards.firstMatch.exists || (error.exists && find.isEnabled)})
            if cards.firstMatch.exists {break}
        }
        guard cards.firstMatch.exists else {shot("discovery-failed"); XCTFail(app.debugDescription); return}
        shot("01-jelajah")
        let park = cards.matching(NSPredicate(format: "label CONTAINS[c] %@", "Taman Pandang Istana")).firstMatch
        try tap(park)
        try tap(app.buttons["personal-select-required"])
        let parkApple = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "personal-apple-", "Taman Pandang")).firstMatch
        guard parkApple.waitForExistence(timeout: 25), parkApple.isEnabled else {shot("park-identity-failed"); XCTFail(app.debugDescription); return}
        try tap(parkApple)

        let review = app.buttons["simple-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 8)); XCTAssertTrue(review.label.contains("1"))
        let before = cards.allElementsBoundByIndex.map(\.identifier)
        let more = app.buttons["simple-more"]
        for _ in 0 ..< 2 {
            try tap(more)
            _ = wait(28, for: {cards.allElementsBoundByIndex.contains{ !before.contains($0.identifier)} || (error.exists && more.isEnabled)})
            if cards.allElementsBoundByIndex.contains(where: { !before.contains($0.identifier)}) {break}
        }
        guard cards.allElementsBoundByIndex.contains(where: { !before.contains($0.identifier)}) else {
            shot("more-failed"); XCTFail(app.debugDescription); return
        }
        XCTAssertTrue(review.exists && review.label.contains("1"))
        shot("02-cari-lainnya-pilihan-tetap")
        review.tap()
        let selected = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Taman Pandang Istana")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cuaca otomatis untuk kegiatan luar ruang"].exists)
        XCTAssertFalse(app.switches["Sesuaikan dengan hujan"].exists)
        try tap(app.buttons["simple-origin"])
        let query = app.textFields["personal-origin-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("Hotel Indonesia Kempinski Jakarta")
        app.buttons["personal-origin-search"].tap()
        let origin = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "personal-origin-result-", "Kempinski")).firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 25))
        try tap(origin)
        let originApple = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "personal-apple-", "Kempinski")).firstMatch
        guard originApple.waitForExistence(timeout: 25), originApple.isEnabled else {shot("origin-identity-failed"); XCTFail(app.debugDescription); return}
        try tap(originApple)
        let plan = app.buttons["personal-plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 8)); try tap(plan)
        let result = app.staticTexts["personal-plan-status"]
        guard result.waitForExistence(timeout: 140), result.label.hasPrefix("1 tujuan") else {
            shot("plan-failed"); XCTFail(app.debugDescription); return
        }
        let ready = app.staticTexts["simple-map-route-ready"]
        if !ready.waitForExistence(timeout: 45) {
            shot("map-incomplete"); XCTFail("Ruas Apple Maps belum lengkap: " + app.debugDescription); return
        }
        XCTAssertTrue(app.descendants(matching: .any)["simple-apple-map"].exists)
        XCTAssertTrue(app.buttons["simple-apple-map"].exists)
        XCTAssertFalse(app.buttons["Buka ruas pertama di Apple Maps"].exists)
        shot("03-rencana-dan-rute-apple-maps")
    }

    func testLiveSunsetMomentAtPantaiIndah() throws {
        let date = DateFormatter()
        date.calendar = Calendar(identifier: .gregorian)
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = TimeZone(identifier: "Asia/Jakarta")
        date.dateFormat = "yyyy-MM-dd"
        let testEnvironment = ProcessInfo.processInfo.environment
        app.launchEnvironment["PERSONAL_TEST_DAY"] = testEnvironment["C67_MOMENT_TEST_DAY"] ?? date.string(from: Date().addingTimeInterval(86400))
        app.launchEnvironment["PERSONAL_CAMPAIGN_LABEL"] = testEnvironment["C67_MOMENT_TEST_LABEL"] ?? "sunset-live-simulator"
        app.launchArguments = ["--personal-ui-test", "--personal-reset-test"]
        app.launch()
        let outdoors = app.buttons["interest-outdoors"]
        XCTAssertTrue(outdoors.waitForExistence(timeout: 10))
        outdoors.tap()
        try tap(app.buttons["personal-onboarding-done"])
        try tap(app.buttons["simple-trip"])
        let area = app.textFields["simple-area"]
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        area.tap()
        if let old = area.value as? String { area.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        area.typeText("Ancol Jakarta")
        let time = app.buttons["simple-start-time"]
        try tap(time)
        let late = app.buttons["16.30"]
        XCTAssertTrue(late.waitForExistence(timeout: 5), app.debugDescription)
        late.tap()
        app.buttons["Simpan"].tap()

        let find = app.buttons["simple-find"]
        let beach = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                                                     "simple-candidate-", "Pantai Indah Ancol")).firstMatch
        let error = app.descendants(matching: .any).matching(identifier: "simple-discovery-error").firstMatch
        for _ in 0 ..< 2 {
            try tap(find)
            _ = wait(28, for: { beach.exists || (error.exists && find.isEnabled) })
            if beach.exists { break }
        }
        try tap(beach)
        try tap(app.buttons["personal-select-required"])
        let appleBeach = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH[c] %@",
                                                          "personal-apple-", "Pantai Indah")).firstMatch
        XCTAssertTrue(appleBeach.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(appleBeach.isEnabled)
        try tap(appleBeach)
        let review = app.buttons["simple-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        review.tap()
        try tap(app.buttons["simple-origin"])
        let query = app.textFields["personal-origin-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 8))
        query.tap()
        query.typeText("Mercure Convention Center Ancol Jakarta")
        app.buttons["personal-origin-search"].tap()
        let origin = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                                                      "personal-origin-result-", "Mercure")).firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 25))
        try tap(origin)
        let appleOrigin = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                                                           "personal-apple-", "Mercure")).firstMatch
        XCTAssertTrue(appleOrigin.waitForExistence(timeout: 25))
        try tap(appleOrigin)

        try tap(app.buttons["personal-plan"])
        let result = app.staticTexts["personal-plan-status"]
        XCTAssertTrue(result.waitForExistence(timeout: 120), app.debugDescription)
        XCTAssertTrue(result.label.hasPrefix("1 tujuan"), app.debugDescription)
        let moment = app.staticTexts["personal-trip-moment"]
        guard moment.waitForExistence(timeout: 10) else {
            shot("pantai-indah-rencana-tanpa-momen")
            XCTFail("The active forecast/schedule did not produce the expected sunset highlight.")
            return
        }
        XCTAssertTrue(moment.label.contains("Pantai Indah Ancol"))
        XCTAssertTrue(app.links["Sumber lokasi"].exists)
        let ready = app.staticTexts["simple-map-route-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 45), app.debugDescription)
        shot("pantai-indah-momen-dan-rute")
        try verifyInteractiveRoute()
    }

    private func verifyInteractiveRoute() throws {
        let preview = app.buttons["simple-apple-map"]
        XCTAssertFalse(app.buttons["Buka ruas pertama di Apple Maps"].exists)
        try tap(preview)
        let heading = app.navigationBars["Peta itinerary"]
        XCTAssertTrue(heading.waitForExistence(timeout: 12), app.debugDescription)
        let map = app.descendants(matching: .any)["personal-route-detail-map"]
        XCTAssertTrue(map.exists)
        let first = app.buttons["personal-route-leg-0"]
        let second = app.buttons["personal-route-leg-1"]
        let firstBadge = app.buttons["personal-route-badge-0"]
        let secondBadge = app.buttons["personal-route-badge-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertTrue(second.exists)
        XCTAssertTrue(firstBadge.exists)
        XCTAssertTrue(secondBadge.exists)
        shot("peta-semua-ruas")

        try tap(second)
        XCTAssertTrue(wait(5, for: { (second.value as? String) == "Disorot" }))
        XCTAssertFalse(firstBadge.exists)
        XCTAssertTrue(secondBadge.exists)
        shot("peta-sorot-ruas-pulang")

        let all = app.buttons["personal-route-all"]
        all.tap()
        XCTAssertTrue(wait(5, for: { firstBadge.exists && secondBadge.exists }))
        firstBadge.tap()
        XCTAssertTrue(wait(5, for: { (first.value as? String) == "Disorot" }))
        XCTAssertFalse(secondBadge.exists)
        XCTAssertEqual(app.state, .runningForeground)
        shot("peta-sorot-dari-nomor")

        app.buttons["personal-route-close"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        XCTAssertFalse(heading.exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

}
