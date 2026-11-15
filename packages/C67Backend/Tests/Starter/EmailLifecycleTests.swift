import Foundation
import CryptoKit
import Testing
import C67Domain
import C67Data

private let lifecycleEmail = "traveller@example.test"
private func lifecycleToken() -> String {
    #"{"access_token":"synthetic-access","refresh_token":"synthetic-refresh","token_type":"bearer","expires_in":3600,"user":{"id":"91111111-1111-4111-8111-111111111111","email":"traveller@example.test"}}"#
}
private func storedFlow(_ store: MemorySessionStore) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: #require(try store.read())) as! [String: Any]
}
private func callbackURL(_ store: MemorySessionStore, code: String = "synthetic-code") throws -> URL {
    let id = try #require(try storedFlow(store)["id"] as? String)
    return URL(string: "c67://auth/callback?state=" + id + "&code=" + code)!
}

@Test func signupPersistsPKCEVerifierAndResendRetainsItsChallenge() async throws {
    let flow = MemorySessionStore()
    let http = HTTPHarness { request in
        let body = try requestBody(request)
        if request.url!.lastPathComponent == "token" {
            #expect(body["auth_code"] as? String == "synthetic-code")
            let saved = try storedFlow(flow)
            #expect(body["code_verifier"] as? String == saved["verifier"] as? String)
            return .init(lifecycleToken())
        }
        let saved = try storedFlow(flow)
        let verifier = try #require(saved["verifier"] as? String)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(body["code_challenge"] as? String == challenge)
        #expect(body["code_challenge_method"] as? String == "s256")
        #expect(body["owner_id"] == nil)
        if request.url!.lastPathComponent == "resend" { return .init("{}") }
        return .init(#"{"id":"91111111-1111-4111-8111-111111111111"}"#)
    }
    let store = MemorySessionStore()
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store,
                                             flowStore: flow, session: http.session)
    try await service.signUp(email: lifecycleEmail, password: "synthetic-password")
    #expect(try await service.currentAccount() == nil)
    #expect(try storedFlow(flow)["password"] == nil)
    try await service.resendConfirmation()
    let callback = try callbackURL(flow)
    let relaunched = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store,
                                                flowStore: flow, session: http.session)
    try await relaunched.handleCallback(callback)
    #expect(try await relaunched.currentAccount()?.email == lifecycleEmail)
    #expect(try flow.read() == nil)
    await #expect(throws: AuthenticationError.emailFlowUnavailable) { try await relaunched.handleCallback(callback) }
}

@Test func callbackRejectsForeignAmbiguousAndTokenBearingURLsBeforeExchange() async throws {
    let http = HTTPHarness { _ in .init(#"{"id":"91111111-1111-4111-8111-111111111111"}"#) }
    let flow = MemorySessionStore()
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: MemorySessionStore(),
                                             flowStore: flow, session: http.session)
    try await service.signUp(email: lifecycleEmail, password: "synthetic-password")
    let id = try #require(try storedFlow(flow)["id"] as? String)
    for value in [
        "other://auth/callback?state=\(id)&code=fake",
        "c67://other/callback?state=\(id)&code=fake",
        "c67://auth/other?state=\(id)&code=fake",
        "c67://auth/callback?state=wrong&code=fake",
        "c67://auth/callback?state=\(id)&state=\(id)&code=fake",
        "c67://auth/callback?state=\(id)&code=fake&access_token=fake",
        "c67://auth/callback?state=\(id)&code=fake#access_token=fake"
    ] {
        await #expect(throws: AuthenticationError.invalidCallback) { try await service.handleCallback(URL(string: value)!) }
    }
    #expect(await http.log.requests().count == 1)
}

@Test func recoveryCredentialCannotAuthorizeTripsUntilPasswordIsUpdated() async throws {
    let http = HTTPHarness { request in
        switch request.url!.lastPathComponent {
        case "recover": return .init("{}")
        case "token": return .init(lifecycleToken())
        case "user":
            #expect(request.httpMethod == "PUT")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access")
            return .init(#"{"id":"91111111-1111-4111-8111-111111111111"}"#)
        default: Issue.record("Unexpected request"); return .init(500, "{}")
        }
    }
    let flow = MemorySessionStore(), store = MemorySessionStore()
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store,
                                             flowStore: flow, session: http.session)
    try await service.sendPasswordReset(email: lifecycleEmail)
    try await service.handleCallback(callbackURL(flow))
    await #expect(throws: AuthenticationError.passwordResetRequired) { try await service.accessToken() }
    let repository = try SupabaseRundownRepository(baseURL: http.baseURL, clientKey: "client",
                                                   session: http.session, authentication: service)
    await #expect(throws: AuthenticationError.passwordResetRequired) { try await repository.listMyTrips() }
    let relaunched = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store,
                                                flowStore: flow, session: http.session)
    await #expect(throws: AuthenticationError.passwordResetRequired) { try await relaunched.accessToken() }
    try await relaunched.updatePassword("new-synthetic-password")
    #expect(try await relaunched.accessToken() == "synthetic-access")
}

@Test(.timeLimit(.minutes(1))) func cancelEmailFlowRejectsLateCodeExchange() async throws {
    let started = TestLatch(), release = TestLatch()
    let http = HTTPHarness { request in
        if request.url!.lastPathComponent == "token" {
            await started.signal(); await release.wait()
            return .init(lifecycleToken())
        }
        return .init(#"{"id":"91111111-1111-4111-8111-111111111111"}"#)
    }
    let store = MemorySessionStore(), flow = MemorySessionStore()
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store,
                                             flowStore: flow, session: http.session)
    try await service.signUp(email: lifecycleEmail, password: "synthetic-password")
    let url = try callbackURL(flow)
    let exchange = Task { try await service.handleCallback(url) }
    await started.wait()
    try await service.cancelEmailFlow()
    await release.signal()
    await #expect(throws: CancellationError.self) { try await exchange.value }
    #expect(try store.read() == nil && flow.read() == nil)
}

@Test func numericErrorCodeDoesNotHideMachineReadableAuthErrors() async throws {
    for (status, code, expected) in [
        (400, "email_not_confirmed", AuthenticationError.emailNotConfirmed),
        (422, "weak_password", .weakPassword), (429, "over_request_rate_limit", .rateLimited),
        (400, "signup_disabled", .signupUnavailable)
    ] {
        let http = HTTPHarness { _ in .init(status, "{\"code\":\(status),\"error_code\":\"\(code)\"}") }
        let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client",
                                                 store: MemorySessionStore(), session: http.session)
        await #expect(throws: expected) { try await service.signIn(email: lifecycleEmail, password: "synthetic") }
    }
}

@Test(.timeLimit(.minutes(1))) func privateResponseFromPreviousLoginIsDiscardedAfterLogout() async throws {
    let started = TestLatch(), release = TestLatch(), graph = try contractFixture("trip-graph")
    let http = HTTPHarness { request in
        if request.url!.lastPathComponent == "token" { return .init(lifecycleToken()) }
        if request.url!.lastPathComponent == "logout" { return .init(204, "") }
        await started.signal(); await release.wait()
        return .init(data: graph)
    }
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: MemorySessionStore(), session: http.session)
    _ = try await service.signIn(email: lifecycleEmail, password: "synthetic")
    let repository = try SupabaseRundownRepository(baseURL: http.baseURL, clientKey: "client", session: http.session,
                                                   authentication: service)
    let pending = Task { try await repository.tripGraph(id: UUID()) }
    await started.wait()
    try await service.signOut()
    await release.signal()
    await #expect(throws: CancellationError.self) { try await pending.value }
}

@Test func refreshRetainsSessionIdentityAndLogoutPublishesSignedOut() async throws {
    let http = HTTPHarness { request in
        request.url!.lastPathComponent == "logout" ? .init(204, "") : .init(lifecycleToken())
    }
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: MemorySessionStore(), session: http.session)
    _ = try await service.signIn(email: lifecycleEmail, password: "synthetic")
    var iterator = await service.sessionChanges().makeAsyncIterator()
    let initial = try #require(await iterator.next())
    _ = try await service.refreshSession()
    let refreshed = try #require(await iterator.next())
    #expect(initial.sessionID == refreshed.sessionID && refreshed.account == initial.account)
    try await service.signOut()
    let signedOut = try #require(await iterator.next())
    #expect(signedOut.account == nil && signedOut.sessionID != initial.sessionID)
}

@Test func expiredPasswordUpdateClearsTheRecoverySession() async throws {
    let http = HTTPHarness { request in
        switch request.url!.lastPathComponent {
        case "recover": return .init("{}")
        case "token": return .init(lifecycleToken())
        case "user": return .init(401, #"{"error_code":"bad_jwt"}"#)
        default: return .init(500, "{}")
        }
    }
    let flow = MemorySessionStore(), store = MemorySessionStore()
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store,
                                             flowStore: flow, session: http.session)
    try await service.sendPasswordReset(email: lifecycleEmail)
    try await service.handleCallback(callbackURL(flow))
    await #expect(throws: AuthenticationError.sessionExpired) { try await service.updatePassword("new-synthetic-password") }
    #expect(try await service.currentAccount() == nil && store.read() == nil)
}
