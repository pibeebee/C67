import CoreLocation
import XCTest

final class PocketEngineUITests: XCTestCase {
    @MainActor func testRecommendationDistanceUsesSimulatedDeviceLocation() {
        continueAfterFailure = false
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: -6.25, longitude: 106.8))
        defer { XCUIDevice.shared.location = nil }
        let app = XCUIApplication()
        app.launchArguments = ["--pocket-integration-fixture", "--without-starting-point"]
        app.launch()
        openTripMenu(app)
        app.buttons["Get Recommendations"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        let useLocation = app.buttons["Use current location"]
        XCTAssertTrue(useLocation.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.buttons["refreshRecommendations"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Recommendations starting point"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        useLocation.tap()
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
        XCTAssertFalse(app.buttons["tripDateSummary"].exists)
        app.buttons["Next"].tap()

        let review = app.navigationBars["Itinerary"]
        if !review.waitForExistence(timeout: 15) {
            capture(app, "First itinerary failure")
            XCTFail(app.debugDescription)
            return
        }
        XCTAssertFalse(app.navigationBars["Visit availability"].exists)
        XCTAssertFalse(app.navigationBars["Trip schedule"].exists)
        let weather = app.staticTexts["itineraryDepartureWeather"]
        XCTAssertTrue(weather.waitForExistence(timeout: 5))
        XCTAssertTrue(weather.label.contains("Weather unavailable for this time"))
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        let unknown = app.staticTexts["Fixture Unknown Hours"]
        let itinerary = app.scrollViews["itineraryList"]
        for _ in 0 ..< 5 where !unknown.isHittable { itinerary.swipeUp(velocity: .fast) }
        XCTAssertTrue(unknown.isHittable, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Places not in this plan"].exists)
        itinerary.swipeDown()
        itinerary.swipeDown()
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
        for _ in 0 ..< 5 {
            if save.exists && save.isHittable { break }
            itinerary.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(save.isHittable, app.debugDescription)
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
        let app = openFixtureRecommendations(extraArguments: ["--pocket-itinerary-timeout-fixture"])
        let name = "Fixture Japanese 1"
        for choice in [name, "Fixture Japanese 2", "Fixture Japanese 3"] {
            let place = app.buttons[choice]
            scrollToTripControl(place, in: app)
            place.tap()
        }
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
            if name == "Fixture Unknown Hours" { app.swipeUp() }
            scrollToTripControl(place, in: app)
            place.tap()
            XCTAssertTrue((place.value as? String)?.contains("Added") == true, app.debugDescription)
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
        let schedule = app.buttons["tripDateSummary"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        XCTAssertTrue(app.navigationBars["Trip schedule"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.datePickers.count, 3)
        XCTAssertTrue(app.datePickers["tripScheduleDate"].exists, app.debugDescription)
        XCTAssertTrue(app.switches["Flexible departure"].exists)
        app.buttons["Done"].tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        let details = app.buttons["Trip details"]
        let itinerary = app.scrollViews["itineraryList"]
        for _ in 0 ..< 6 where !details.isHittable {
            itinerary.swipeUp(velocity: .fast)
        }
        capture(app, "V4 itinerary details control")
        XCTAssertTrue(details.isHittable, app.debugDescription)
        details.tap()
        XCTAssertTrue(app.staticTexts["Hybrid v4: schedules (experimental)"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testHybridShowsAutomaticTomorrowFallbackInReview() {
        continueAfterFailure = false
        let app = openV4MainSpot(lateDay: true, method: "hybrid_v4_2")
        XCTAssertFalse(app.buttons["tripDateSummary"].exists)
        XCTAssertTrue(app.buttons["mainSpotAutomatic"].exists)
        XCTAssertFalse(app.buttons["tripScheduleOptions"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)
        capture(app, "Main Spot without schedule controls")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 20), app.debugDescription)
        let explanation = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Travelants found a schedule for this date instead.")).firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        let save = app.buttons["Save this trip"]
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Itinerary automatic tomorrow and pinned save"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(save.isHittable, app.debugDescription)
        XCTAssertEqual(save.label, "Save your trip for later…")
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.buttons["itineraryStartNow"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tripPlanningError"].exists)
    }

    @MainActor func testV41CreatesAnItineraryWithoutAskingForASchedule() {
        continueAfterFailure = false
        let app = openV4MainSpot(method: "hybrid_v4_1")
        XCTAssertFalse(app.buttons["tripDateSummary"].exists)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Japanese 2"].exists)
        let details = app.buttons["Trip details"]
        scrollToTripControl(details, in: app)
        details.tap()
        XCTAssertTrue(app.staticTexts["Hybrid v4.1: flexible schedules (experimental)"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.navigationBars["Trip schedule"].exists)
        capture(app, "Hybrid v4.1 calculates the itinerary")
    }

    @MainActor func testV41EstimatesMissingDurationWithoutOpeningAnEditor() {
        continueAfterFailure = false
        let app = openFixtureRecommendations(extraArguments: ["-io.pibeebee.c67.orderingMethod", "hybrid_v4_1"])
        for name in ["Fixture Japanese 1", "Fixture Japanese 2"] {
            let place = app.buttons[name]
            scrollToTripControl(place, in: app)
            place.tap()
        }
        let unknown = app.buttons["Fixture Unknown Hours"]
        app.swipeUp()
        scrollToTripControl(unknown, in: app)
        unknown.tap()
        XCTAssertTrue((unknown.value as? String)?.contains("Added") == true, app.debugDescription)
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fixture Unknown Hours"].exists)
        XCTAssertFalse(app.navigationBars["Trip schedule"].exists)
    }

    @MainActor func testFutureSavedPocketTripOffersDateEditorBeforeStarting() {
        continueAfterFailure = false
        let app = openFixtureRecommendations(extraArguments: ["--pocket-late-day-fixture"])
        let names = ["Fixture Japanese 1", "Fixture Japanese 2", "Fixture Japanese 3"]
        for name in names {
            let place = app.buttons[name]
            scrollToTripControl(place, in: app)
            place.tap()
        }
        app.buttons["recommendationsNext"].tap()

        app.buttons["Next"].tap()

        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["itineraryStartNow"].exists)
        capture(app, "Future itinerary before saving")
        let saveOrStart = app.buttons["Save this trip"]
        scrollToTripControl(saveOrStart, in: app)
        saveOrStart.tap()
        let save = app.alerts["Save Itinerary"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let tripName = save.textFields.firstMatch.value as? String ?? "My trip"
        save.buttons["Save"].tap()

        XCTAssertTrue(app.navigationBars[tripName].waitForExistence(timeout: 10), app.debugDescription)
        scrollToTripControl(saveOrStart, in: app)
        XCTAssertEqual(saveOrStart.label, "Go Trip")
        saveOrStart.tap()

        let editDate = app.buttons["Try again"]
        for _ in 0 ..< 6 where !editDate.isHittable {
            app.scrollViews["itineraryList"].swipeDown()
        }
        let dateIssue = app.staticTexts["Choose a new trip date and review its schedule before starting."]
        XCTAssertTrue(dateIssue.waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "Future trip requires a new date")
        XCTAssertFalse(app.buttons["confirmTripArrival"].exists)
        XCTAssertTrue(editDate.isHittable, app.debugDescription)
        editDate.tap()
        XCTAssertTrue(app.navigationBars["Change trip date"].waitForExistence(timeout: 5))
        capture(app, "Change trip date after starting a future trip")
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        XCTAssertTrue(app.buttons["Calculate schedule"].exists)
    }

    @MainActor func testAutomaticItineraryNeedsNoAIConsentOrScheduleInput() {
        continueAfterFailure = false
        let app = openFixtureRecommendations(extraArguments: [
            "--pocket-privacy-fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM",
        ])
        for name in ["Fixture Japanese 1", "Fixture Japanese 2", "Fixture Japanese 3"] {
            let place = app.buttons[name]
            scrollToTripControl(place, in: app)
            place.tap()
        }
        app.buttons["recommendationsNext"].tap()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["tripDateSummary"].exists)
        next.tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertFalse(app.buttons["Allow AI assistance for this trip"].exists)
        XCTAssertFalse(app.navigationBars["Trip schedule"].exists)
        let save = app.buttons["Save this trip"]
        let footerReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in save.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [footerReady], timeout: 5), .completed, app.debugDescription)
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        capture(app, "Itinerary with pinned actions at accessibility text size")
    }

    @MainActor private func openV4MainSpot(lateDay: Bool = false, method: String = "hybrid_v4") -> XCUIApplication {
        var arguments = ["-io.pibeebee.c67.orderingMethod", method]
        if lateDay { arguments.append("--pocket-late-day-fixture") }
        let app = openFixtureRecommendations(extraArguments: arguments)
        for name in ["Fixture Japanese 1", "Fixture Japanese 2", "Fixture Japanese 3"] {
            let place = app.buttons[name]
            scrollToTripControl(place, in: app)
            place.tap()
        }
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Showing places")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "This itinerary method supports")).firstMatch.exists)
        capture(app, "List of Places without descriptive copy")
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["mainSpotAutomatic"].waitForExistence(timeout: 5))
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
        for name in ["Fixture Japanese 1", "Fixture Japanese 2"] {
            let place = app.buttons[name]
            scrollToTripControl(place, in: app)
            place.tap()
        }
        let unknown = app.buttons["Fixture Unknown Hours"]
        app.swipeUp()
        scrollToTripControl(unknown, in: app)
        unknown.tap()
        XCTAssertTrue((unknown.value as? String)?.contains("Added") == true, app.debugDescription)
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        let message = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A visit duration is unavailable")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["Adjust schedule"].exists, app.debugDescription)
        app.buttons["Adjust schedule"].tap()
        XCTAssertTrue(app.navigationBars["Trip schedule"].waitForExistence(timeout: 5))
        let duration = app.cells.containing(.staticText, identifier: "Fixture Unknown Hours").firstMatch.switches["Set visit duration"]
        scrollToTripControl(duration, in: app)
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
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
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
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        app.buttons["Next"].tap()
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
