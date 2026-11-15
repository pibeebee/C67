import Foundation

public struct TravellerAccount: Codable, Equatable, Sendable {
    public let id: UUID
    public let email: String?
    public init(id: UUID, email: String?) { self.id = id; self.email = email }
}

/// A local session identity changes on account transitions, never on token rotation.
public struct AuthenticationSnapshot: Equatable, Sendable {
    public let account: TravellerAccount?
    public let sessionID: UUID
    public let requiresPasswordReset: Bool
    public let isRestored: Bool
    public let pendingEmail: String?
    public let pendingRecovery: Bool
    public init(account: TravellerAccount?, sessionID: UUID, requiresPasswordReset: Bool = false,
                isRestored: Bool = true, pendingEmail: String? = nil, pendingRecovery: Bool = false) {
        self.account = account; self.sessionID = sessionID
        self.requiresPasswordReset = requiresPasswordReset; self.isRestored = isRestored
        self.pendingEmail = pendingEmail; self.pendingRecovery = pendingRecovery
    }
}

/// Ephemeral Apple authorization output. Never persist or log the identity token or nonce.
public struct AppleSignInCredentials: Sendable {
    public let identityToken: String
    public let nonce: String
    public let userID: String
    public init(identityToken: String, nonce: String, userID: String) {
        self.identityToken = identityToken; self.nonce = nonce; self.userID = userID
    }
}

public protocol TravellerAuthentication: Sendable {
    func currentAccount() async throws -> TravellerAccount?
    func refreshSession() async throws -> TravellerAccount?
    func sessionChanges() async -> AsyncStream<AuthenticationSnapshot>
    func signIn(email: String, password: String) async throws -> TravellerAccount
    func signInWithApple(_ credentials: AppleSignInCredentials) async throws -> TravellerAccount
    func currentAppleUserID() async throws -> String?
    func invalidateAppleSession(userID: String) async throws
    func signUp(email: String, password: String) async throws
    func resendConfirmation() async throws
    func sendPasswordReset(email: String) async throws
    func handleCallback(_ url: URL) async throws
    func updatePassword(_ password: String) async throws
    func cancelEmailFlow() async throws
    func signOut() async throws
    func accessToken() async throws -> String?
}

public enum AuthenticationError: Error, Equatable, LocalizedError, Sendable {
    case invalidCredentials, sessionExpired, storageUnavailable, operationInProgress
    case remoteSignOutFailed, invalidResponse, emailNotConfirmed, invalidEmail, weakPassword
    case rateLimited, invalidCallback, emailFlowExpired, emailFlowUnavailable, passwordResetRequired
    case passwordUnchanged, reauthenticationRequired, signupUnavailable, emailDeliveryFailed
    case invalidAppleCredential, appleSignInUnavailable, appleSignInFailed
    case server(status: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Sign-in failed. Check your email and password."
        case .sessionExpired: "Your session has expired. Sign in again."
        case .storageUnavailable: "Secure session storage is unavailable. Please try again."
        case .operationInProgress: "Another account action is in progress."
        case .remoteSignOutFailed: "Signed out on this device. The server could not confirm session revocation."
        case .invalidResponse: "The authentication server returned an unexpected response."
        case .emailNotConfirmed: "Confirm your email before signing in. Open the confirmation link on the device that requested it."
        case .invalidEmail: "Enter a valid email address."
        case .weakPassword: "Use a password with at least 8 characters and meet any additional server requirements."
        case .rateLimited: "Too many attempts. Wait before trying again."
        case .invalidCallback: "This sign-in link cannot be used by this app. Request a new link here."
        case .emailFlowExpired: "This link has expired or was already used. Request a new link on this device."
        case .emailFlowUnavailable: "No email request is pending. Request a new link on this device."
        case .passwordResetRequired: "Set a new password to finish account recovery."
        case .passwordUnchanged: "Choose a password different from the current password."
        case .reauthenticationRequired: "Request a new password recovery email to verify your identity."
        case .signupUnavailable: "Account registration is currently unavailable."
        case .emailDeliveryFailed: "The confirmation email could not be sent. Try again later."
        case .invalidAppleCredential: "Apple sign-in could not be verified. Please try again."
        case .appleSignInUnavailable: "Sign in with Apple is not configured for this server."
        case .appleSignInFailed: "Sign in with Apple did not finish. Please try again."
        case .server(let status): "Authentication is unavailable (HTTP \(status)). Please try again."
        }
    }
}
