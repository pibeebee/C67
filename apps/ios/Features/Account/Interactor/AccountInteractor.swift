import Foundation
import C67Domain

struct AccountInteractor: Sendable {
    let authentication: any TravellerAuthentication
    var appleCredentials: any AppleCredentialChecking = AppleCredentialStateChecker()
    func restore() async throws -> TravellerAccount? {
        try await verifyAppleCredential()
        return try await authentication.currentAccount()
    }
    func refresh() async throws -> TravellerAccount? {
        try await verifyAppleCredential()
        return try await authentication.refreshSession()
    }
    private func verifyAppleCredential() async throws {
        // Apple can revoke its credential while the server is still deleting the account.
        guard try await !authentication.hasPendingAccountDeletion(),
              let userID = try await authentication.currentAppleUserID() else { return }
        // Temporary Apple/system errors must not destroy a usable Supabase session.
        guard let authorized = try? await appleCredentials.isAuthorized(userID: userID), !authorized else { return }
        try await authentication.invalidateAppleSession(userID: userID)
        throw AuthenticationError.sessionExpired
    }
    func signInWithApple(_ credentials: AppleSignInCredentials) async throws -> TravellerAccount {
        try await authentication.signInWithApple(credentials)
    }
    func changes() async -> AsyncStream<AuthenticationSnapshot> { await authentication.sessionChanges() }
    func signIn(email: String, password: String) async throws -> TravellerAccount {
        try await authentication.signIn(email: email, password: password)
    }
    func signUp(email: String, password: String) async throws { try await authentication.signUp(email: email, password: password) }
    func resend() async throws { try await authentication.resendConfirmation() }
    func recover(email: String) async throws { try await authentication.sendPasswordReset(email: email) }
    func callback(_ url: URL) async throws { try await authentication.handleCallback(url) }
    func updatePassword(_ password: String) async throws { try await authentication.updatePassword(password) }
    func cancelEmailFlow() async throws { try await authentication.cancelEmailFlow() }
    var supportsAccountDeletion: Bool { authentication.supportsAccountDeletion }
    func hasPendingDeletion() async throws -> Bool { try await authentication.hasPendingAccountDeletion() }
    func deleteAccount(_ accountID: UUID, appleAuthorizationCode: String?) async throws -> AccountDeletionResult {
        try await authentication.deleteAccount(expectedAccountID: accountID, appleAuthorizationCode: appleAuthorizationCode)
    }
    func signOut() async throws { try await authentication.signOut() }
}
