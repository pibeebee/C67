import Foundation
import XCTest
import C67Domain
import C67Data
@testable import C67

@MainActor
final class AccountTests: XCTestCase {
    func testKeychainPersistsUpdatesDeletesAndSeparatesBackends() throws {
        let namespace = "io.pibeebee.c67.tests." + UUID().uuidString
        let first = KeychainSessionStore(namespace: namespace, baseURL: URL(string: "https://first.example.test")!)
        let second = KeychainSessionStore(namespace: namespace, baseURL: URL(string: "https://second.example.test")!)
        defer { try? first.write(nil); try? second.write(nil) }
        XCTAssertNil(try first.read())
        try first.write(Data("synthetic-session-one".utf8))
        XCTAssertEqual(try first.read(), Data("synthetic-session-one".utf8))
        XCTAssertNil(try second.read())
        try first.write(Data("synthetic-session-two".utf8))
        let relaunchedStore = KeychainSessionStore(namespace: namespace, baseURL: URL(string: "https://first.example.test")!)
        XCTAssertEqual(try relaunchedStore.read(), Data("synthetic-session-two".utf8))
        try first.write(nil)
        XCTAssertNil(try relaunchedStore.read())
    }

    func testDiscoveryClearsPrivateStateWhenTheSessionChanges() async throws {
        let repository = try MockRundownRepository()
        let sources = try await repository.listRundowns()
        let source = try XCTUnwrap(sources.first)
        let presenter = DiscoveryPresenter(interactor: .init(repository: repository))
        let snapshot = AuthenticationSnapshot(account: TravellerAccount(id: UUID(), email: "a@example.test"), sessionID: UUID())
        presenter.sessionDidChange(snapshot)
        await presenter.save(source, at: Date(timeIntervalSince1970: 1800000000))
        XCTAssertNotNil(presenter.savedTrip)
        presenter.sessionDidChange(snapshot)
        XCTAssertNotNil(presenter.savedTrip)
        presenter.sessionDidChange(.init(account: nil, sessionID: UUID()))
        XCTAssertNil(presenter.savedTrip)
        XCTAssertNil(presenter.error)
        XCTAssertFalse(presenter.isSaving)
    }

    func testPresenterLoginAndOfflineLogoutShowCorrectAccountState() async {
        let authentication = FakeAuthentication()
        let presenter = AccountAssembly.makePresenter(authentication: authentication)
        await presenter.restore()
        XCTAssertTrue(presenter.hasRestored)
        XCTAssertNil(presenter.account)
        await presenter.signIn(email: "traveller@example.test", password: "synthetic")
        XCTAssertEqual(presenter.account?.email, "traveller@example.test")
        XCTAssertFalse(presenter.isBusy)
        await authentication.failLogout()
        await presenter.signOut()
        XCTAssertNil(presenter.account)
        XCTAssertEqual(presenter.error, AuthenticationError.remoteSignOutFailed.localizedDescription)
    }

    func testPresenterKeepsAccountOnTemporaryErrorAndClearsExpiredSession() async {
        let authentication = FakeAuthentication()
        let presenter = AccountAssembly.makePresenter(authentication: authentication)
        await presenter.signIn(email: "traveller@example.test", password: "synthetic")
        await authentication.failRestore(.server(status: 503))
        await presenter.restore()
        XCTAssertNotNil(presenter.account)
        XCTAssertNotNil(presenter.error)
        await authentication.failRestore(.sessionExpired)
        await presenter.restore()
        XCTAssertNil(presenter.account)
        XCTAssertEqual(presenter.error, AuthenticationError.sessionExpired.localizedDescription)
    }

    func testPassiveRestorePreservesCallbackErrorUntilExplicitRetry() async {
        let presenter = AccountAssembly.makePresenter(authentication: FakeAuthentication())
        await presenter.callback(URL(string: "c67://auth/callback?code=synthetic")!)
        XCTAssertEqual(presenter.error, AuthenticationError.invalidCallback.localizedDescription)
        await presenter.restore()
        XCTAssertEqual(presenter.error, AuthenticationError.invalidCallback.localizedDescription)
        await presenter.restore(force: true)
        XCTAssertNil(presenter.error)
    }

    func testAppleRevocationClearsAccountAndTemporarySystemErrorsKeepSession() async {
        for fails in [false, true] {
            let authentication = FakeAuthentication()
            let presenter = AccountPresenter(interactor: .init(authentication: authentication,
                                                               appleCredentials: TestAppleChecker(fails: fails)))
            await presenter.signInWithApple(.init(identityToken: "synthetic", nonce: "synthetic", userID: "synthetic-user"))
            XCTAssertEqual(presenter.account?.email, "relay@privaterelay.appleid.com")
            await presenter.restore()
            XCTAssertEqual(presenter.account != nil, fails)
            if !fails { XCTAssertEqual(presenter.error, AuthenticationError.sessionExpired.localizedDescription) }
        }
    }

    func testRevokedAppleSessionStaysClearedWhenRemoteLogoutFails() async {
        let authentication = FakeAuthentication()
        let presenter = AccountPresenter(interactor: .init(authentication: authentication,
                                                           appleCredentials: TestAppleChecker(fails: false)))
        await presenter.signInWithApple(.init(identityToken: "synthetic", nonce: "synthetic", userID: "synthetic-user"))
        await authentication.failLogout()
        await presenter.restore()
        XCTAssertNil(presenter.account)
        XCTAssertEqual(presenter.error, AuthenticationError.remoteSignOutFailed.localizedDescription)
    }

    func testPresenterReportsRejectedCredentialsAndAllowsRetry() async {
        let authentication = FakeAuthentication()
        let presenter = AccountAssembly.makePresenter(authentication: authentication)
        await presenter.signIn(email: "traveller@example.test", password: "rejected")
        XCTAssertNil(presenter.account)
        XCTAssertFalse(presenter.isBusy)
        XCTAssertEqual(presenter.error, AuthenticationError.invalidCredentials.localizedDescription)
        await presenter.signIn(email: "traveller@example.test", password: "synthetic")
        XCTAssertNotNil(presenter.account)
        XCTAssertNil(presenter.error)
    }
}

private actor FakeAuthentication: TravellerAuthentication {
    private var account: TravellerAccount?
    private var restoreError: AuthenticationError?
    private var logoutFails = false
    private var appleUserID: String?
    func failRestore(_ error: AuthenticationError) { restoreError = error }
    func failLogout() { logoutFails = true }
    func currentAccount() throws -> TravellerAccount? {
        if let restoreError { throw restoreError }
        return account
    }
    func signIn(email: String, password: String) throws -> TravellerAccount {
        if password == "rejected" { throw AuthenticationError.invalidCredentials }
        let account = TravellerAccount(id: UUID(), email: email)
        self.account = account
        return account
    }
    func signInWithApple(_ credentials: AppleSignInCredentials) throws -> TravellerAccount {
        let account = TravellerAccount(id: UUID(), email: "relay@privaterelay.appleid.com")
        self.account = account
        appleUserID = credentials.userID
        return account
    }
    func currentAppleUserID() -> String? { appleUserID }
    func invalidateAppleSession(userID: String) throws {
        if appleUserID == userID { try signOut() }
    }
    func signOut() throws {
        account = nil; appleUserID = nil
        if logoutFails { throw AuthenticationError.remoteSignOutFailed }
    }
    func refreshSession() throws -> TravellerAccount? { try currentAccount() }
    func sessionChanges() -> AsyncStream<AuthenticationSnapshot> {
        AsyncStream { $0.yield(.init(account: account, sessionID: UUID())); $0.finish() }
    }
    func signUp(email: String, password: String) throws { throw AuthenticationError.signupUnavailable }
    func resendConfirmation() throws { throw AuthenticationError.emailFlowUnavailable }
    func sendPasswordReset(email: String) throws { throw AuthenticationError.emailDeliveryFailed }
    func handleCallback(_ url: URL) throws { throw AuthenticationError.invalidCallback }
    func updatePassword(_ password: String) throws { throw AuthenticationError.passwordResetRequired }
    func cancelEmailFlow() { }
    func accessToken() -> String? { account == nil ? nil : "synthetic-token" }
}

private struct TestAppleChecker: AppleCredentialChecking {
    let fails: Bool
    func isAuthorized(userID: String) async throws -> Bool {
        if fails { throw URLError(.notConnectedToInternet) }
        return false
    }
}
