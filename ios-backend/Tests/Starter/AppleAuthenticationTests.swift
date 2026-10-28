import Foundation
import Testing
import C67Domain
import C67Data

private let appleSubject = "synthetic-apple-subject"
private let appleCredentials = AppleSignInCredentials(identityToken: "synthetic-apple-id-token", nonce: String(repeating: "n", count: 43), userID: appleSubject)
private func appleToken(_ access: String = "synthetic-apple-access") -> String {
    """
    {"access_token":"\(access)","refresh_token":"synthetic-apple-refresh","token_type":"bearer","expires_in":3600,
    "user":{"id":"91111111-1111-4111-8111-111111111111","email":"relay@privaterelay.appleid.com"}}
    """
}

@Test func appleTokenExchangePersistsCommonSessionWithoutPersistingAppleTokenOrNonce() async throws {
    let http = HTTPHarness { request in
        let body = try requestBody(request)
        #expect(request.url!.query == "grant_type=id_token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body["provider"] as? String == "apple")
        #expect(body["id_token"] as? String == appleCredentials.identityToken)
        #expect(body["nonce"] as? String == appleCredentials.nonce)
        #expect(body["email"] == nil && body["user_id"] == nil)
        return .init(appleToken())
    }
    let store = MemorySessionStore()
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store, session: http.session)
    let user = try await service.signInWithApple(appleCredentials)
    #expect(user.email == "relay@privaterelay.appleid.com")
    #expect(try await service.accessToken() == "synthetic-apple-access")
    let persisted = String(data: try #require(try store.read()), encoding: .utf8)!
    #expect(!persisted.contains(appleCredentials.identityToken) && !persisted.contains(appleCredentials.nonce))
    let restored = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store, session: http.session)
    #expect(try await restored.currentAccount() == user)
    #expect(try await restored.currentAppleUserID() == appleSubject)
}

@Test func appleRefreshRetainsRevocationIdentityAndLateRevocationDoesNotClearEmailLogin() async throws {
    let http = HTTPHarness { request in
        if request.url!.query == "grant_type=refresh_token" { return .init(appleToken("rotated-apple-access")) }
        return .init(appleToken())
    }
    let store = MemorySessionStore()
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store, session: http.session)
    _ = try await service.signInWithApple(appleCredentials)
    _ = try await service.refreshSession()
    #expect(try await service.currentAppleUserID() == appleSubject)
    _ = try await service.signIn(email: "traveller@example.test", password: "synthetic")
    try await service.invalidateAppleSession(userID: appleSubject)
    #expect(try await service.currentAccount() != nil)
    #expect(try await service.currentAppleUserID() == nil)
}

@Test func matchingAppleRevocationClearsSessionAndRevokesOnlyLocalRefresh() async throws {
    let http = HTTPHarness { request in
        if request.url!.lastPathComponent == "logout" {
            #expect(request.url!.query == "scope=local")
            return .init(204, "")
        }
        return .init(appleToken())
    }
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: MemorySessionStore(), session: http.session)
    _ = try await service.signInWithApple(appleCredentials)
    try await service.invalidateAppleSession(userID: "different-subject")
    #expect(try await service.currentAccount() != nil)
    try await service.invalidateAppleSession(userID: appleSubject)
    #expect(try await service.currentAccount() == nil)
    #expect(try await service.currentAppleUserID() == nil)
}

@Test func appleFailureMapsProviderErrorsAndNeverInstallsARejectedSession() async throws {
    for (status, code, expected) in [(400, "provider_disabled", AuthenticationError.appleSignInUnavailable),
                                     (400, "validation_failed", .invalidAppleCredential),
                                     (429, "over_request_rate_limit", .rateLimited), (503, "unexpected_failure", .server(status: 503))] {
        let http = HTTPHarness { _ in .init(status, "{\"error_code\":\"\(code)\"}") }
        let store = MemorySessionStore()
        let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store, session: http.session)
        await #expect(throws: expected) { try await service.signInWithApple(appleCredentials) }
        #expect(try store.read() == nil)
    }
}

@Test func logoutPreventsLateAppleExchangeFromRestoringSession() async throws {
    let started = TestLatch(), release = TestLatch()
    let http = HTTPHarness { _ in
        await started.signal(); await release.wait()
        return .init(appleToken())
    }
    let store = MemorySessionStore()
    let service = try SupabaseAuthentication(baseURL: http.baseURL, clientKey: "client", store: store, session: http.session)
    let exchange = Task { try await service.signInWithApple(appleCredentials) }
    await started.wait()
    try await service.signOut()
    await release.signal()
    await #expect(throws: CancellationError.self) { try await exchange.value }
    #expect(try store.read() == nil)
}
