import XCTest
@testable import C67

@MainActor
final class AccountFormTests: XCTestCase {
    func testSignInRequiresEmailAndPasswordButKeepsExistingShortPasswordsUsable() {
        var form = AccountFormState()
        XCTAssertFalse(form.canSubmit(.signIn))
        form.email = "traveller@example.test"
        XCTAssertFalse(form.canSubmit(.signIn))
        form.password = "legacy"
        XCTAssertTrue(form.canSubmit(.signIn))
    }
    func testRegistrationAndResetRequireMatchingPasswordsOfAtLeastEightCharacters() {
        var form = AccountFormState()
        form.email = "traveller@example.test"
        form.password = "synthetic-password"
        XCTAssertFalse(form.canSubmit(.signUp))
        form.confirmation = "different"
        XCTAssertFalse(form.canResetPassword)
        form.confirmation = form.password
        XCTAssertTrue(form.canSubmit(.signUp))
        XCTAssertTrue(form.canResetPassword)
        form.password = "short"; form.confirmation = "short"
        XCTAssertFalse(form.canSubmit(.signUp))
    }
    func testRecoveryNeedsOnlyEmailAndClearingSecretsPreservesEmail() {
        var form = AccountFormState()
        form.email = "   "
        XCTAssertFalse(form.canSubmit(.recovery))
        form.email = "traveller@example.test"
        XCTAssertTrue(form.canSubmit(.recovery))
        form.password = "synthetic-password"; form.confirmation = form.password
        form.clearPasswords()
        XCTAssertTrue(form.password.isEmpty && form.confirmation.isEmpty)
        XCTAssertEqual(form.email, "traveller@example.test")
        XCTAssertFalse(form.canSubmit(.signUp))
    }
}
