import XCTest
import CryptoKit
import C67Domain
@testable import C67

final class AppleSignInAttemptTests: XCTestCase {
    func testNonceUsesSHA256HexAndEachAttemptHasFreshState() throws {
        let first = AppleSignInAttempt(), second = AppleSignInAttempt()
        XCTAssertNotEqual(first.nonce, second.nonce)
        XCTAssertNotEqual(first.state, second.state)
        XCTAssertEqual(first.hashedNonce.count, 64)
        let expected = SHA256.hash(data: Data(first.nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(first.hashedNonce, expected)
        let credential = try first.credentials(userID: "synthetic-apple-user", identityToken: Data("synthetic-token".utf8), returnedState: first.state)
        XCTAssertEqual(credential.nonce, first.nonce)
    }
    func testMissingTokenForeignStateAndExpiredAttemptsAreRejected() {
        let now = Date(timeIntervalSince1970: 1800000000)
        let attempt = AppleSignInAttempt(now: now)
        for (token, state, date) in [(nil, attempt.state, now), (Data(), attempt.state, now),
                                     (Data([0xff]), attempt.state, now), (Data("synthetic".utf8), "foreign", now),
                                     (Data("synthetic".utf8), attempt.state, now.addingTimeInterval(301)),
                                     (Data("synthetic".utf8), attempt.state, now.addingTimeInterval(-1))] as [(Data?, String, Date)] {
            XCTAssertThrowsError(try attempt.credentials(userID: "synthetic-user", identityToken: token, returnedState: state, now: date))
        }
    }
}
