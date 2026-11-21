import XCTest

final class TripHomeUITests: XCTestCase {
    private let deletionFixture = ["--skip-splash", "--pocket-auth-fixture", "--pocket-deletion-fixture"]

    @MainActor func testDeleteAccountReviewCanBeCancelled() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = deletionFixture + ["--seed-deletion-fixture"]
        app.launch()
        openDeleteAccountReview(in: app)

        XCTAssertTrue(app.staticTexts["deletionConsequences"].isHittable)
        XCTAssertTrue(app.staticTexts["deletionAccountEmail"].isHittable)
        XCTAssertTrue(app.buttons["authAppleDeletion"].isHittable)
        XCTAssertFalse(app.buttons["Remove Apple access myself"].exists)
        capture(app, name: "Delete Account review")
        app.navigationBars["Delete Account"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["deleteAccount"].exists)
        XCTAssertFalse(app.buttons["Check status"].exists)
    }

    @MainActor func testDeleteAccountWithAppleFromOneScreenAtAccessibilityTextSize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = deletionFixture + [
            "--seed-deletion-fixture", "--simulate-apple-deletion-authorization",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        openDeleteAccountReview(in: app)

        let apple = app.buttons["authAppleDeletion"]
        let scroll = app.scrollViews["accountDeletionReview"]
        for _ in 0 ..< 3 where !apple.isHittable { scroll.swipeUp() }
        XCTAssertTrue(apple.isHittable)
        XCTAssertGreaterThanOrEqual(apple.frame.height, 44)
        XCTAssertTrue(app.navigationBars["Delete Account"].buttons["Cancel"].isHittable)
        capture(app, name: "Delete Account review - Accessibility XXXL")
        apple.tap()

        waitForDeletionCompletion(in: app)
        XCTAssertFalse(app.descendants(matching: .any)["How to remove Apple access"].firstMatch.exists)
        capture(app, name: "Delete Account Apple success")
    }

    @MainActor func testDeleteAccountCanCompleteWhenAppleVerificationCannotBeUsed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = deletionFixture + ["--seed-deletion-fixture", "--simulate-apple-deletion-unavailable"]
        app.launch()
        openDeleteAccountReview(in: app)

        let manual = app.buttons["Remove Apple access myself"]
        XCTAssertFalse(manual.exists)
        app.buttons["authAppleDeletion"].tap()
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        capture(app, name: "Delete Account Apple recovery")
        manual.tap()
        let confirm = app.buttons["Delete Travelants account"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture(app, name: "Delete Account manual confirmation")
        confirm.tap()

        let checkStatus = app.buttons["Check status"]
        XCTAssertTrue(checkStatus.waitForExistence(timeout: 5))
        app.navigationBars["Delete Account"].buttons["Done"].tap()
        app.navigationBars["Account"].buttons["Done"].tap()
        waitForDeletionCompletion(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["How to remove Apple access"].firstMatch.exists)
        capture(app, name: "Delete Account confirmed")
        app.terminate()
        app.launchArguments = deletionFixture
        app.launch()
        XCTAssertTrue(app.buttons["authApple"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["History"].exists)
    }

    @MainActor private func openDeleteAccountReview(in app: XCUIApplication) {
        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()
        app.buttons["Account"].tap()
        let delete = app.buttons["deleteAccount"]
        scrollToTripControl(delete, in: app)
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        XCTAssertTrue(app.navigationBars["Delete Account"].waitForExistence(timeout: 5))
    }

    @MainActor private func waitForDeletionCompletion(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Your account has been deleted."].waitForExistence(timeout: 20))
        XCTAssertTrue(app.navigationBars["Account"].waitForNonExistence(timeout: 5))
        let signIn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["authApple"])
        XCTAssertEqual(XCTWaiter.wait(for: [signIn], timeout: 5), .completed)
    }

    @MainActor func testAuthenticatedPocketStartsWithAppleSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-splash", "--pocket-auth-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["authApple"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Welcome to Travelants"].exists)
        capture(app, name: "Sign in")
        XCTAssertFalse(app.textFields["pocketServerURL"].exists)
        XCTAssertFalse(app.secureTextFields["pocketReadToken"].exists)
    }

    @MainActor func testReviewerSignInRejectsWrongPasswordThenRestoresSessionAndSupportsDeletion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let arguments = ["--skip-splash", "--pocket-auth-fixture", "--pocket-review-fixture"]
        app.launchArguments = arguments + ["--reset-review-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["authApple"].waitForExistence(timeout: 10))
        app.buttons["appReviewSignIn"].tap()
        let email = app.textFields["appReviewEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("review@example.test")
        let password = app.secureTextFields["appReviewPassword"]
        let submit = app.buttons["appReviewSubmit"]
        password.tap()
        password.typeText("incorrect")
        submit.tap()
        XCTAssertTrue(app.staticTexts["Sign-in needs attention"].waitForExistence(timeout: 5))
        password.tap()
        password.typeText("synthetic-review-password")
        submit.tap()
        XCTAssertTrue(app.tabBars.buttons["History"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        openDeleteAccountReview(in: app)
        XCTAssertFalse(app.buttons["authAppleDeletion"].exists)
        app.buttons["confirmDeleteAccount"].tap()
        waitForDeletionCompletion(in: app)
    }

    @MainActor func testPrivacyPolicyLinkIsVisibleBeforeSignInAndInAccount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let arguments = ["--skip-splash", "--pocket-auth-fixture", "--pocket-privacy-fixture"]
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["authApple"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["Privacy Policy"].firstMatch.exists)
        app.terminate()
        app.launchArguments = arguments + ["--pocket-auth-settings-fixture"]
        app.launch()
        app.tabBars.buttons["History"].tap()
        let account = app.buttons["Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        capture(app, name: "History")
        account.tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        let policy = app.descendants(matching: .any)["Privacy Policy"].firstMatch
        scrollToTripControl(policy, in: app)
        XCTAssertTrue(policy.exists, app.debugDescription)
        capture(app, name: "Account")
    }

    @MainActor func testHomeOffersManualStartingPointBeforeRequestingLocation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--pocket-integration-fixture", "--without-starting-point"]
        app.launch()
        let manual = app.buttons["homeLocation"]
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["homeUseCurrentLocation"].isHittable)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture(app, name: "Home starting point")
        manual.tap()
        XCTAssertTrue(app.navigationBars["Starting point"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["placeSearchField"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor func testCompletedTripShowsVisitedStops() {
        let app = XCUIApplication()
        app.launchArguments = ["--completed-trip-preview"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Trip complete"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["All 3 stops visited"].exists)
        XCTAssertTrue(app.staticTexts["Visited stops"].exists)
        XCTAssertTrue(app.buttons["Done"].exists)
        capture(app, name: "Trip complete summary")
    }
    @MainActor func testEmptyHomeNavigationAndPlanningEntry() {
        let app = XCUIApplication()
        app.launchArguments += ["--skip-splash"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homeEmptyState"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["homePlanTrip"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["homeAddTrip"].frame.width, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["homeAddTrip"].frame.height, 44)
        XCTAssertLessThanOrEqual(app.buttons["homeAddTrip"].frame.width, 48)
        XCTAssertLessThanOrEqual(app.buttons["homeAddTrip"].frame.height, 48)
        capture(app, name: "HOME EMPTY - Light")

        app.buttons["homeLocation"].tap()
        XCTAssertTrue(app.navigationBars["Starting point"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["placeSearchField"].exists)
        app.buttons["Cancel"].tap()

        app.buttons["homePlanTrip"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["homeEmptyState"].waitForExistence(timeout: 5))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No trips yet"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Sign-in needs live mode"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Trip"].tap()
        XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 5))
    }

    @MainActor func testEmptyHomeAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments += ["--skip-splash"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homeEmptyState"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["homeAddTrip"].isHittable)
        XCTAssertTrue(app.buttons["homeLocation"].isHittable)
        capture(app, name: "HOME EMPTY - Accessibility XXXL")
        openTripMenu(app)
        app.buttons["Get Recommendations"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
    }

    @MainActor func testSavingMockProposalOpensTripAndReturnsHome() {
        let app = XCUIApplication()
        app.launchArguments += ["--skip-splash"]
        app.launch()
        reviewMockItinerary(app)
        saveMockItinerary(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["homeAddTrip"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["homeEmptyState"].exists)
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 12 {
            if element.exists && element.isHittable { return }
            let itinerary = app.scrollViews["itineraryList"]
            let form = itinerary.exists ? itinerary : app.collectionViews.firstMatch
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.85))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.2))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.exists, "Expected planning control after scrolling")
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
