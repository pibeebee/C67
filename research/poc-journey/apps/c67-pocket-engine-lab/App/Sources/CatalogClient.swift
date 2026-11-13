import Foundation
import Security
import PocketEngine

enum TokenVault {
    private static let service = "giovanchristoffel.c67-pocket-engine.catalog"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "read-token", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func write(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "read-token"]
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query; insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw EngineError.invalid("Token tidak dapat disimpan ke Keychain.") }
        } else if status != errSecSuccess { throw EngineError.invalid("Token Keychain tidak dapat diperbarui.") }
    }
}

struct ProviderHit: Decodable, Identifiable, Sendable {
    var id: String
    var name: String
    var address: String
    var coordinate: Coordinate
    var hoursSummary: String
}
struct ProviderResponse: Decodable, Sendable { var results: [ProviderHit]; var notice: String }

actor CatalogClient {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil; c.httpCookieStorage = nil; c.timeoutIntervalForRequest = 25; c.timeoutIntervalForResource = 110
        return URLSession(configuration: c, delegate: NoRedirect(), delegateQueue: nil)
    }()
    static func validate(_ value: String) throws -> URL {
        guard let url = URL(string: value), let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw EngineError.invalid("Isi URL server tanpa username, password, query, atau fragment.")
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        let privateIP = parts.count == 4 && parts.allSatisfy { (0 ... 255).contains($0) } &&
            (parts[0] == 10 || parts[0] == 127 || parts[0] == 192 && parts[1] == 168 || parts[0] == 172 && (16 ... 31).contains(parts[1]))
        guard url.scheme == "https" || url.scheme == "http" && (host == "localhost" || host == "[::1]" || host.hasSuffix(".local") || privateIP) else {
            throw EngineError.invalid("Gunakan HTTPS, atau HTTP untuk server lokal/LAN saja.")
        }
        return url
    }
    private func fetch(base: String, path: String, token: String, body: Data? = nil, advice: Bool = false) async throws -> Data {
        guard !token.isEmpty else { throw EngineError.invalid("Isi token baca katalog pada Pengaturan.") }
        let url = try Self.validate(base).appending(path: path)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            if advice { request.timeoutInterval = 95 }
        }
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200 ..< 300).contains(status) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw EngineError.invalid("Server katalog HTTP \(status). Periksa alamat, token, dan konfigurasi provider bila digunakan.")
        }
        guard data.count <= 30_000_000 else { throw EngineError.invalid("Katalog melampaui batas ukuran PoC.") }
        return data
    }
    func catalog(base: String, token: String) async throws -> Catalog {
        let data = try await fetch(base: base, path: "v1/catalog", token: token)
        return try Codec.decoder().decode(Catalog.self, from: data).validated()
    }
    struct AdviceResponse: Decodable, Sendable {
        var slotID: String
        var requestedModel: String
        var reportedModel: String
        var elapsedMS: Double
    }
    func visitAdvice(base: String, token: String, request: VisitAdviceRequest) async throws -> AdviceResponse {
        let data = try await fetch(base: base, path: "v1/advice/visits", token: token, body: JSONEncoder().encode(request), advice: true)
        let result = try JSONDecoder().decode(AdviceResponse.self, from: data)
        guard result.requestedModel == "cx/gpt-6-luna(max)", ["cx/gpt-6-luna(max)", "gpt-6-luna(max)"].contains(result.reportedModel) else {
            throw EngineError.invalid("Identitas model respons tidak sesuai Luna Max. Jadwal belum diterbitkan.")
        }
        return result
    }
    func tomtom(base: String, token: String, query: String, coordinate: Coordinate) async throws -> ProviderResponse {
        let data = try await fetch(base: base, path: "v1/providers/tomtom/search", token: token,
                                   body: try JSONSerialization.data(withJSONObject: ["query": query, "latitude": String(coordinate.latitude), "longitude": String(coordinate.longitude)]))
        return try JSONDecoder().decode(ProviderResponse.self, from: data)
    }
}
