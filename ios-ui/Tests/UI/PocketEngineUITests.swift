import XCTest

final class PocketEngineUITests: XCTestCase {
    @MainActor func testStructuredInterestsReachPocketSolverAndSavedItinerary() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash", "--pocket-integration-fixture"]
        app.launch()
        openTripMenu(app)
        app.buttons["Get Recommendations"].tap()
        XCTAssertTrue(app.buttons["Foodie"].waitForExistence(timeout: 5))
        app.buttons["Foodie"].tap()
        app.buttons["pocketRefineInterests"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("japanese")
        let japanese = app.buttons["pocketLabel-japanese_cuisine"]
        XCTAssertTrue(japanese.waitForExistence(timeout: 5))
        japanese.tap()
        app.buttons["pocketRefinementsDone"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["pocketRefinementsDone"])
        waitForExpectations(timeout: 5)
        app.buttons["Next"].tap()
        for _ in 0 ..< 6 {
            XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
            app.buttons["Skip"].tap()
        }
        let confirm = app.buttons["confirmTripInput"]
        scrollToTripControl(confirm, in: app)
        XCTAssertTrue(confirm.isEnabled, "Pocket discovery must not require a preselected destination")
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Recommendations"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Fixture Korean 4"].exists)
        for index in 1 ... 3 {
            let place = app.buttons["Fixture Japanese \(index)"]
            scrollToTripControl(place, in: app)
            place.tap()
        }
        app.buttons["recommendationsNext"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.navigationBars["Visit availability"].waitForExistence(timeout: 5))
        let consent = app.switches["pocketAIConsent"]
        scrollToTripControl(consent, in: app)
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(consent.value as? String, "1")
        let build = app.buttons["pocketBuildItinerary"]
        scrollToTripControl(build, in: app)
        build.tap()
        if !app.navigationBars["Itinerary"].waitForExistence(timeout: 15) {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Pocket planning failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Pocket planning failure"; screenshot.lifetime = .keepAlways; add(screenshot)
            XCTFail("The real Pocket solver did not reach itinerary review")
            return
        }
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Pocket real-solver synthetic integration"
        attachment.lifetime = .keepAlways
        add(attachment)
        let save = app.buttons["Save this trip"]
        scrollToTripControl(save, in: app)
        save.tap()
        XCTAssertTrue(app.alerts["Save Itinerary"].waitForExistence(timeout: 5))
        app.alerts["Save Itinerary"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Pocket integration test"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Fixture Japanese 1"].exists)
    }

    @MainActor func testLivePocketShowsRealJakartaParksWithoutPreselectedPlaces() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["C67_LIVE_ACCEPTANCE"] == "1")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash"]
        app.launch()
        XCTAssertTrue(app.buttons["Starting point: Current device position"].waitForExistence(timeout: 15),
                      "Set the Simulator starting point to Blok M before running this test.")
        openTripMenu(app)
        app.buttons["Get Recommendations"].tap()
        XCTAssertTrue(app.buttons["Nature"].waitForExistence(timeout: 5))
        app.buttons["Nature"].tap()
        app.buttons["Next"].tap()
        for _ in 0 ..< 6 {
            XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
            app.buttons["Skip"].tap()
        }
        let confirm = app.buttons["confirmTripInput"]
        scrollToTripControl(confirm, in: app)
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Recommendations"].waitForExistence(timeout: 20))
        for name in ["Taman Bendera Pusaka", "Tebet Eco Park", "Taman Literasi Martha Tiahahu"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10), name)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Real Jakarta parks in Pocket recommendations"
        attachment.lifetime = .keepAlways
        add(attachment)
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
