import Foundation
import CryptoKit
import C67Domain

/// A single native authorization attempt; kept only in memory until completion or dismissal.
struct AppleSignInAttempt {
    let nonce: String
    let state: String
    let createdAt: Date
    var hashedNonce: String { SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined() }

    init(now: Date = Date()) {
        nonce = Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
        state = UUID().uuidString
        createdAt = now
    }

    func credentials(userID: String, identityToken: Data?, returnedState: String?, now: Date = Date()) throws -> AppleSignInCredentials {
        guard returnedState == state, now.timeIntervalSince(createdAt) >= 0,
              now.timeIntervalSince(createdAt) < 300, !userID.isEmpty,
              let identityToken, let token = String(data: identityToken, encoding: .utf8), !token.isEmpty else {
            throw AuthenticationError.invalidAppleCredential
        }
        return .init(identityToken: token, nonce: nonce, userID: userID)
    }
}
