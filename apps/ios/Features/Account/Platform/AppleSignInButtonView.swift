import SwiftUI
import AuthenticationServices
import C67Domain

struct AppleSignInButtonView: View {
    var verifyingDeletion = false
    let onCompletion: (Result<AppleSignInCredentials, AuthenticationError>) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var attempt: AppleSignInAttempt?

    var body: some View {
        SignInWithAppleButton(verifyingDeletion ? .continue : .signIn) { request in
            let next = AppleSignInAttempt()
            attempt = next
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
                if (error as? ASAuthorizationError)?.code != .canceled {
                    onCompletion(.failure(.appleSignInFailed))
                }
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(minHeight: 50, maxHeight: 50)
        .accessibilityIdentifier("authApple")
        .onDisappear { attempt = nil }
    }
}
