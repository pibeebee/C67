import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import C67Domain

/// RPC adapter for the published C67 contract. Domain has no vendor dependency.
public struct SupabaseRundownRepository: RundownRepository {
    let authentication: SupabaseAuthentication?
    let connection: SupabaseConnection
    private let onUnauthorized: @Sendable (String) async throws -> Void
    let accessToken: @Sendable () async throws -> String?

    public init(baseURL: URL, clientKey: String, session: URLSession = .shared, authentication: SupabaseAuthentication? = nil,
                accessToken: @escaping @Sendable () async throws -> String? = { nil },
                onUnauthorized: @escaping @Sendable (String) async throws -> Void = { _ in }) throws {
        connection = try .init(baseURL: baseURL, clientKey: clientKey, session: session)
        self.authentication = authentication
        self.accessToken = accessToken
        self.onUnauthorized = onUnauthorized
    }

    public func listRundowns() async throws -> [Rundown] {
        try await rpc("list_rundowns", body: Empty())
    }
    public func rundown(id: UUID) async throws -> Rundown {
        try await rpc("get_rundown", body: Detail(p_version_id: id))
    }
    public func createTrip(from versionID: UUID, startsAt: Date, requestID: UUID) async throws -> Trip {
        try await privateRPC("create_trip", body: Create(p_version_id: versionID,
                                                         p_starts_at: startsAt, p_request_id: requestID))
    }

    func privateRPC<Body: Encodable, Output: Decodable>(_ name: String, body: Body) async throws -> Output {
        if let authentication {
            guard let ticket = try await authentication.authorization() else { throw RepositoryError.authenticationRequired }
            let result: Output = try await rpc(name, body: body, token: ticket.token)
            guard await authentication.isCurrent(ticket) else { throw CancellationError() }
            return result
        }
        guard let token = try await accessToken(), !token.isEmpty else { throw RepositoryError.authenticationRequired }
        return try await rpc(name, body: body, token: token)
    }

    func rpc<Body: Encodable, Output: Decodable>(
        _ name: String, body: Body, token: String? = nil
    ) async throws -> Output {
        var request = connection.request(path: "rest/v1/rpc/\(name)", token: token)
        request.httpBody = try SupabaseConnection.encoder().encode(body)
        let (data, response) = try await connection.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RepositoryError.server(status: 0) }
        guard (200 ..< 300).contains(response.statusCode) else {
            switch response.statusCode {
            case 400: throw RepositoryError.invalidInput
            case 401:
                if let token {
                    if let authentication { try await authentication.invalidateSession(rejectedToken: token) }
                    else { try await onUnauthorized(token) }
                }
                throw RepositoryError.authenticationRequired
            case 403: throw RepositoryError.accessDenied
            case 404: throw RepositoryError.notFound
            case 409: throw RepositoryError.idempotencyConflict
            default: throw RepositoryError.server(status: response.statusCode)
            }
        }
        return try SupabaseConnection.decoder().decode(Output.self, from: data)
    }
    private struct Empty: Encodable {}
    private struct Detail: Encodable { let p_version_id: UUID }
    private struct Create: Encodable {
        let p_version_id: UUID
        let p_starts_at: Date
        let p_request_id: UUID
    }
}
