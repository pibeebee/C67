import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing
import C67Domain
import C67Data

private let accountID = "91111111-1111-4111-8111-111111111111"
private func tokenJSON(_ access: String = "synthetic-access", refresh: String = "synthetic-refresh") -> String {
    """
    {"access_token":"\(access)","refresh_token":"\(refresh)","token_type":"bearer","expires_in":3600,
     "user":{"id":"\(accountID)","email":"traveller@example.test"}}
    """
}
private func auth(_ http: HTTPHarness, store: MemorySessionStore = .init(), clock: TestClock = .init()) throws -> SupabaseAuthentication {
    try .init(baseURL: http.baseURL, clientKey: "opaque-client-key", store: store,
              session: http.session, now: { clock.now() })
}

@Test func signInRestoresSecureSessionAndLogoutUsesLocalScope() async throws {
    let http = HTTPHarness { request in
        #expect(request.value(forHTTPHeaderField: "apikey") == "opaque-client-key")
        if request.url!.path.hasSuffix("logout") {
            #expect(request.url!.query == "scope=local")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access")
            return .init(204, "")
        }
        #expect(request.url!.query == "grant_type=password")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try requestBody(request)
        #expect(body["email"] as? String == "traveller@example.test")
        #expect(body["password"] as? String == "synthetic-password")
        return .init(tokenJSON())
    }
    let store = MemorySessionStore()
    let first = try auth(http, store: store)
    #expect(try await first.accessToken() == nil)
    let user = try await first.signIn(email: " traveller@example.test ", password: "synthetic-password")
    #expect(user.id.uuidString.lowercased() == accountID)
    let relaunched = try auth(http, store: store)
    #expect(try await relaunched.currentAccount() == user)
    #expect(await http.log.requests().count == 1)
    try await relaunched.signOut()
    #expect(try store.read() == nil)
    let afterLogout = try auth(http, store: store)
    #expect(try await afterLogout.accessToken() == nil)
}

@Test func concurrentRefreshRotatesOnceAndPersistsBeforeReturning() async throws {
    let http = HTTPHarness { request in
        if request.url!.query == "grant_type=refresh_token" {
            let body = try requestBody(request)
            #expect(body["refresh_token"] as? String == "synthetic-refresh")
            return .init(tokenJSON("rotated-access", refresh: "rotated-refresh"))
        }
        return .init(tokenJSON())
    }
    let store = MemorySessionStore(), clock = TestClock()
    let service = try auth(http, store: store, clock: clock)
    _ = try await service.signIn(email: "a@example.test", password: "synthetic")
    clock.advance(3590)
    try await withThrowingTaskGroup(of: String?.self) { group in
        for _ in 0 ..< 12 { group.addTask { try await service.accessToken() } }
        for try await value in group { #expect(value == "rotated-access") }
    }
    #expect(await http.log.requests().filter { $0.url!.query == "grant_type=refresh_token" }.count == 1)
    let relaunched = try auth(http, store: store, clock: clock)
    #expect(try await relaunched.accessToken() == "rotated-access")
}

@Test func refreshRejectionClearsSessionButTransientFailureRetainsRecovery() async throws {
    for status in [400, 401, 403, 422, 429, 503] {
        let http = HTTPHarness { request in
            request.url!.query == "grant_type=password" ? .init(tokenJSON()) : .init(status, "{}")
        }
        let store = MemorySessionStore(), clock = TestClock()
        let service = try auth(http, store: store, clock: clock)
        _ = try await service.signIn(email: "a@example.test", password: "synthetic")
        clock.advance(3601)
        if status == 429 || status == 503 {
            await #expect(throws: status == 429 ? AuthenticationError.rateLimited : .server(status: status)) { try await service.accessToken() }
            #expect(try store.read() != nil)
        } else {
            await #expect(throws: AuthenticationError.sessionExpired) { try await service.accessToken() }
            #expect(try store.read() == nil)
            #expect(try await service.accessToken() == nil)
        }
    }
}

@Test func logoutPreventsLateSignInFromRestoringSession() async throws {
    let started = TestLatch(), release = TestLatch()
    let http = HTTPHarness { _ in
        await started.signal(); await release.wait()
        return .init(tokenJSON())
    }
    let store = MemorySessionStore(), service = try auth(http, store: store)
    let login = Task { try await service.signIn(email: "a@example.test", password: "synthetic") }
    await started.wait()
    try await service.signOut()
    await release.signal()
    await #expect(throws: CancellationError.self) { try await login.value }
    #expect(try store.read() == nil)
    #expect(try await service.currentAccount() == nil)
}

@Test func logoutPreventsInFlightRefreshFromResurrectingSession() async throws {
    let started = TestLatch(), release = TestLatch()
    let http = HTTPHarness { request in
        if request.url!.path.hasSuffix("logout") { return .init(204, "") }
        if request.url!.query == "grant_type=refresh_token" {
            await started.signal(); await release.wait()
            return .init(tokenJSON("late-access"))
        }
        return .init(tokenJSON())
    }
    let clock = TestClock(), store = MemorySessionStore(), service = try auth(http, store: store, clock: clock)
    _ = try await service.signIn(email: "a@example.test", password: "synthetic")
    clock.advance(3590)
    let refresh = Task { try await service.accessToken() }
    await started.wait()
    try await service.signOut()
    await release.signal()
    await #expect(throws: CancellationError.self) { try await refresh.value }
    #expect(try await service.accessToken() == nil)
    #expect(try store.read() == nil)
}

@Test func invalidLoginAndStorageFailuresNeverExposeUsableSession() async throws {
    let rejected = HTTPHarness { _ in .init(400, #"{"error_code":"invalid_credentials"}"#) }
    let invalid = try auth(rejected)
    await #expect(throws: AuthenticationError.invalidCredentials) {
        try await invalid.signIn(email: "a@example.test", password: "synthetic")
    }
    #expect(try await invalid.accessToken() == nil)
    let http = HTTPHarness { _ in .init(tokenJSON()) }
    let store = MemorySessionStore()
    store.failWrites()
    let service = try auth(http, store: store)
    await #expect(throws: AuthenticationError.storageUnavailable) {
        try await service.signIn(email: "a@example.test", password: "synthetic")
    }
    #expect(try await service.accessToken() == nil)
}

@Test func failedRefreshPersistenceFailsEveryWaiter() async throws {
    let http = HTTPHarness { _ in .init(tokenJSON()) }
    let store = MemorySessionStore(), clock = TestClock(), service = try auth(http, store: store, clock: clock)
    _ = try await service.signIn(email: "a@example.test", password: "synthetic")
    clock.advance(3601); store.failWrites()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0 ..< 4 { group.addTask {
            await #expect(throws: AuthenticationError.storageUnavailable) { try await service.accessToken() }
        } }
    }
}

@Test func corruptSessionCanBeRemovedAndOfflineLogoutIsExplicit() async throws {
    let http = HTTPHarness { request in
        if request.url!.path.hasSuffix("logout") { throw URLError(.notConnectedToInternet) }
        return .init(tokenJSON())
    }
    let store = MemorySessionStore(Data("invalid-record".utf8)), service = try auth(http, store: store)
    await #expect(throws: AuthenticationError.storageUnavailable) { try await service.accessToken() }
    try await service.signOut()
    #expect(try store.read() == nil)
    _ = try await service.signIn(email: "a@example.test", password: "synthetic")
    await #expect(throws: AuthenticationError.remoteSignOutFailed) { try await service.signOut() }
    #expect(try store.read() == nil)
    #expect(try await service.currentAccount() == nil)
}

@Test func cancellingOneRefreshWaiterDoesNotCancelOtherRequests() async throws {
    let started = TestLatch(), release = TestLatch()
    let http = HTTPHarness { request in
        if request.url!.query == "grant_type=refresh_token" {
            await started.signal(); await release.wait()
            return .init(tokenJSON("rotated-access"))
        }
        return .init(tokenJSON())
    }
    let clock = TestClock(), service = try auth(http, clock: clock)
    _ = try await service.signIn(email: "a@example.test", password: "synthetic")
    clock.advance(3590)
    let cancelled = Task { try await service.accessToken() }
    await started.wait()
    cancelled.cancel()
    let other = Task { try await service.accessToken() }
    await release.signal()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(try await other.value == "rotated-access")
}

@Test func staleTokenRejectionDoesNotDeleteNewerSession() async throws {
    let http = HTTPHarness { request in
        let body = try requestBody(request)
        return .init(tokenJSON(body["email"] as? String == "second@example.test" ? "new-access" : "old-access"))
    }
    let service = try auth(http)
    _ = try await service.signIn(email: "first@example.test", password: "synthetic")
    _ = try await service.signIn(email: "second@example.test", password: "synthetic")
    try await service.invalidateSession(rejectedToken: "old-access")
    #expect(try await service.accessToken() == "new-access")
    try await service.invalidateSession(rejectedToken: "new-access")
    #expect(try await service.currentAccount() == nil)
}
