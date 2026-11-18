import CoreLocation
import XCTest

final class PocketEngineUITests: XCTestCase {
    @MainActor func testRecommendationDistanceUsesSimulatedDeviceLocation() {
        continueAfterFailure = false
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: -6.25, longitude: 106.8))
        defer { XCUIDevice.shared.location = nil }
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash", "--pocket-integration-fixture"]
        app.launch()
        openTripMenu(app)
        app.buttons["Get Recommendations"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        let permission = app.alerts.buttons["Allow While Using App"]
        if permission.waitForExistence(timeout: 3) { permission.tap() }
        let row = app.buttons["Fixture Japanese 1"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        let hasDistance = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (row.value as? String)?.contains("away") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hasDistance], timeout: 20), .completed, app.debugDescription)
    }

    @MainActor func testFirstItineraryKeepsUnknownPlacesAndSavesTheRecommendation() {
        continueAfterFailure = false
        let app = openFixtureRecommendations()
        for name in ["Fixture Japanese 1", "Fixture Japanese 2", "Fixture Unknown Hours"] {
            let place = app.buttons[name]
            if name == "Fixture Unknown Hours" { app.swipeUp() }
            scrollToTripControl(place, in: app)
            place.tap()
            XCTAssertTrue((place.value as? String)?.contains("Added") == true, app.debugDescription)
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
        let weather = app.staticTexts["itineraryDepartureWeather"]
        XCTAssertTrue(weather.waitForExistence(timeout: 5))
        XCTAssertTrue(weather.label.contains("Weather unavailable for this time"))
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        let unknown = app.staticTexts["Fixture Unknown Hours"]
        scrollToTripControl(unknown, in: app)
        XCTAssertTrue(unknown.exists)
        XCTAssertFalse(app.staticTexts["Places not in this plan"].exists)
        app.scrollViews["itineraryList"].swipeDown()
        app.scrollViews["itineraryList"].swipeDown()
        capture(app, "Untimed itinerary keeps every selected place")
        app.buttons["itineraryDepartureEdit"].tap()
        app.buttons["Departure date and time"].tap()
        XCTAssertTrue(app.navigationBars["Edit departure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers.count >= 2)
        app.navigationBars["Edit departure"].buttons["Cancel"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
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
            .press(forDuration: 0.2, thenDragTo: review.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertLessThan(first.frame.midY, second.frame.midY)
        XCTAssertFalse(app.staticTexts["Updated itinerary. Review it before saving."].exists)
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
        let savedName = app.alerts["Save Itinerary"].textFields.firstMatch.value as? String ?? "My trip"
        app.alerts["Save Itinerary"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars[savedName].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Unknown Hours"].exists)
        XCTAssertLessThan(second.frame.midY, first.frame.midY)
    }

    @MainActor func testMainSpotTimeoutChecksSameRequestAndKeepsSelections() {
        continueAfterFailure = false
        let app = openFixtureRecommendations(extraArguments: ["--pocket-itinerary-timeout-fixture",
                                                              "-io.pibeebee.c67.orderingMethod", "luna"])
        let name = "Fixture Japanese 1"
        let place = app.buttons[name]
        scrollToTripControl(place, in: app)
        place.tap()
        app.buttons["recommendationsNext"].tap()
        let mainSpot = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                        "mainSpot-", name)).firstMatch
        XCTAssertTrue(mainSpot.waitForExistence(timeout: 5))
        mainSpot.tap()
        app.buttons["Next"].tap()

        let status = app.buttons["Check status"]
        XCTAssertTrue(app.staticTexts["Your itinerary is taking longer than expected"].waitForExistence(timeout: 15),
                      app.debugDescription)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(mainSpot.exists)
        XCTAssertFalse(app.buttons["Next"].exists)
        status.tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts[name].exists)
    }

    @MainActor func testOpeningHoursDisclosesUnknownForSelectedPlace() {
        continueAfterFailure = false
        let app = openFixtureRecommendations()
        for name in ["Fixture Japanese 1", "Fixture Japanese 2", "Fixture Unknown Hours"] {
            let place = app.buttons[name]
            scrollToTripControl(place, in: app)
            place.tap()
        }
        app.buttons["recommendationsNext"].tap()
        let mainSpot = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "mainSpot-", "Fixture Japanese 2")).firstMatch
        XCTAssertTrue(mainSpot.waitForExistence(timeout: 5))
        mainSpot.tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 15))
        let hours = app.buttons["itineraryOpeningHours"]
        XCTAssertTrue(hours.waitForExistence(timeout: 5), app.debugDescription)
        hours.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hours unavailable — check before visiting")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
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
        let app = openFixtureRecommendations(extraArguments: ["-io.pibeebee.c67.orderingMethod", "luna"])
        let unknown = app.buttons["Fixture Unknown Hours"]
        app.swipeUp()
        scrollToTripControl(unknown, in: app)
        unknown.tap()
        XCTAssertTrue((unknown.value as? String)?.contains("Added") == true, app.debugDescription)
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
        let originalName = field.value as? String
        XCTAssertFalse(originalName?.isEmpty ?? true)
        replaceTripName(field, with: "")
        XCTAssertFalse(alert.buttons["Save"].isEnabled)
        replaceTripName(field, with: String(repeating: "A", count: 121))
        XCTAssertFalse(alert.buttons["Save"].isEnabled)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].exists)

        scrollToTripControl(save, in: app)
        save.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, originalName)
        replaceTripName(field, with: "Weekend coffee and taman 2026")
        XCTAssertTrue(alert.buttons["Save"].isEnabled)
        alert.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Weekend coffee and taman 2026"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Fixture Unknown Hours"].exists)
        scrollToTripControl(save, in: app)
        XCTAssertEqual(save.label, "Go Trip")
        capture(app, "Untimed exact rename after validation and cancel")
    }

    @MainActor func testV4CreatesSyntheticItineraryFromSelectedPlaces() {
        continueAfterFailure = false
        let app = openV4MainSpot()
        let schedule = app.buttons["tripScheduleOptions"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        XCTAssertTrue(app.navigationBars["Trip schedule"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.datePickers.count, 3)
        XCTAssertTrue(app.datePickers["tripScheduleDate"].exists, app.debugDescription)
        XCTAssertTrue(app.switches["Flexible departure"].exists)
        app.buttons["Done"].tap()
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        let details = app.buttons["Trip details"]
        scrollToTripControl(details, in: app)
        details.tap()
        XCTAssertTrue(app.staticTexts["Hybrid v4: schedules (experimental)"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testV4ShowsAutomaticTomorrowFallbackInReview() {
        continueAfterFailure = false
        let app = openV4MainSpot(lateDay: true)
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 20), app.debugDescription)
        let explanation = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Travelant found a schedule for this date instead.")).firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        let save = app.buttons["Save this trip"]
        scrollToTripControl(save, in: app)
        XCTAssertEqual(save.label, "Save your trip for later…")
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.buttons["itineraryStartNow"].exists)
    }

    @MainActor func testV41CreatesAnItineraryUsingUserDurationsAndShowsTheChosenDate() {
        continueAfterFailure = false
        let app = openV4MainSpot(method: "hybrid_v4_1")
        XCTAssertTrue(app.buttons["tripDateSummary"].waitForExistence(timeout: 5))
        app.buttons["tripScheduleOptions"].tap()
        XCTAssertTrue(app.navigationBars["Trip schedule"].waitForExistence(timeout: 5))
        app.buttons["tripTimingChoice"].tap()
        app.buttons["Tomorrow"].tap()
        for name in ["Fixture Japanese 1", "Fixture Japanese 2"] {
            let row = app.cells.containing(.staticText, identifier: name).firstMatch
            scrollToTripControl(row, in: app)
            let toggle = row.switches["Set visit duration"]
            scrollToTripControl(toggle, in: app)
            XCTAssertTrue(toggle.exists, app.debugDescription)
            toggle.switches.firstMatch.tap()
            XCTAssertEqual(toggle.value as? String, "1", app.debugDescription)
        }
        app.buttons["Done"].tap()
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        let details = app.buttons["Trip details"]
        scrollToTripControl(details, in: app)
        details.tap()
        XCTAssertTrue(app.staticTexts["Hybrid v4.1: flexible schedules (experimental)"].waitForExistence(timeout: 5), app.debugDescription)
        let supplied = app.staticTexts["Visit durations were supplied by you."]
        scrollToTripControl(supplied, in: app)
        capture(app, "Hybrid v4.1 with user durations")
        XCTAssertTrue(supplied.exists, app.debugDescription)
    }

    @MainActor func testV41ExplainsMissingDurationAndRecoversThroughScheduleEditing() {
        continueAfterFailure = false
        let app = openFixtureRecommendations(extraArguments: ["-io.pibeebee.c67.orderingMethod", "hybrid_v4_1"])
        let unknown = app.buttons["Fixture Unknown Hours"]
        app.swipeUp()
        scrollToTripControl(unknown, in: app)
        unknown.tap()
        XCTAssertTrue((unknown.value as? String)?.contains("Added") == true, app.debugDescription)
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Skip"].tap()
        let details = app.buttons["View schedule details"]
        XCTAssertTrue(details.waitForExistence(timeout: 15), app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: details)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
        capture(app, "Schedule recovery notice")
        details.tap()
        let diagnostic = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "visit duration is needed")).firstMatch
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Visit duration needed"].exists, app.debugDescription)
        capture(app, "Schedule conflict details")
        diagnostic.tap()
        XCTAssertTrue(app.navigationBars["Trip schedule"].waitForExistence(timeout: 10), app.debugDescription)
        let duration = app.switches["Set visit duration"]
        let revealed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: duration)
        XCTAssertEqual(XCTWaiter.wait(for: [revealed], timeout: 5), .completed, app.debugDescription)
        capture(app, "Duration field after opening the diagnostic")
        duration.switches.firstMatch.tap()
        XCTAssertEqual(duration.value as? String, "1", app.debugDescription)
        app.buttons["Done"].tap()
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fixture Unknown Hours"].exists)
    }

    @MainActor private func openV4MainSpot(lateDay: Bool = false, method: String = "hybrid_v4") -> XCUIApplication {
        var arguments = ["-io.pibeebee.c67.orderingMethod", method]
        if lateDay { arguments.append("--pocket-late-day-fixture") }
        let app = openFixtureRecommendations(extraArguments: arguments)
        for name in ["Fixture Japanese 1", "Fixture Japanese 2"] {
            let place = app.buttons[name]
            scrollToTripControl(place, in: app)
            place.tap()
        }
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor func testV4ReportsUnknownDurationWithoutLosingSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash", "--pocket-integration-fixture", "-io.pibeebee.c67.orderingMethod", "hybrid_v4"]
        app.launch()
        openTripMenu(app)
        app.buttons["Get Recommendations"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.navigationBars["Recommendations"].waitForExistence(timeout: 10))
        let unknown = app.buttons["Fixture Unknown Hours"]
        app.swipeUp()
        scrollToTripControl(unknown, in: app)
        unknown.tap()
        XCTAssertTrue((unknown.value as? String)?.contains("Added") == true, app.debugDescription)
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        let message = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A visit duration is unavailable")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["Adjust schedule"].exists, app.debugDescription)
        app.buttons["Adjust schedule"].tap()
        XCTAssertTrue(app.navigationBars["Trip schedule"].waitForExistence(timeout: 5))
        let duration = app.switches["Set visit duration"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        duration.switches.firstMatch.tap()
        XCTAssertEqual(duration.value as? String, "1", app.debugDescription)
        XCTAssertTrue(app.steppers.firstMatch.exists, app.debugDescription)
        app.buttons["Done"].tap()
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 25), app.debugDescription)
    }

    @MainActor private func openFixtureRecommendations(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash", "--pocket-integration-fixture"] + extraArguments
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

    @MainActor func testAuthenticatedAccountExposesItineraryMethods() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash", "--pocket-auth-fixture", "--pocket-auth-settings-fixture"]
        app.launch()
        app.tabBars.buttons["History"].tap()
        app.buttons["Account"].tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        let picker = app.buttons["pocketOrderingMethod"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
        picker.tap()
        XCTAssertTrue(app.buttons["Luna"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Hybrid v4: schedules"].exists)
        XCTAssertTrue(app.buttons["Hybrid: weather context"].exists)
        app.buttons["Hybrid v4: schedules"].tap()
        XCTAssertTrue(picker.label.contains("Hybrid v4: schedules") || (picker.value as? String)?.contains("Hybrid v4: schedules") == true)
        app.buttons["Done"].tap()
        app.buttons["Account"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("Hybrid v4: schedules") || (picker.value as? String)?.contains("Hybrid v4: schedules") == true)
        picker.tap()
        app.buttons["Luna"].tap()
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
        let picker = app.buttons["pocketOrderingMethod"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
        picker.tap()
        XCTAssertTrue(app.buttons["Hybrid v4: schedules"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Hybrid: weather context"].exists)
        app.buttons["Hybrid v4: schedules"].tap()
        XCTAssertTrue(picker.label.contains("Hybrid v4: schedules") || (picker.value as? String)?.contains("Hybrid v4: schedules") == true)
        picker.tap()
        app.buttons["Luna"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Trip"].exists)
    }
}
