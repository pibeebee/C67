import CoreLocation
import XCTest

final class PocketEngineUITests: XCTestCase {
    @MainActor func testFirstItineraryKeepsUnknownPlacesAndSavesTheRecommendation() {
        continueAfterFailure = false
        let app = openFixtureRecommendations()
        for name in ["Fixture Japanese 1", "Fixture Japanese 2", "Fixture Unknown Hours"] {
            let place = app.buttons[name]
            scrollToTripControl(place, in: app)
            place.tap()
        }
        app.buttons["recommendationsNext"].tap()
        let mainSpot = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                        "mainSpot-", "Fixture Japanese 2")).firstMatch
        XCTAssertTrue(mainSpot.waitForExistence(timeout: 5))
        mainSpot.tap()
        app.buttons["Next"].tap()

        let review = app.navigationBars["Itinerary"]
        if !review.waitForExistence(timeout: 15) {
            capture(app, "First itinerary failure")
            XCTFail(app.debugDescription)
            return
        }
        XCTAssertFalse(app.navigationBars["Visit availability"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Unknown Hours"].exists)
        XCTAssertFalse(app.staticTexts["Places not in this plan"].exists)
        capture(app, "Untimed itinerary keeps every selected place")
        app.buttons["itineraryDepartureEdit"].tap()
        app.buttons["End point"].tap()
        XCTAssertTrue(app.navigationBars["End point"].waitForExistence(timeout: 5))
        app.navigationBars["End point"].buttons["Cancel"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Driving times are estimates")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Synthetic experience order")).firstMatch.exists)
        XCTAssertTrue(app.buttons["itineraryStartNow"].exists)

        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2 min")).firstMatch.exists)
        let first = app.staticTexts["Fixture Japanese 1"]
        let second = app.staticTexts["Fixture Japanese 2"]
        let handles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "itineraryReorder-"))
        let source = handles.element(boundBy: 0)
        let target = handles.element(boundBy: 1)
        XCTAssertTrue(source.isHittable && target.isHittable)
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.2, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: -2, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 1)
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            first.exists && second.exists && second.frame.midY < first.frame.midY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 20), .completed)

        let save = app.buttons["Save this trip"]
        scrollToTripControl(save, in: app)
        save.tap()
        XCTAssertTrue(app.alerts["Save Itinerary"].waitForExistence(timeout: 5))
        app.alerts["Save Itinerary"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Pocket integration test"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Unknown Hours"].exists)
        XCTAssertLessThan(second.frame.midY, first.frame.midY)
    }

    @MainActor func testUnknownActivityDoesNotBlockRecommendation() {
        continueAfterFailure = false
        let app = openFixtureRecommendations()
        let unknown = app.buttons["Fixture Unknown Hours"]
        scrollToTripControl(unknown, in: app)
        unknown.tap()
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.navigationBars["Visit availability"].exists)
        let visit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "itineraryEdit-")).firstMatch
        XCTAssertTrue(visit.waitForExistence(timeout: 5))
        XCTAssertTrue((visit.value as? String)?.hasPrefix("≈ ") == true)
        let start = app.buttons["itineraryStartNow"]
        scrollToTripControl(start, in: app)
        start.tap()
        XCTAssertTrue(app.buttons["confirmTripArrival"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "Started from the itinerary review")
    }

    @MainActor func testUntimedRenameValidatesNameAndCancelKeepsTheRecommendation() {
        continueAfterFailure = false
        let app = openFixtureRecommendations()
        let unknown = app.buttons["Fixture Unknown Hours"]
        scrollToTripControl(unknown, in: app)
        unknown.tap()
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 15))

        let save = app.buttons["Save this trip"]
        scrollToTripControl(save, in: app)
        save.tap()
        let alert = app.alerts["Save Itinerary"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        replaceTripName(field, with: "")
        XCTAssertFalse(alert.buttons["Save"].isEnabled)
        replaceTripName(field, with: String(repeating: "A", count: 121))
        XCTAssertFalse(alert.buttons["Save"].isEnabled)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].exists)

        scrollToTripControl(save, in: app)
        save.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Pocket integration test")
        replaceTripName(field, with: "Weekend coffee and taman 2026")
        XCTAssertTrue(alert.buttons["Save"].isEnabled)
        alert.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Weekend coffee and taman 2026"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Fixture Unknown Hours"].exists)
        scrollToTripControl(save, in: app)
        XCTAssertEqual(save.label, "Go Trip")
        capture(app, "Untimed exact rename after validation and cancel")
    }

    @MainActor private func openFixtureRecommendations() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash", "--pocket-integration-fixture"]
        app.launch()
        openTripMenu(app)
        app.buttons["Get Recommendations"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.navigationBars["Recommendations"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func capture(_ app: XCUIApplication, _ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testLivePocketPlansFromRealJakartaDiscovery() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["C67_LIVE_ACCEPTANCE"] == "1")
        continueAfterFailure = false
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: -6.2443, longitude: 106.7985))
        defer { XCUIDevice.shared.location = nil }
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash"]
        app.launch()
        if app.alerts.firstMatch.waitForExistence(timeout: 2) {
            let allow = app.alerts.buttons["Allow While Using App"]
            if allow.exists { allow.tap() }
        }
        let current = app.buttons["Starting point: Current device position"]
        if !current.waitForExistence(timeout: 4) {
            let change = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Starting point:")).firstMatch
            XCTAssertTrue(change.waitForExistence(timeout: 10), app.debugDescription)
            change.tap()
            let picker = app.navigationBars["Starting point"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("Blok M MRT Jakarta\n")
            let result = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS %@", "Blok M", "-6.24")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 20), app.debugDescription)
            result.tap()
            XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 5))
        }

        openTripMenu(app)
        app.buttons["Get Recommendations"].tap()
        XCTAssertTrue(app.buttons["Nature"].waitForExistence(timeout: 5))
        app.buttons["Nature"].tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Recommendations"].waitForExistence(timeout: 20))
        let bendera = app.buttons["Taman Bendera Pusaka"]
        if bendera.waitForExistence(timeout: 5), bendera.isHittable {
            bendera.tap()
        } else {
            let lookup = app.buttons.matching(identifier: "Search for a place").allElementsBoundByIndex.first(where: \.isHittable)
            let openLookup = try XCTUnwrap(lookup)
            openLookup.tap()
            let search = app.textFields["addPlacesSearch"]
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("Taman Bendera Pusaka")
            let result = app.buttons["Add Taman Bendera Pusaka"]
            XCTAssertTrue(result.waitForExistence(timeout: 20), app.debugDescription)
            result.tap()
            app.buttons["addPlacesNext"].tap()
        }
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        let review = app.navigationBars["Itinerary"]
        if !review.waitForExistence(timeout: 480) {
            capture(app, "Live Pocket planning result")
            XCTFail(app.debugDescription)
            return
        }
        XCTAssertTrue(app.staticTexts["Taman Bendera Pusaka"].exists)
        capture(app, "Live first itinerary from Jakarta discovery")

    }

    @MainActor func testRuntimeFiveSelectedPlacesUseLunaOrdering() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["C67_RUNTIME_ACCEPTANCE"] == "1")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash", "--pocket-runtime-acceptance"]
        for key in ["C67_LIVE_URL", "C67_LIVE_READ_TOKEN", "C67_LIVE_INPUT"] {
            app.launchEnvironment[key] = try XCTUnwrap(env[key])
        }
        app.launch()
        openTripMenu(app)
        app.buttons["Add Specific Place"].tap()
        XCTAssertTrue(app.buttons["addPlacesNext"].waitForExistence(timeout: 10))
        app.buttons["addPlacesNext"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        let review = app.navigationBars["Itinerary"]
        let terminal = NSPredicate { _, _ in
            review.exists || app.buttons["Try again"].exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "could not finish")).firstMatch.exists
        }
        let completed = XCTNSPredicateExpectation(predicate: terminal, object: nil)
        let state = XCTWaiter.wait(for: [completed], timeout: 480)
        if state != .completed || !review.exists {
            capture(app, "Live five-place research failure")
            XCTFail(app.debugDescription)
            return
        }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Outside the areas currently supported")).firstMatch.exists)
        XCTAssertFalse(app.navigationBars["Visit availability"].exists)
        let selectedNames = ["Taman Bendera Pusaka", "Tatemukai Signature Omakase Sushi", "National Library of Indonesia", "Night market", "Memorial Coffee Cipondoh"]
        for name in selectedNames {
            XCTAssertTrue(app.staticTexts[name].exists, name)
        }
        XCTAssertFalse(app.staticTexts["Places not in this plan"].exists)
        capture(app, "Five selected places with live Luna ordering")
        let save = app.buttons["Save this trip"]
        scrollToTripControl(save, in: app)
        save.tap()
        XCTAssertTrue(app.alerts["Save Itinerary"].waitForExistence(timeout: 5))
        let field = app.alerts["Save Itinerary"].textFields.firstMatch
        replaceTripName(field, with: "Live order acceptance")
        guard field.value as? String == "Live order acceptance" else { return }
        app.alerts["Save Itinerary"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Live order acceptance"].waitForExistence(timeout: 15), app.debugDescription)
        for name in selectedNames { XCTAssertTrue(app.staticTexts[name].exists, name) }
        capture(app, "Saved live recommendation without regenerating Luna")
        scrollToTripControl(save, in: app)
        XCTAssertEqual(save.label, "Go Trip")
        save.tap()
        XCTAssertTrue(app.buttons["confirmTripArrival"].waitForExistence(timeout: 10))
        app.buttons["confirmTripArrival"].tap()
        XCTAssertTrue(app.staticTexts["You’ve arrived"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["completeTripVisit"].exists)
        capture(app, "Started live Luna trip and confirmed first arrival")
    }

    @MainActor func testPocketSettingsAreReachableAndDoNotRevealReadToken() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash", "--pocket-integration-fixture"]
        app.launch()
        app.tabBars.buttons["History"].tap()
        app.buttons["Account"].tap()
        XCTAssertTrue(app.navigationBars["Pocket settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["pocketServerURL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["pocketReadToken"].exists)
        XCTAssertFalse(app.staticTexts["synthetic-fixture-token"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Trip"].exists)
    }
}
