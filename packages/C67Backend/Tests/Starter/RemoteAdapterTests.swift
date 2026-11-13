import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing
import C67Domain
import C67Data

private final class RPCStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "test-client-key")
        let operation = request.url!.lastPathComponent
        var status = 200
        var payload = ""
        switch operation {
        case "list_rundowns":
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            payload = "[]"
        case "get_rundown":
            status = 404
            payload = #"{"code":"PT404","message":"Published version not found","details":null,"hint":null}"#
        case "create_trip":
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-traveller-token")
            payload = #"{"id":"31111111-1111-4111-8111-111111111111","source_version_id":"11111111-1111-4111-8111-111111111111","title":"Synthetic trip","starts_at":"2026-11-01T02:00:00.123+00:00","stops":[]}"#
        default:
            Issue.record("Unexpected RPC path: \(operation)")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func rpcUsesClientKeyAndTravellerJWTSeparatelyAndDecodesServerTime() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RPCStub.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let repository = try SupabaseRundownRepository(
        baseURL: #require(URL(string: "https://example.com")), clientKey: "test-client-key",
        session: session, accessToken: { "test-traveller-token" }
    )
    #expect(try await repository.listRundowns().isEmpty)
    await #expect(throws: RepositoryError.notFound) { try await repository.rundown(id: UUID()) }
    let trip = try await repository.createTrip(from: UUID(), startsAt: Date(), requestID: UUID())
    #expect(trip.title == "Synthetic trip")
    let expected = ISO8601DateFormatter().date(from: "2026-11-01T02:00:00Z")!
    #expect(abs(trip.startsAt.timeIntervalSince(expected) - 0.123) < 0.001)
}
