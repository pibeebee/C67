import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import C67Domain

/// Small RPC adapter for the starter contract. Domain has no vendor dependency.
public struct SupabaseRundownRepository: RundownRepository {
    private let baseURL: URL
    private let clientKey: String
    private let session: URLSession
    private let accessToken: @Sendable () async -> String?

    public init(baseURL: URL, clientKey: String, session: URLSession = .shared,
                accessToken: @escaping @Sendable () async -> String? = { nil }) throws {
        guard let scheme = baseURL.scheme, ["https", "http"].contains(scheme),
              let host = baseURL.host, !clientKey.isEmpty,
              baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/",
              scheme == "https" || ["localhost", "127.0.0.1", "::1"].contains(host) else {
            throw RepositoryError.invalidConfiguration
        }
        self.baseURL = baseURL
        self.clientKey = clientKey
        self.session = session
        self.accessToken = accessToken
    }

    public func listRundowns() async throws -> [Rundown] {
        try await rpc("list_rundowns", body: Empty())
    }
    public func rundown(id: UUID) async throws -> Rundown {
        try await rpc("get_rundown", body: Detail(p_version_id: id))
    }
    public func createTrip(from versionID: UUID, startsAt: Date, requestID: UUID) async throws -> Trip {
        guard let token = await accessToken(), !token.isEmpty else {
            throw RepositoryError.authenticationRequired
        }
        return try await rpc("create_trip", body: Create(p_version_id: versionID,
                             p_starts_at: startsAt, p_request_id: requestID), token: token)
    }

    private func rpc<Body: Encodable, Output: Decodable>(
        _ name: String, body: Body, token: String? = nil
    ) async throws -> Output {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue(clientKey, forHTTPHeaderField: "apikey")
        // Client keys may be opaque publishable keys; only JWTs belong in Authorization.
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RepositoryError.server(status: 0) }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { throw RepositoryError.authenticationRequired }
            if response.statusCode == 404 { throw RepositoryError.notFound }
            if response.statusCode == 409 { throw RepositoryError.idempotencyConflict }
            throw RepositoryError.server(status: response.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                       debugDescription: "Expected an ISO 8601 timestamp"))
            }
            return date
        }
        return try decoder.decode(Output.self, from: data)
    }
    private struct Empty: Encodable {}
    private struct Detail: Encodable { let p_version_id: UUID }
    private struct Create: Encodable {
        let p_version_id: UUID
        let p_starts_at: Date
        let p_request_id: UUID
    }
}
