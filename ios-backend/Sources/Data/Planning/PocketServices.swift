import Foundation
import Security
import C67Domain
import PocketEngine

public struct PocketCredentials: Sendable {
    public var serverURL: String
    public var token: String
    public init(serverURL: String, token: String) { self.serverURL = serverURL; self.token = token }
}

public protocol PocketConnectionProviding: Sendable {
    func credentials() async -> PocketCredentials
    func update(serverURL: String, token: String) async throws
}

public actor PocketConnectionStore: PocketConnectionProviding {
    private let defaultURL: String
    private let namespace: String
    public init(serverURL: String = "", namespace: String = "io.pibeebee.c67.pocket") {
        defaultURL = serverURL; self.namespace = namespace
    }
    public func credentials() -> PocketCredentials {
        var query = keychainQuery
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let token = status == errSecSuccess ? (result as? Data).map { String(decoding: $0, as: UTF8.self) } ?? "" : ""
        return .init(serverURL: UserDefaults.standard.string(forKey: namespace + ".url") ?? defaultURL, token: token)
    }
    public func update(serverURL: String, token: String) throws {
        let url = try PocketCatalogClient.validatedURL(serverURL)
        let old = credentials()
        if !old.token.isEmpty, let previous = URL(string: old.serverURL),
           (previous.host != url.host || previous.port != url.port || previous.scheme != url.scheme), token.isEmpty {
            throw EngineError.invalid("Enter a read token for the new server. The previous server's token was not transferred.")
        }
        if !token.isEmpty {
            let data = Data(token.utf8)
            let status = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var insertion = keychainQuery
                insertion[kSecValueData as String] = data
                insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw PlanningError.unavailable }
            } else if status != errSecSuccess { throw PlanningError.unavailable }
        }
        UserDefaults.standard.set(serverURL, forKey: namespace + ".url")
    }
    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: namespace,
         kSecAttrAccount as String: "catalog-read-token"]
    }
}

public struct PocketAdviceSelection: Sendable {
    public var slotID: String
    public var requestedModel: String
    public var reportedModel: String
    public init(slotID: String, requestedModel: String, reportedModel: String) {
        self.slotID = slotID; self.requestedModel = requestedModel; self.reportedModel = reportedModel
    }
    public func validated() throws -> Self {
        guard requestedModel == "cx/gpt-6-luna(max)",
              ["cx/gpt-6-luna(max)", "gpt-6-luna(max)"].contains(reportedModel) else { throw PlanningError.invalidResponse }
        return self
    }
}

public struct PocketPlanningServices: Sendable {
    public var catalog: @Sendable () async throws -> Catalog
    public var discover: @Sendable (Profile, VisitArea) async throws -> [Venue]
    public var travel: @Sendable (Coordinate, Coordinate, Date, C67Domain.PlanningMode) async throws -> LegQuote
    public var weather: ItineraryPlanner.Weather
    public var advise: @Sendable (VisitAdviceRequest) async throws -> PocketAdviceSelection
    public var attribution: @Sendable () async throws -> PlanningEvidence?
    public init(catalog: @escaping @Sendable () async throws -> Catalog,
                discover: @escaping @Sendable (Profile, VisitArea) async throws -> [Venue],
                travel: @escaping @Sendable (Coordinate, Coordinate, Date, C67Domain.PlanningMode) async throws -> LegQuote,
                weather: @escaping ItineraryPlanner.Weather,
                advise: @escaping @Sendable (VisitAdviceRequest) async throws -> PocketAdviceSelection,
                attribution: @escaping @Sendable () async throws -> PlanningEvidence? = { nil }) {
        self.catalog = catalog; self.discover = discover; self.travel = travel; self.weather = weather; self.advise = advise
        self.attribution = attribution
    }
}

public actor PocketCatalogClient {
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private let session: URLSession
    private let connection: any PocketConnectionProviding
    public init(connection: any PocketConnectionProviding) {
        self.connection = connection
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 25; configuration.timeoutIntervalForResource = 100
        session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }
    public static func validatedURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw EngineError.invalid("Enter the catalog server URL without credentials, query or fragment.")
        }
        #if DEBUG
            let permittedLocal = url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host.lowercased())
        #else
            let permittedLocal = false
        #endif
        guard url.scheme == "https" || permittedLocal else { throw EngineError.invalid("Use HTTPS for the Pocket server.") }
        return url
    }
    private func fetch(_ path: String, body: Data? = nil) async throws -> Data {
        let credentials = await connection.credentials()
        guard !credentials.serverURL.isEmpty, !credentials.token.isEmpty else {
            throw EngineError.invalid("Configure the Pocket catalog server and read token in Account before using Luna.")
        }
        var request = URLRequest(url: try Self.validatedURL(credentials.serverURL).appending(path: path))
        request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 95
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode), data.count <= 30_000_000 else {
            throw EngineError.invalid("Pocket server request failed. Check the connection and retry; no replacement AI result was used.")
        }
        return data
    }
    public func catalog() async throws -> Catalog {
        let credentials = await connection.credentials()
        if credentials.serverURL.isEmpty || credentials.token.isEmpty { return try Catalog.bundled().validated() }
        return try Codec.decoder().decode(Catalog.self, from: await fetch("v1/catalog")).validated()
    }
    public func advise(_ value: VisitAdviceRequest) async throws -> PocketAdviceSelection {
        struct Response: Decodable { var slotID: String; var requestedModel: String; var reportedModel: String }
        let response = try JSONDecoder().decode(Response.self, from: await fetch("v1/advice/visits", body: JSONEncoder().encode(value)))
        return try PocketAdviceSelection(slotID: response.slotID, requestedModel: response.requestedModel, reportedModel: response.reportedModel).validated()
    }
}
