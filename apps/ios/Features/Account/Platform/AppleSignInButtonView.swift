import SwiftUI
import AuthenticationServices
import C67Domain

struct AppleSignInButtonView: View {
    var verifyingDeletion = false
    var onRequest: () -> Void = {}
    var onCancel: () -> Void = {}
    let onCompletion: (Result<AppleSignInCredentials, AuthenticationError>) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var attempt: AppleSignInAttempt?

    var body: some View {
        authorizationButton
            .frame(minHeight: 50, maxHeight: 50)
            .accessibilityIdentifier(verifyingDeletion ? "authAppleDeletion" : "authApple")
            .onDisappear { attempt = nil }
    }

    @ViewBuilder private var authorizationButton: some View {
        #if DEBUG
            if verifyingDeletion, let result = simulatedDeletionAuthorization {
                nativeAppleButton
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .overlay {
                        Button {
                            onRequest()
                            onCompletion(result)
                        } label: {
                            Color.clear.contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Continue with Apple")
                    }
            } else {
                nativeAppleButton
            }
        #else
            nativeAppleButton
        #endif
    }

    private var nativeAppleButton: some View {
        SignInWithAppleButton(verifyingDeletion ? .continue : .signIn) { request in
            let next = AppleSignInAttempt()
            attempt = next
            onRequest()
            request.requestedScopes = verifyingDeletion ? [] : [.email]
            request.nonce = next.hashedNonce
            request.state = next.state
        } onCompletion: { result in
            guard let current = attempt else { return }
            // Consume before handing off: duplicate or late completions cannot sign in again.
            attempt = nil
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    onCompletion(.failure(.invalidAppleCredential)); return
                }
                do {
                    onCompletion(.success(try current.credentials(userID: credential.user,
                                                                  identityToken: credential.identityToken,
                                                                  returnedState: credential.state,
                                                                  authorizationCode: verifyingDeletion ? credential.authorizationCode : nil)))
                } catch { onCompletion(.failure(.invalidAppleCredential)) }
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code == .canceled {
                    onCancel()
                } else {
                    onCompletion(.failure(.appleSignInFailed))
                }
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
    }

    #if DEBUG
        private var simulatedDeletionAuthorization: Result<AppleSignInCredentials, AuthenticationError>? {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--pocket-auth-fixture"), arguments.contains("--pocket-deletion-fixture") else { return nil }
            if arguments.contains("--simulate-apple-deletion-unavailable") { return .failure(.appleSignInFailed) }
            guard arguments.contains("--simulate-apple-deletion-authorization") else { return nil }
            return .success(.init(identityToken: "synthetic-identity", nonce: "synthetic-nonce", userID: "synthetic-apple-user",
                                  authorizationCode: "synthetic-deletion-code"))
        }
    #endif
}
