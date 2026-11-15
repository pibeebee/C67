import Foundation
import XCTest
import C67Domain
import C67Data

/// Reads a private host-only cohort created by the approved server helper; no admin key enters the app.
@MainActor
final class SharedAuthIntegrationTests: XCTestCase {
    func testNativeSessionsAndTwoAccountTripPrivacyOnHomelab() async throws {
        guard ProcessInfo.processInfo.environment["C67_SHARED_AUTH_INTEGRATION"] == "1" else {
            throw XCTSkip("Prepare the exact synthetic shared cohort and opt in to homelab verification.")
        }
        let file = URL(fileURLWithPath: "/private/tmp/c67-native-auth-shared/cohort.json")
        let cohort = try JSONDecoder().decode(Cohort.self, from: Data(contentsOf: file))
        guard cohort.origin == "https://supabase.mrt.qzz.io", cohort.accounts.count == 2,
              cohort.accounts.allSatisfy({ $0.email.hasPrefix("c67-native-auth-check-") && $0.email.hasSuffix("@example.invalid") }) else {
            throw AuthenticationError.invalidResponse
        }
        let origin = URL(string: cohort.origin)!
        let namespace = "io.pibeebee.c67.shared-auth-tests." + UUID().uuidString
        let storeA = KeychainSessionStore(namespace: namespace + ".a", baseURL: origin)
        let storeB = KeychainSessionStore(namespace: namespace + ".b", baseURL: origin)
        defer { try? storeA.write(nil); try? storeB.write(nil) }
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": "C67-Native-Auth-Verification/1.0"]
        let http = URLSession(configuration: config)
        defer { http.invalidateAndCancel() }
        func auth(_ store: KeychainSessionStore) throws -> SupabaseAuthentication {
            try .init(baseURL: origin, clientKey: cohort.clientKey, store: store, session: http)
        }
        func repository(_ service: SupabaseAuthentication) throws -> SupabaseRundownRepository {
            try .init(baseURL: origin, clientKey: cohort.clientKey, session: http, authentication: service)
        }
        var a = try auth(storeA)
        let b = try auth(storeB)
        let userA = try await a.signIn(email: cohort.accounts[0].email, password: cohort.accounts[0].password)
        verify(userA.id == cohort.accounts[0].id)
        _ = try await b.signIn(email: cohort.accounts[1].email, password: cohort.accounts[1].password)
        verify(try await repository(a).listMyTrips().items.isEmpty)
        verify(try await repository(b).listMyTrips().items.isEmpty)
        let sources = try await repository(a).listRundowns()
        let source = try XCTUnwrap(sources.first)
        let requestID = UUID(), start = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 86400)
        let tripA = try await repository(a).createTrip(from: source.id, startsAt: start, requestID: requestID)
        verify(try await repository(a).createTrip(from: source.id, startsAt: start, requestID: requestID) == tripA)
        verify(try await repository(a).tripGraph(id: tripA.id).id == tripA.id)
        do { _ = try await repository(b).tripGraph(id: tripA.id); XCTFail("Foreign trip graph was exposed") }
        catch RepositoryError.notFound { }
        a = try auth(storeA)
        verify(try await a.currentAccount()?.id == userA.id)
        verify(try await a.refreshSession()?.id == userA.id)
        verify(try await repository(a).listMyTrips().items.contains(where: { $0.id == tripA.id }))
        let tripB = try await repository(b).createTrip(from: source.id, startsAt: start, requestID: UUID())
        do { _ = try await repository(a).tripGraph(id: tripB.id); XCTFail("Reverse foreign graph was exposed") }
        catch RepositoryError.notFound { }
        // Switch one app session to B; owner-scoped queries must not retain A's rows.
        _ = try await a.signIn(email: cohort.accounts[1].email, password: cohort.accounts[1].password)
        let switched = try await repository(a).listMyTrips().items
        verify(switched.contains(where: { $0.id == tripB.id }) && !switched.contains(where: { $0.id == tripA.id }))
        let saved = try XCTUnwrap(try storeA.read())
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let refreshToken = try XCTUnwrap(fields["refreshToken"] as? String)
        try await a.signOut()
        verify(try await a.currentAccount() == nil)
        do { _ = try await repository(a).listMyTrips(); XCTFail("Signed-out query was authorized") }
        catch RepositoryError.authenticationRequired { }
        var request = URLRequest(url: origin.appendingPathComponent("auth/v1/token"))
        request.url = URL(string: request.url!.absoluteString + "?grant_type=refresh_token")
        request.httpMethod = "POST"
        request.setValue(cohort.clientKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])
        let (_, response) = try await http.data(for: request)
        verify(!((200 ..< 300).contains((response as? HTTPURLResponse)?.statusCode ?? 0)))
        // local-scope logout must preserve B's independently created session.
        verify(try await b.refreshSession()?.id == cohort.accounts[1].id)
        try await b.signOut()
    }
}
private struct Cohort: Decodable {
    let origin: String
    let clientKey: String
    let accounts: [Account]
    struct Account: Decodable { let id: UUID; let email: String; let password: String }
}
private func verify(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value, file: file, line: line)
}
