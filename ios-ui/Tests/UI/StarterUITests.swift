import XCTest

final class StarterUITests: XCTestCase {
    @MainActor func testAccountUsesConfiguredMode() {
        let app = XCUIApplication()
        let expectsLive = ProcessInfo.processInfo.environment["C67_TEST_LIVE"] == "1"
        if ProcessInfo.processInfo.environment["C67_TEST_LARGE_TEXT"] == "1" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        if expectsLive {
            XCTAssertTrue(app.buttons["authApple"].waitForExistence(timeout: 5))
            let appleScreenshot = XCTAttachment(screenshot: app.screenshot())
            appleScreenshot.name = "Native Apple sign-in option"
            appleScreenshot.lifetime = .keepAlways
            add(appleScreenshot)
            loadFormControl(app.textFields["authEmail"], in: app)
            XCTAssertTrue(app.textFields["Email address"].waitForExistence(timeout: 5))
            loadFormControl(app.secureTextFields["authPassword"], in: app)
            XCTAssertTrue(app.secureTextFields["Password"].exists)
            loadFormControl(app.buttons["authSubmit"], in: app)
            XCTAssertFalse(app.buttons["authSubmit"].isEnabled)
        } else {
            XCTAssertTrue(app.staticTexts["Sign-in needs live mode"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.secureTextFields["Password"].exists)
            XCTAssertFalse(app.buttons["authApple"].exists)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = expectsLive ? "Live Account form" : "Mock Account boundary"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts[expectsLive ? "Live • Supabase" : "Mock • memory only"].waitForExistence(timeout: 5))
    }

    @MainActor func testLiveRegistrationAndRecoveryFormValidation() throws {
        guard ProcessInfo.processInfo.environment["C67_TEST_LIVE"] == "1" else {
            throw XCTSkip("Run this form check with the explicitly configured live client.")
        }
        let app = XCUIApplication()
        if ProcessInfo.processInfo.environment["C67_TEST_LARGE_TEXT"] == "1" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        loadFormControl(app.buttons["authAction"], in: app)
        app.buttons["authAction"].tap()
        app.buttons["Create account"].tap()
        loadFormControl(app.secureTextFields["authConfirmation"], in: app)
        XCTAssertTrue(app.secureTextFields["authConfirmation"].waitForExistence(timeout: 5))
        loadFormControl(app.buttons["authSubmit"], in: app)
        XCTAssertFalse(app.buttons["authSubmit"].isEnabled)
        loadFormControl(app.textFields["authEmail"], in: app, scrollingUp: false)
        app.textFields["authEmail"].tap()
        app.textFields["authEmail"].typeText("synthetic@example.test")
        app.secureTextFields["authPassword"].tap()
        // Dismiss the system suggestion before typing our synthetic password.
        // iOS may show it without treating it as an XCTest interruption.
        if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) {
            app.buttons["Close"].tap()
        }
        app.secureTextFields["authPassword"].typeText("synthetic-password")
        loadFormControl(app.buttons["authSubmit"], in: app)
        XCTAssertFalse(app.buttons["authSubmit"].isEnabled)
        loadFormControl(app.secureTextFields["authConfirmation"], in: app, scrollingUp: false)
        app.secureTextFields["authConfirmation"].tap()
        app.secureTextFields["authConfirmation"].typeText("synthetic-password")
        loadFormControl(app.buttons["authSubmit"], in: app)
        let validationScreenshot = XCTAttachment(screenshot: app.screenshot())
        validationScreenshot.name = "Synthetic registration form validation"
        validationScreenshot.lifetime = .keepAlways
        add(validationScreenshot)
        XCTAssertTrue(app.buttons["authSubmit"].isEnabled)
        loadFormControl(app.buttons["authAction"], in: app, scrollingUp: false)
        app.buttons["authAction"].tap()
        app.buttons["Forgot password"].tap()
        XCTAssertFalse(app.secureTextFields["authPassword"].exists)
        loadFormControl(app.buttons["authSubmit"], in: app)
        XCTAssertTrue(app.buttons["Send recovery email"].exists)
        // Do not submit: this UI check never sends email through the shared SMTP provider.
        loadFormControl(app.buttons["authAction"], in: app, scrollingUp: false)
        app.buttons["authAction"].tap()
        app.buttons["Sign in"].tap()
        loadFormControl(app.secureTextFields["authPassword"], in: app)
        XCTAssertTrue(app.secureTextFields["authPassword"].exists)
        loadFormControl(app.buttons["authSubmit"], in: app)
        XCTAssertFalse(app.buttons["authSubmit"].isEnabled)
        app.buttons["Done"].tap()
    }

    @MainActor func testLiveSystemCallbackWithoutPendingFlow() throws {
        guard ProcessInfo.processInfo.environment["C67_TEST_LIVE"] == "1" else {
            throw XCTSkip("Run callback routing only with the explicitly configured live client.")
        }
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        // No valid code or pending flow: exercise OS routing without an Auth exchange.
        XCUIDevice.shared.system.open(URL(string: "c67://auth/callback?code=synthetic&state=synthetic")!)
        let feedback = app.staticTexts["No email request is pending. Request a new link on this device."]
        loadFormControl(feedback, in: app)
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        loadFormControl(app.buttons["authSubmit"], in: app, scrollingUp: false)
        XCTAssertFalse(app.buttons["authSubmit"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "System callback without pending flow"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
    }

    @MainActor private func loadFormControl(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool = true) {
        for _ in 0 ..< 5 {
            // Form lazily creates rows; XCTest scrolls an existing target into view when tapping.
            if element.exists { return }
            if scrollingUp { app.collectionViews.firstMatch.swipeUp() }
            else { app.collectionViews.firstMatch.swipeDown() }
        }
        XCTAssertTrue(element.exists, "Expected form control to be loaded after scrolling.")
    }

    @MainActor func testMockDiscoveryDetailAndTrip() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Mock • memory only"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kota Tua Photo Walk")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1. Fatahillah Square"].waitForExistence(timeout: 5))
        app.buttons["Save as my trip"].tap()
        XCTAssertTrue(app.alerts["Trip saved"].waitForExistence(timeout: 5))
        app.alerts["Trip saved"].buttons["OK"].tap()
    }
}
