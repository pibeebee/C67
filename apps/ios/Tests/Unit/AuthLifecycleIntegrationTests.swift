import Foundation
import XCTest
import C67Domain
import C67Data
@testable import C67

/// Opt-in integration against the disposable homelab Auth/mail fixture, never the shared server.
@MainActor
final class AuthLifecycleIntegrationTests: XCTestCase {
    func testRegistrationConfirmationRecoveryRefreshAndLogoutAgainstRealAuth() async throws {
        guard ProcessInfo.processInfo.environment["C67_AUTH_INTEGRATION"] == "1" else {
            throw XCTSkip("Start the isolated Auth/mail fixture and opt in to its native integration test.")
        }
        let origin = URL(string: "http://127.0.0.1:18081")!
        let namespace = "io.pibeebee.c67.auth-integration." + UUID().uuidString
        let store = KeychainSessionStore(namespace: namespace, baseURL: origin)
        let flowStore = KeychainSessionStore(namespace: namespace + ".flow", baseURL: origin)
        defer { try? store.write(nil); try? flowStore.write(nil) }
        func service() throws -> SupabaseAuthentication {
            try .init(baseURL: origin, clientKey: "isolated-client", store: store, flowStore: flowStore)
        }
        let email = "c67-auth-test-" + UUID().uuidString.lowercased() + "@example.test"
        let password = UUID().uuidString + "Aa1!"
        let first = try service()
        try await first.signUp(email: email, password: password)
        check(try await first.currentAccount() == nil)
        do {
            _ = try await first.signIn(email: email, password: password)
            XCTFail("Unconfirmed account unexpectedly signed in")
        } catch AuthenticationError.emailNotConfirmed { }
        check(try flowStore.read() != nil)
        let initialMail = try await fixtureMail(email: email, minimum: 1)
        // The disposable fixture uses a one-second resend interval; shared rate limits stay unchanged.
        try await Task.sleep(for: .milliseconds(1100))
        try await first.resendConfirmation()
        let resent = try await fixtureMail(email: email, minimum: initialMail.count + 1)
        let confirmationLink = try XCTUnwrap(resent.links.last.flatMap(URL.init(string:)))
        let callback = try await fixtureRedirect(confirmationLink)
        // Simulate process replacement: both verifier and session use actual Simulator Keychain.
        let confirmed = try service()
        try await confirmed.handleCallback(callback)
        let account = try await confirmed.currentAccount()
        check(account?.email == email)
        check(try flowStore.read() == nil)
        check(try await confirmed.accessToken() != nil)
        do { try await confirmed.handleCallback(callback); XCTFail("Consumed callback was accepted twice") }
        catch AuthenticationError.emailFlowUnavailable { }
        let relaunched = try service()
        check(try await relaunched.currentAccount()?.id == account?.id)
        check(try await relaunched.refreshSession()?.id == account?.id)

        try await relaunched.sendPasswordReset(email: email)
        let recoveryMail = try await fixtureMail(email: email, minimum: resent.count + 1)
        let recoveryLink = try XCTUnwrap(recoveryMail.links.last.flatMap(URL.init(string:)))
        let recoveryCallback = try await fixtureRedirect(recoveryLink)
        let recovering = try service()
        try await recovering.handleCallback(recoveryCallback)
        do { _ = try await recovering.accessToken(); XCTFail("Recovery session authorized a private request") }
        catch AuthenticationError.passwordResetRequired { }
        let presenter = AccountAssembly.makePresenter(authentication: recovering)
        let observation = Task { await presenter.observe() }
        defer { observation.cancel() }
        await presenter.restore()
        for _ in 0 ..< 100 where !presenter.requiresPasswordReset { await Task.yield() }
        check(presenter.requiresPasswordReset)
        let newPassword = UUID().uuidString + "Bb2!"
        await presenter.updatePassword(newPassword)
        XCTAssertNil(presenter.error)
        XCTAssertFalse(presenter.requiresPasswordReset)
        check(try await recovering.accessToken() != nil)
        try await recovering.signOut()
        check(try store.read() == nil)
        let final = try service()
        do { _ = try await final.signIn(email: email, password: password); XCTFail("Old password still worked") }
        catch AuthenticationError.invalidCredentials { }
        _ = try await final.signIn(email: email, password: newPassword)
        let saved = try XCTUnwrap(try store.read())
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let refreshToken = try XCTUnwrap(fields["refreshToken"] as? String)
        try await final.signOut()
        check(try await service().currentAccount() == nil)
        let status = try await fixtureRefreshStatus(refreshToken)
        check(status == 400 || status == 401 || status == 403)
    }
}

private struct FixtureMail: Decodable { let count: Int; let links: [String] }
private func fixtureMail(email: String, minimum: Int) async throws -> FixtureMail {
    var url = URLComponents(string: "http://127.0.0.1:18081/__test/mail")!
    url.queryItems = [.init(name: "recipient", value: email)]
    for _ in 0 ..< 50 {
        let (data, _) = try await URLSession.shared.data(from: url.url!)
        let mail = try JSONDecoder().decode(FixtureMail.self, from: data)
        if mail.count >= minimum && !mail.links.isEmpty { return mail }
        try await Task.sleep(for: .milliseconds(100))
    }
    throw AuthenticationError.emailDeliveryFailed
}
private final class FixtureNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
private func fixtureRedirect(_ url: URL) async throws -> URL {
    guard url.scheme == "http", url.host == "127.0.0.1", url.port == 18081,
          url.path == "/auth/v1/verify" else { throw AuthenticationError.invalidCallback }
    let session = URLSession(configuration: .ephemeral, delegate: FixtureNoRedirect(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let (_, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 303,
          let location = http.value(forHTTPHeaderField: "Location"), let callback = URL(string: location) else {
        throw AuthenticationError.invalidCallback
    }
    return callback
}
private func fixtureRefreshStatus(_ token: String) async throws -> Int {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:18081/auth/v1/token?grant_type=refresh_token")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["refresh_token": token])
    let (_, response) = try await URLSession.shared.data(for: request)
    return (response as? HTTPURLResponse)?.statusCode ?? 0
}

private func check(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value, file: file, line: line)
}
