import SwiftUI
import AuthenticationServices

protocol AppleCredentialChecking: Sendable {
    /// false only for a definitive revoked, missing or transferred credential.
    func isAuthorized(userID: String) async throws -> Bool
}

struct AppleCredentialStateChecker: AppleCredentialChecking {
    func isAuthorized(userID: String) async throws -> Bool {
        let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        switch state {
        case .authorized: return true
        case .revoked, .notFound, .transferred: return false
        @unknown default: return true
        }
    }
}

struct AppleCredentialRevocationModifier: ViewModifier {
    let onRevocation: () -> Void
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            onRevocation()
        }
    }
}
