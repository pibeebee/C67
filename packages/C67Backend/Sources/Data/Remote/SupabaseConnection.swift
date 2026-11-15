import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import C67Domain

/// Shared URL validation and coding for Auth and the RPC adapter.
struct SupabaseConnection: Sendable {
    let baseURL: URL
    let clientKey: String
    let session: URLSession

    init(baseURL: URL, clientKey: String, session: URLSession) throws {
        guard let scheme = baseURL.scheme, ["https", "http"].contains(scheme),
              let host = baseURL.host, !clientKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/",
              scheme == "https" || ["localhost", "127.0.0.1", "::1"].contains(host) else {
            throw RepositoryError.invalidConfiguration
        }
        self.baseURL = baseURL; self.clientKey = clientKey; self.session = session
    }

    func request(path: String, query: [URLQueryItem] = [], token: String? = nil) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(clientKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Keep subsecond command identity when retrying a create operation.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
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
        return decoder
    }
}
