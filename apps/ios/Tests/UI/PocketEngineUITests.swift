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
        XCTAssertFalse(app.staticTexts["Pull down to refresh recommendations"].exists)
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

        let save = toolbarSave(in: app)
        save.tap()
        XCTAssertTrue(app.alerts["Save Itinerary"].waitForExistence(timeout: 5))
        let savedName = app.alerts["Save Itinerary"].textFields.firstMatch.value as? String ?? "My trip"
        app.alerts["Save Itinerary"].buttons["Save"].tap()
        openSavedTripFromHome(named: savedName, in: app)
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
        reviewFixtureTripWithUnknownHours(in: app)
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.navigationBars["Visit availability"].exists)
        let visit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                     "itineraryEdit-", "Fixture Unknown Hours")).firstMatch
        XCTAssertTrue(visit.waitForExistence(timeout: 5))
        let visitTime = visit.value as? String ?? ""
        XCTAssertNotNil(visitTime.range(of: #"^\d{2}:\d{2}–\d{2}:\d{2}$"#, options: .regularExpression))
        let travel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "2 min")).firstMatch
        XCTAssertTrue(travel.exists)
        _ = toolbarSave(in: app)
        let start = app.buttons["itineraryStartNow"]
        scrollToTripControl(start, in: app)
        start.tap()
        let confirmSchedule = app.buttons["Start with this schedule"]
        let arrival = app.buttons["confirmTripArrival"]
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in confirmSchedule.isHittable || arrival.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 10), .completed, app.debugDescription)
        if confirmSchedule.isHittable { confirmSchedule.tap() }
        XCTAssertTrue(arrival.waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "Started from the itinerary review")
    }

    @MainActor func testItineraryCheckmarkValidatesNameAndSavesToHome() {
        continueAfterFailure = false
        let app = openFixtureRecommendations(extraArguments: ["-io.pibeebee.c67.orderingMethod", "luna", "-C67_APP_MODE", "staging"])
        let footer = reviewFixtureTripWithUnknownHours(in: app)
        let review = app.navigationBars["Itinerary"]
        XCTAssertTrue(review.waitForExistence(timeout: 15))

        let save = toolbarSave(in: app)
        XCTAssertEqual(save.label, "Save trip")
        XCTAssertFalse(review.buttons["tripCreationCancel"].exists)
        XCTAssertFalse(app.buttons["Save this trip"].exists)
        assertFooterAlignment(app.buttons["itineraryStartNow"], with: footer)
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

        save.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, originalName)
        replaceTripName(field, with: "Weekend coffee and taman 2026")
        XCTAssertTrue(alert.buttons["Save"].isEnabled)
        alert.buttons["Save"].tap()
        openSavedTripFromHome(named: "Weekend coffee and taman 2026", in: app)
        XCTAssertTrue(app.staticTexts["Fixture Unknown Hours"].exists)
        let goTrip = app.buttons["Save this trip"]
        XCTAssertEqual(goTrip.label, "Go Trip")
        assertFooterAlignment(goTrip, with: footer)
        capture(app, "Untimed exact rename after validation and cancel")
    }

    @MainActor func testBeforeYouGoUsesForecastBelowDeparture() {
        continueAfterFailure = false
        let app = openFixtureRecommendations(extraArguments: [
            "-C67_APP_MODE", "staging", "--before-you-go-rain-fixture",
        ])
        reviewFixtureTripWithUnknownHours(in: app)
        _ = toolbarSave(in: app)
        let departure = app.otherElements["itineraryDeparture"]
        let heading = app.staticTexts["itineraryPreparationTitle"]
        XCTAssertTrue(departure.exists)
        XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThanOrEqual(heading.frame.minY, departure.frame.maxY)
        XCTAssertFalse(app.staticTexts["Schedule diagnostics"].exists)
        let umbrella = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Pack an umbrella")).firstMatch
        XCTAssertTrue(umbrella.waitForExistence(timeout: 5), app.debugDescription)
        let hours = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Check opening hours")).firstMatch
        scrollToTripControl(hours, in: app)
        capture(app, "Before you go with a synthetic rain forecast")
    }

    @MainActor func testItineraryMapPinShowsOnlyPlaceAndVisitDetails() {
        continueAfterFailure = false
        let app = openFixtureRecommendations(extraArguments: ["-C67_APP_MODE", "staging", "--itinerary-pin-details-fixture"])
        reviewFixtureTripWithUnknownHours(in: app)
        _ = toolbarSave(in: app)
        let visit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                     "itineraryEdit-", "Fixture Japanese 1")).firstMatch
        let plannedTime = try? XCTUnwrap(visit.value as? String)
        XCTAssertNotNil(plannedTime)
        let expand = app.buttons["itineraryExpandMap"]
        let itinerary = app.scrollViews["itineraryList"]
        for _ in 0 ..< 8 where !expand.isHittable {
            let start = itinerary.coordinate(withNormalizedOffset: .init(dx: 0.02, dy: 0.68))
            let end = itinerary.coordinate(withNormalizedOffset: .init(dx: 0.02, dy: 0.36))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertTrue(expand.isHittable, app.debugDescription)
        expand.tap()

        let expandedMap = app.descendants(matching: .any)["itineraryExpandedMap"].firstMatch
        XCTAssertTrue(expandedMap.waitForExistence(timeout: 10), app.debugDescription)
        let pin = expandedMap.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                             "itineraryMapStop-", "Fixture Japanese 1")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10), app.debugDescription)
        let unfocusedPinY = pin.frame.midY
        let adjacentPin = expandedMap.buttons["itineraryMapStop-2"].firstMatch
        XCTAssertTrue(adjacentPin.exists)
        let unfocusedSeparation = abs(adjacentPin.frame.midY - unfocusedPinY)
        XCTAssertGreaterThan(unfocusedSeparation, 20)
        pin.tap()
        let title = app.staticTexts["itineraryPinTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(title.label, "Fixture Japanese 1")
        XCTAssertEqual(app.staticTexts["itineraryPinAddress"].label, "Synthetic fixture address")
        let schedule = app.descendants(matching: .any)["itineraryPinSchedule"].firstMatch
        XCTAssertTrue(schedule.label.contains("45 min"), app.debugDescription)
        XCTAssertTrue(schedule.label.contains(plannedTime ?? "Missing planned time"))
        for label in ["Regular hours", "Contact", "Entry rules", "Entry rules source"] {
            XCTAssertFalse(app.staticTexts[label].exists, app.debugDescription)
        }
        let maps = app.buttons["itineraryPinOpenMaps"]
        XCTAssertTrue(maps.exists)
        XCTAssertLessThanOrEqual(schedule.frame.maxX, maps.frame.minX)
        XCTAssertTrue(schedule.frame.minY < maps.frame.maxY && maps.frame.minY < schedule.frame.maxY)
        XCTAssertGreaterThanOrEqual(maps.frame.height, 44)
        let focusedPin = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(pin.frame.midY - unfocusedPinY) > 30
                && abs(pin.frame.midX - app.frame.midX) < 24
                && abs(pin.frame.midY - app.frame.midY) < 95
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [focusedPin], timeout: 5), .completed, app.debugDescription)
        let zoomedIn = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !adjacentPin.exists || abs(adjacentPin.frame.midY - pin.frame.midY) > unfocusedSeparation * 1.25
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomedIn], timeout: 5), .completed, app.debugDescription)
        let focusedPinY = pin.frame.midY
        let cardTitleY = title.frame.minY
        XCTAssertLessThan(abs(cardTitleY - focusedPinY), 215)
        capture(app, "Itinerary card anchored to the focused pin")

        let panStart = app.coordinate(withNormalizedOffset: .init(dx: 0.08, dy: 0.41))
        let panEnd = app.coordinate(withNormalizedOffset: .init(dx: 0.08, dy: 0.50))
        panStart.press(forDuration: 0.05, thenDragTo: panEnd, withVelocity: .slow, thenHoldForDuration: 0)
        let cardFollowedPin = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let pinMovement = pin.frame.midY - focusedPinY
            let cardMovement = title.frame.minY - cardTitleY
            return abs(pinMovement) > 25 && abs(cardMovement - pinMovement) < 15
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [cardFollowedPin], timeout: 5), .completed, app.debugDescription)

        app.buttons["itineraryPinClose"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        let otherPin = app.buttons.containing(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                          "itineraryMapStop-", "Fixture Unknown Hours")).firstMatch
        otherPin.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(title.label, "Fixture Unknown Hours")
        XCTAssertEqual(app.staticTexts["itineraryPinAddress"].label, "Address unavailable")
        app.buttons["itineraryCloseMap"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 5))
    }

    @MainActor func testVisitDurationWheelUpdatesItinerary() {
        continueAfterFailure = false
        let app = openFixtureRecommendations(extraArguments: [
            "-io.pibeebee.c67.orderingMethod", "luna", "-C67_APP_MODE", "staging",
        ])
        reviewFixtureTripWithUnknownHours(in: app)
        _ = toolbarSave(in: app)
        let visit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                     "itineraryEdit-", "Fixture Japanese 1")).firstMatch
        scrollToTripControl(visit, in: app)
        let stopID = visit.identifier.dropFirst("itineraryEdit-".count)
        let reorder = app.descendants(matching: .any)["itineraryReorder-\(stopID)"]
        XCTAssertTrue(reorder.exists, app.debugDescription)
        XCTAssertGreaterThanOrEqual(visit.frame.minY, reorder.frame.maxY)
        XCTAssertGreaterThanOrEqual(visit.frame.maxX, reorder.frame.maxX)
        XCTAssertGreaterThanOrEqual(visit.frame.height, 44)
        capture(app, "Separate itinerary time row")
        visit.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5)).tap()

        let editor = app.navigationBars["Edit visit"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let place = app.staticTexts["itineraryVisitPlace"]
        XCTAssertTrue(place.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(place.label, "Fixture Japanese 1")
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(wheel.value as? String, "45 min")
        let update = app.buttons["Update itinerary"]
        XCTAssertTrue(update.isHittable)
        XCTAssertGreaterThan(update.frame.minY, wheel.frame.maxY)

        wheel.adjust(toPickerWheelValue: "50 min")
        XCTAssertEqual(wheel.value as? String, "50 min")
        capture(app, "Native visit duration wheel and bottom action")
        update.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        _ = toolbarSave(in: app)
        scrollToTripControl(visit, in: app)
        visit.tap()
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        XCTAssertEqual(wheel.value as? String, "50 min")
    }

    @MainActor func testItineraryDragMovesLastStopIntoNewSlot() {
        continueAfterFailure = false
        let app = openFixtureRecommendations(extraArguments: ["-C67_APP_MODE", "staging"])
        reviewFixtureTripWithUnknownHours(in: app)
        _ = toolbarSave(in: app)
        let itinerary = app.scrollViews["itineraryList"]
        let handles = itinerary.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "itineraryReorder-"))
        let source = handles.element(boundBy: 2)
        let target = handles.element(boundBy: 0)
        for _ in 0 ..< 5 where !source.isHittable {
            let start = itinerary.coordinate(withNormalizedOffset: .init(dx: 0.97, dy: 0.67))
            let end = itinerary.coordinate(withNormalizedOffset: .init(dx: 0.97, dy: 0.49))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertTrue(source.isHittable && target.isHittable, app.debugDescription)
        let movedLabel = source.label
        let originalFirstLabel = target.label
        let destination = target.coordinate(withNormalizedOffset: .init(dx: -1.4, dy: 0.6))
        source.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.25, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 1.5)
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            handles.element(boundBy: 0).label == movedLabel && handles.element(boundBy: 1).label == originalFirstLabel
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 10), .completed, app.debugDescription)
        _ = toolbarSave(in: app)
        capture(app, "Itinerary after dropping into the first slot")
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
        let save = toolbarSave(in: app)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Itinerary automatic tomorrow with toolbar save"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(save.label, "Save trip")
        XCTAssertFalse(app.buttons["Save this trip"].exists)
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
        let checkmark = toolbarSave(in: app)
        capture(app, "Future itinerary before saving")
        checkmark.tap()
        let save = app.alerts["Save Itinerary"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let tripName = save.textFields.firstMatch.value as? String ?? "My trip"
        save.buttons["Save"].tap()

        openSavedTripFromHome(named: tripName, in: app)
        let go = app.buttons["Save this trip"]
        scrollToTripControl(go, in: app)
        XCTAssertEqual(go.label, "Go Trip")
        go.tap()

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
        let save = toolbarSave(in: app)
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        capture(app, "Itinerary toolbar save at accessibility text size")
    }

    @MainActor func testV52DefaultOutdoorOptionsAndPartialForecastSurviveSave() {
        continueAfterFailure = false
        let app = openV4MainSpot(method: nil, extraArguments: ["--pocket-current-ordering-fixture"])
        let options = app.buttons["tripScheduleOptions"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        XCTAssertTrue(app.navigationBars["Trip schedule"].waitForExistence(timeout: 5))

        let allowance = app.steppers["extraTravelAllowance"]
        scrollToTripControl(allowance, in: app)
        XCTAssertTrue(allowance.exists, app.debugDescription)
        allowance.buttons.element(boundBy: 1).tap()

        let exposure = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "visitExposure-")).firstMatch
        scrollToTripControl(exposure, in: app)
        XCTAssertTrue(exposure.isHittable, app.debugDescription)
        exposure.tap()
        app.buttons["Outdoor · direct sun"].tap()
        app.navigationBars["Trip schedule"].buttons["Done"].tap()

        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 30), app.debugDescription)
        let details = app.buttons["Trip details"]
        scrollToTripControl(details, in: app)
        details.tap()
        XCTAssertTrue(app.staticTexts["v51ScheduleDecision"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Travelants v5.2"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "UV index: 4")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Direct sunlight (W/m²): unavailable"].exists, app.debugDescription)
        let order = (1 ... 3).map { app.buttons["itineraryMapStop-\($0)"].label }
        capture(app, "v5.2 outdoor schedule decision")
        toolbarSave(in: app).tap()
        let dialog = app.alerts["Save Itinerary"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        let title = dialog.textFields.firstMatch.value as? String ?? ""
        dialog.buttons["Save"].tap()
        openSavedTripFromHome(named: title, in: app)
        assertTripEngine("Travelants v5.2", in: app)
        XCTAssertTrue(app.staticTexts["Direct sunlight (W/m²): unavailable"].exists)
        XCTAssertEqual((1 ... 3).map { app.buttons["itineraryMapStop-\($0)"].label }, order)
        for name in ["Fixture Japanese 1", "Fixture Japanese 2", "Fixture Japanese 3"] {
            XCTAssertTrue(app.staticTexts[name].exists, name)
        }
    }

    @MainActor func testV51OutdoorOptionsAndMissingForecastSurviveSave() {
        continueAfterFailure = false
        let app = openV4MainSpot(method: "hybrid_v5_1")
        let options = app.buttons["tripScheduleOptions"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        XCTAssertTrue(app.navigationBars["Trip schedule"].waitForExistence(timeout: 5))

        let allowance = app.steppers["extraTravelAllowance"]
        scrollToTripControl(allowance, in: app)
        XCTAssertTrue(allowance.exists, app.debugDescription)
        allowance.buttons.element(boundBy: 1).tap()

        let exposure = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "visitExposure-")).firstMatch
        scrollToTripControl(exposure, in: app)
        XCTAssertTrue(exposure.isHittable, app.debugDescription)
        exposure.tap()
        app.buttons["Outdoor · direct sun"].tap()
        app.navigationBars["Trip schedule"].buttons["Done"].tap()

        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 30), app.debugDescription)
        let details = app.buttons["Trip details"]
        scrollToTripControl(details, in: app)
        details.tap()
        XCTAssertTrue(app.staticTexts["v51ScheduleDecision"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Direct sunlight (W/m²): unavailable"].exists, app.debugDescription)
        capture(app, "v5.1 outdoor schedule decision")
        toolbarSave(in: app).tap()
        let dialog = app.alerts["Save Itinerary"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        let title = dialog.textFields.firstMatch.value as? String ?? ""
        dialog.buttons["Save"].tap()
        openSavedTripFromHome(named: title, in: app)
    }

    @MainActor func testV52UpgradesSavedV51OnlyAfterApplyingDateEdit() {
        continueAfterFailure = false
        let fixtureID = UUID()
        let app = openV4MainSpot(method: "hybrid_v5_1", fixtureID: fixtureID)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 30), app.debugDescription)
        toolbarSave(in: app).tap()
        let dialog = app.alerts["Save Itinerary"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        let title = dialog.textFields.firstMatch.value as? String ?? ""
        dialog.buttons["Save"].tap()
        openSavedTripFromHome(named: title, in: app)
        app.terminate()

        app.launchArguments = ["--skip-splash", "--pocket-integration-fixture", "--pocket-current-ordering-fixture"]
        app.launch()
        openSavedTripFromHome(named: title, in: app)
        assertTripEngine("Travelants v5.1", in: app)

        func openDateEditor() {
            let menu = app.navigationBars.buttons["Trip options"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5), app.debugDescription)
            menu.tap()
            app.buttons["Change trip date"].tap()
            XCTAssertTrue(app.navigationBars["Change trip date"].waitForExistence(timeout: 5), app.debugDescription)
        }

        openDateEditor()
        app.navigationBars["Change trip date"].swipeDown()
        XCTAssertTrue(app.navigationBars["Change trip date"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Travelants v5.1"].exists)
        openDateEditor()
        app.buttons["Calculate schedule"].tap()
        let apply = app.buttons["Apply schedule"].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 30), app.debugDescription)
        scrollToTripControl(apply, in: app)
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10), app.debugDescription)
        app.terminate()

        app.launch()
        openSavedTripFromHome(named: title, in: app)
        assertTripEngine("Travelants v5.2", in: app)
        for name in ["Fixture Japanese 1", "Fixture Japanese 2", "Fixture Japanese 3"] {
            XCTAssertTrue(app.staticTexts[name].exists, name)
        }
        capture(app, "Saved v5.2 itinerary after applying date edit")
    }

    @MainActor private func assertTripEngine(_ version: String, in app: XCUIApplication) {
        let engine = app.staticTexts[version]
        if !engine.exists {
            let details = app.buttons["Trip details"]
            scrollToTripControl(details, in: app)
            let footer = app.buttons["Save this trip"]
            let itinerary = app.scrollViews["itineraryList"]
            for _ in 0 ..< 4 where footer.exists && details.frame.maxY >= footer.frame.minY - 8 {
                // Start outside the interactive MapKit view, which otherwise handles the drag.
                let start = itinerary.coordinate(withNormalizedOffset: .init(dx: 0.015, dy: 0.73))
                let end = itinerary.coordinate(withNormalizedOffset: .init(dx: 0.015, dy: 0.42))
                start.press(forDuration: 0.01, thenDragTo: end)
            }
            XCTAssertTrue(details.isHittable, app.debugDescription)
            if footer.exists {
                XCTAssertLessThan(details.frame.midY, footer.frame.minY, app.debugDescription)
            }
            details.tap()
        }
        XCTAssertTrue(engine.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testOpeningHoursExperimentTimeToItinerary() async throws {
        let probe = URL(string: "http://127.0.0.1:18793/health")!
        let http = try? await URLSession.shared.data(from: probe).1 as? HTTPURLResponse
        try XCTSkipUnless(http?.statusCode == 200, "Start benchmark_hours.py --serve-simulator")
        continueAfterFailure = false
        for (variant, port) in zip(["A", "B", "C"], [18791, 18792, 18793]) {
            let app = openV4MainSpot(method: variant == "C" ? "hybrid_v5_2" : "hybrid_v5_1", hoursPort: port)
            let next = app.buttons["Next"]
            XCTAssertTrue(next.exists)
            let started = ContinuousClock.now
            next.tap()
            XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 30), app.debugDescription)
            print("HOURS_SIMULATOR variant=\(variant) tap_to_visible=\(started.duration(to: .now))")
            app.terminate()
        }
    }

    @MainActor private func openV4MainSpot(lateDay: Bool = false, method: String? = "hybrid_v4", hoursPort: Int? = nil,
                                           extraArguments: [String] = [], fixtureID: UUID? = nil) -> XCUIApplication {
        var arguments = extraArguments
        if let method { arguments += ["-io.pibeebee.c67.orderingMethod", method] }
        if lateDay { arguments.append("--pocket-late-day-fixture") }
        let app = openFixtureRecommendations(extraArguments: arguments, hoursPort: hoursPort, fixtureID: fixtureID)
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

    @MainActor private func openFixtureRecommendations(extraArguments: [String] = [], hoursPort: Int? = nil,
                                                        fixtureID: UUID? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash", "--pocket-integration-fixture"] + extraArguments
        if let fixtureID { app.launchEnvironment["C67_ORDERING_FIXTURE_ID"] = fixtureID.uuidString }
        if let hoursPort { app.launchEnvironment["C67_SYNTHETIC_HOURS_PORT"] = String(hoursPort) }
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
            let search = app.searchFields["placeSearchField"]
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("Blok M MRT Jakarta\n")
            let result = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "MRT Blok M")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 20), app.debugDescription)
            result.tap()
            XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 5))
        }

        openTripMenu(app)
        app.buttons["Add Specific Place"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Taman Bendera Pusaka\n")
        let park = app.buttons["Add Taman Bendera Pusaka"]
        XCTAssertTrue(park.waitForExistence(timeout: 20), app.debugDescription)
        park.tap()
        app.buttons["addPlacesNext"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        let options = app.buttons["tripScheduleOptions"]
        XCTAssertTrue(options.waitForExistence(timeout: 5), app.debugDescription)
        options.tap()
        let exposure = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "visitExposure-")).firstMatch
        scrollToTripControl(exposure, in: app)
        exposure.tap()
        app.buttons["Outdoor · direct sun"].tap()
        app.navigationBars["Trip schedule"].buttons["Done"].tap()
        let started = ContinuousClock.now
        app.buttons["Next"].tap()
        let review = app.navigationBars["Itinerary"]
        if !review.waitForExistence(timeout: 120) {
            capture(app, "Live Pocket planning result")
            XCTFail(app.debugDescription)
            return
        }
        print("V52_LIVE tap_to_review=\(started.duration(to: .now))")
        XCTAssertTrue(app.staticTexts["Taman Bendera Pusaka"].exists)
        let openingHours = app.buttons["Opening hours"]
        if openingHours.exists {
            scrollToTripControl(openingHours, in: app)
            openingHours.tap()
        }
        assertTripEngine("Travelants v5.2", in: app)
        XCTAssertTrue(app.staticTexts["v51ScheduleDecision"].exists)
        let readings = app.staticTexts.allElementsBoundByIndex.map(\.label)
            .filter { label in ["Feels-like temperature", "UV index", "Direct sunlight", "Opening hours", "Regular hours", "Taman Bendera Pusaka:", "Legs without a driving estimate"]
                .contains { label.hasPrefix($0) } }
        print("V52_LIVE evidence=\(readings)")
        capture(app, "Live v5.2 itinerary from Jakarta discovery")
        toolbarSave(in: app).tap()
        let save = app.alerts["Save Itinerary"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let title = "Jakarta v5.2 " + UUID().uuidString.prefix(6)
        replaceTripName(save.textFields.firstMatch, with: String(title))
        save.buttons["Save"].tap()
        openSavedTripFromHome(named: title, in: app)
        assertTripEngine("Travelants v5.2", in: app)
        XCTAssertTrue(app.staticTexts["Taman Bendera Pusaka"].exists)
        capture(app, "Saved live v5.2 itinerary")
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
        let save = toolbarSave(in: app)
        save.tap()
        XCTAssertTrue(app.alerts["Save Itinerary"].waitForExistence(timeout: 5))
        let field = app.alerts["Save Itinerary"].textFields.firstMatch
        replaceTripName(field, with: "Live order acceptance")
        guard field.value as? String == "Live order acceptance" else { return }
        app.alerts["Save Itinerary"].buttons["Save"].tap()
        openSavedTripFromHome(named: "Live order acceptance", in: app)
        for name in selectedNames { XCTAssertTrue(app.staticTexts[name].exists, name) }
        capture(app, "Saved live recommendation without regenerating Luna")
        let go = app.buttons["Save this trip"]
        scrollToTripControl(go, in: app)
        XCTAssertEqual(go.label, "Go Trip")
        go.tap()
        XCTAssertTrue(app.buttons["confirmTripArrival"].waitForExistence(timeout: 10))
        app.buttons["confirmTripArrival"].tap()
        XCTAssertTrue(app.staticTexts["You’ve arrived"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["completeTripVisit"].exists)
        capture(app, "Started live Luna trip and confirmed first arrival")
    }

    @MainActor private func toolbarSave(in app: XCUIApplication) -> XCUIElement {
        let save = app.navigationBars["Itinerary"].buttons["itinerarySave"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in save.isHittable && save.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, app.debugDescription)
        return save
    }

    @MainActor @discardableResult
    private func reviewFixtureTripWithUnknownHours(in app: XCUIApplication) -> CGRect {
        for name in ["Fixture Japanese 1", "Fixture Japanese 2", "Fixture Unknown Hours"] {
            let place = app.buttons[name]
            if name == "Fixture Unknown Hours" { app.swipeUp() }
            scrollToTripControl(place, in: app)
            place.tap()
            XCTAssertTrue((place.value as? String)?.contains("Added") == true, app.debugDescription)
        }
        let recommendationsNext = app.buttons["recommendationsNext"]
        let footer = recommendationsNext.frame
        XCTAssertGreaterThanOrEqual(footer.height, 44)
        recommendationsNext.tap()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
        assertFooterAlignment(next, with: footer)
        next.tap()
        return footer
    }

    @MainActor private func assertFooterAlignment(_ action: XCUIElement, with reference: CGRect) {
        XCTAssertTrue(action.isHittable, action.debugDescription)
        let frame = action.frame
        XCTAssertEqual(frame.minX, reference.minX, accuracy: 1, action.label)
        XCTAssertEqual(frame.maxY, reference.maxY, accuracy: 1, action.label)
        XCTAssertEqual(frame.width, reference.width, accuracy: 1, action.label)
        XCTAssertEqual(frame.height, reference.height, accuracy: 1, action.label)
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
