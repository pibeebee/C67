import C67PlannerV5
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
    func credentials() async throws -> PocketCredentials
    func update(serverURL: String, token: String) async throws
}

/// Obtains the current user session for each request; never embeds a shared Pocket token.
public struct AuthenticatedPocketConnection: PocketConnectionProviding {
    private let serverURL: String
    private let authentication: any TravellerAuthentication

    public init(serverURL: String, authentication: any TravellerAuthentication) throws {
        self.serverURL = try PocketResearchClient.validatedURL(serverURL).absoluteString
        self.authentication = authentication
    }

    public func credentials() async throws -> PocketCredentials {
        guard let token = try await authentication.accessToken(), !token.isEmpty else { throw PlanningError.authenticationRequired }
        return .init(serverURL: serverURL, token: token)
    }

    public func update(serverURL _: String, token _: String) async throws {
        throw PlanningError.unavailable
    }
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
        let url = try PocketResearchClient.validatedURL(serverURL)
        let old = credentials()
        guard !token.isEmpty || !old.token.isEmpty else {
            throw PlanningError.failed("POCKET_CONNECTION_REQUIRED")
        }
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
    public var explanation: String?
    public var reportedReasoningEffort: String?
    public var providerProtocol: String?
    public init(slotID: String, requestedModel: String, reportedModel: String, explanation: String? = nil, reportedReasoningEffort: String? = nil, providerProtocol: String? = nil) {
        self.reportedReasoningEffort = reportedReasoningEffort; self.providerProtocol = providerProtocol
        self.explanation = explanation
        self.slotID = slotID; self.requestedModel = requestedModel; self.reportedModel = reportedModel
    }
    public func validated() throws -> Self {
        guard requestedModel == "cx/gpt-6-luna(max)",
              (["cx/gpt-6-luna(max)", "gpt-6-luna(max)"].contains(reportedModel)
                  || (reportedModel == "gpt-6-luna" && reportedReasoningEffort == "max" && providerProtocol == "responses")) else { throw PlanningError.invalidResponse }
        return self
    }
}

public struct PocketVisitResolution: Codable, Sendable {
    public struct Record: Codable, Sendable {
        public var placeID: UUID
        public var status: String
        public var reason: String?
        public var venue: Venue?
        public var recommendedMinutes: Int?
        public var preferredMinute: Int?
        public var recommendationReason: String?
        public var snapshotID: String?
    }
    public var reportedReasoningEffort: String? = nil
    public var providerProtocol: String? = nil
    public var resolvedAt: Date
    public var records: [Record]
    public var requestedModel: String
    public var reportedModel: String
}

struct PocketScheduleForecast: Sendable {
    var series: [PlannerV51WeatherSeries] = []
    var rain: [PlannerV5RainSample] = []
    var evidence: [PlanningEvidence] = []
}

public struct PocketPlanningServices: Sendable {
    var scheduleForecast: (@Sendable (PlanningPoint, Date, Date, Bool) async throws -> PocketScheduleForecast)?
    public var travel: @Sendable (Coordinate, Coordinate, Date, C67Domain.PlanningMode) async throws -> LegQuote
    public var weather: ItineraryPlanner.Weather
    public var advise: @Sendable (VisitAdviceRequest) async throws -> PocketAdviceSelection
    public var resolve: (@Sendable (PlanningInput, UUID) async throws -> PocketVisitResolution)?
    public var order: (@Sendable (PlanningInput, UUID) async throws -> PlanningExperiencePlan)?
    public var experience: (@Sendable ([PlanningInput], UUID) async throws -> [PlanningExperiencePlan])?
    public var foundationExperience: (@Sendable ([PlanningInput], UUID) async throws -> [PlanningExperiencePlan])?
    public var hours: (@Sendable (String) async -> PlanningHoursLookup)?
    var batchHours: (@Sendable ([String]) async throws -> [String: PlanningHoursLookup]?)?
    public var attribution: @Sendable () async throws -> PlanningEvidence?
    public init(travel: @escaping @Sendable (Coordinate, Coordinate, Date, C67Domain.PlanningMode) async throws -> LegQuote,
                weather: @escaping ItineraryPlanner.Weather,
                advise: @escaping @Sendable (VisitAdviceRequest) async throws -> PocketAdviceSelection,
                resolve: (@Sendable (PlanningInput, UUID) async throws -> PocketVisitResolution)? = nil,
                order: (@Sendable (PlanningInput, UUID) async throws -> PlanningExperiencePlan)? = nil,
                experience: (@Sendable ([PlanningInput], UUID) async throws -> [PlanningExperiencePlan])? = nil,
                foundationExperience: (@Sendable ([PlanningInput], UUID) async throws -> [PlanningExperiencePlan])? = nil,
                hours: (@Sendable (String) async -> PlanningHoursLookup)? = nil,
                attribution: @escaping @Sendable () async throws -> PlanningEvidence? = { nil }) {
        self.travel = travel; self.weather = weather; self.advise = advise
        self.attribution = attribution
        self.resolve = resolve
        self.order = order
        self.experience = experience
        self.foundationExperience = foundationExperience
        self.hours = hours
    }
}

enum PocketExternalAIRequest {
    @TaskLocal static var authorize: (@Sendable () async throws -> Void)?
}

public actor PocketResearchClient {
    private enum HoursBatchError: Error { case unsupported }

    func openingHours(placeIDs: [String]) async throws -> [String: PlanningHoursLookup]? {
        struct BatchRequest: Encodable { let placeIds: [String] }
        struct BatchResponse: Decodable { let results: [String: PlanningHoursLookup] }
        let placeIDs = Set(placeIDs).sorted()
        let failed: (String) -> [String: PlanningHoursLookup] = { status in
            Dictionary(uniqueKeysWithValues: placeIDs.map { ($0, .init(status: status)) })
        }
        do {
            let body = try JSONEncoder().encode(BatchRequest(placeIds: placeIDs))
            let data = try await fetch("v1/hours/batch", body: body, timeout: 100)
            let response = try JSONDecoder().decode(BatchResponse.self, from: data).results
            guard Set(response.keys) == Set(placeIDs) else { return failed("temporary_error") }
            return response.reduce(into: [:]) { results, row in
                results[row.key] = row.value.status != "available" || row.value.hours?.placeId == row.key
                    ? row.value : .init(status: "temporary_error")
            }
        } catch HoursBatchError.unsupported { return nil }
        catch PlanningError.rateLimited { return failed("rate_limited") }
        catch {
            try Task.checkCancellation()
            return failed("temporary_error")
        }
    }
    public func openingHours(placeID: String) async -> PlanningHoursLookup {
        guard placeID.range(of: "^I[0-9A-Fa-f]{1,63}$", options: .regularExpression) != nil else {
            return .init(status: "invalid_place_id")
        }
        do {
            let body = try JSONEncoder().encode(["placeId": placeID])
            let data = try await fetch("v1/hours/lookup", body: body)
            let result = try JSONDecoder().decode(PlanningHoursLookup.self, from: data)
            guard result.status != "available" || result.hours?.placeId == placeID else { return .init(status: "temporary_error") }
            return result
        } catch PlanningError.rateLimited { return .init(status: "rate_limited") }
        catch { return .init(status: "temporary_error") }
    }
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private let session: URLSession
    private let connection: any PocketConnectionProviding
    public init(connection: any PocketConnectionProviding) {
        self.connection = connection
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 25; configuration.timeoutIntervalForResource = 420
        session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }
    init(connection: any PocketConnectionProviding, session: URLSession) {
        self.connection = connection
        self.session = session
    }
    public static func validatedURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw EngineError.invalid("Enter the visit research server URL without credentials, query or fragment.")
        }
        #if DEBUG
            let permittedLocal = url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host.lowercased())
        #else
            let permittedLocal = false
        #endif
        guard url.scheme == "https" || permittedLocal else { throw EngineError.invalid("Use HTTPS for the Pocket server.") }
        return url
    }
    func fetch(_ path: String, body: Data? = nil, timeout: TimeInterval? = nil) async throws -> Data {
        let isOrdering = path.hasPrefix("v1/order")
        let credentials: PocketCredentials
        do { credentials = try await connection.credentials() }
        catch is CancellationError { throw CancellationError() }
        catch AuthenticationError.sessionExpired { throw PlanningError.authenticationRequired }
        catch AuthenticationError.passwordResetRequired { throw PlanningError.authenticationRequired }
        catch let error as PlanningError { throw error }
        catch { throw PlanningError.unavailable }
        guard !credentials.serverURL.isEmpty, !credentials.token.isEmpty else {
            if isOrdering { throw PlanningError.failed("POCKET_CONNECTION_REQUIRED") }
            throw EngineError.invalid("Configure the visit research server and read token in Account.")
        }
        let url: URL
        do { url = try Self.validatedURL(credentials.serverURL) }
        catch {
            if isOrdering { throw PlanningError.failed("POCKET_CONNECTION_REQUIRED") }
            throw error
        }
        var request = URLRequest(url: url.appending(path: path))
        request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = isOrdering ? 25 : 360
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let timeout { request.timeoutInterval = timeout }
        if body != nil, ["v1/order", "v1/visits/resolve", "v1/advice/visits"].contains(path) {
            try await PocketExternalAIRequest.authorize?()
        }
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, data.count <= 30_000_000 else { throw PlanningError.invalidResponse }
        if path == "v1/hours/batch", http.statusCode == 404 { throw HoursBatchError.unsupported }
        if isOrdering {
            struct ErrorResponse: Decodable { let code: String }
            let code = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.code
            switch code {
            case "ORDER_METHOD_UNSUPPORTED": throw PlanningError.failed("POCKET_ORDER_METHOD_UNSUPPORTED")
            case "INVALID_ORDER_INPUT": throw PlanningError.invalidInput
            case "REQUEST_CONFLICT": throw PlanningError.requestConflict
            case "AUTH_TEMPORARILY_UNAVAILABLE", "JOB_STORAGE_UNAVAILABLE": throw PlanningError.unavailable
            default: break
            }
            switch http.statusCode {
            case 400: throw PlanningError.failed("ORDER_REQUEST_REJECTED")
            case 401 where connection is AuthenticatedPocketConnection: throw PlanningError.authenticationRequired
            case 401, 403: throw PlanningError.failed("POCKET_CONNECTION_REJECTED")
            case 404 where body != nil: throw PlanningError.failed("POCKET_ORDER_ENDPOINT_MISSING")
            case 404: throw PlanningError.failed("ORDER_JOB_MISSING")
            case 422: throw PlanningError.failed("ORDER_REQUEST_REJECTED")
            default: break
            }
        }
        if http.statusCode == 429 { throw PlanningError.rateLimited }
        if isOrdering, [408, 504, 524].contains(http.statusCode) { throw PlanningError.timedOut }
        if http.statusCode == 408 || http.statusCode >= 500 { throw PlanningError.unavailable }
        guard (200 ..< 300).contains(http.statusCode) else { throw EngineError.invalid("Pocket server request failed. Check the connection and token; no replacement AI result was used.") }
        return data
    }
    public func resolve(_ input: PlanningInput, requestID: UUID) async throws -> PocketVisitResolution {
        struct Body: Encodable {
            var requestID: UUID
            var places: [PlanningPlace]
            var preferences: String
            var mainSpotID: UUID?
            var dates: [String]
        }
        struct Job: Decodable {
            var id: UUID
            var status: String
            var result: PocketVisitResolution?
        }
        struct Status: Decodable { var id: UUID; var status: String }
        let days = (1 ... 7).compactMap { TripClock.calendar.date(byAdding: .day, value: $0, to: Date()) }.map(TripClock.day)
        let body = Body(requestID: requestID, places: input.places, preferences: input.preferences,
                        mainSpotID: input.enginePreferences?.mainSpotID, dates: days)
        let data = try await fetch("v1/visits/resolve", body: Codec.encoder().encode(body))
        let initial = try JSONDecoder().decode(Status.self, from: data)
        guard initial.id == requestID else { throw PlanningError.invalidResponse }
        var status = initial
        while status.status == "running" || status.status == "queued" {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(2))
            let data = try await fetch("v1/visits/jobs/" + initial.id.uuidString.lowercased())
            status = try JSONDecoder().decode(Status.self, from: data)
            if status.status == "succeeded" {
                let job = try Codec.decoder().decode(Job.self, from: data)
                guard let result = job.result,
                      Set(result.records.map(\.placeID)) == Set(input.places.map(\.id)),
                      result.records.count == input.places.count else { throw PlanningError.invalidResponse }
                _ = try PocketAdviceSelection(slotID: "", requestedModel: result.requestedModel, reportedModel: result.reportedModel, reportedReasoningEffort: result.reportedReasoningEffort, providerProtocol: result.providerProtocol).validated()
                return result
            }
        }
        if status.status == "succeeded" {
            let completed = try await fetch("v1/visits/jobs/" + initial.id.uuidString.lowercased())
            guard let result = try Codec.decoder().decode(Job.self, from: completed).result,
                  Set(result.records.map(\.placeID)) == Set(input.places.map(\.id)),
                  result.records.count == input.places.count else { throw PlanningError.invalidResponse }
            _ = try PocketAdviceSelection(slotID: "", requestedModel: result.requestedModel, reportedModel: result.reportedModel, reportedReasoningEffort: result.reportedReasoningEffort, providerProtocol: result.providerProtocol).validated()
            return result
        }
        throw EngineError.invalid("Web research or Luna could not finish. Retry your selected places.")
    }

    public func advise(_ value: VisitAdviceRequest) async throws -> PocketAdviceSelection {
        struct Response: Decodable { var slotID: String; var requestedModel: String; var reportedModel: String; var explanation: String?; var reportedReasoningEffort: String?; var providerProtocol: String? }
        let response = try JSONDecoder().decode(Response.self, from: await fetch("v1/advice/visits", body: JSONEncoder().encode(value)))
        return try PocketAdviceSelection(slotID: response.slotID, requestedModel: response.requestedModel, reportedModel: response.reportedModel, explanation: response.explanation, reportedReasoningEffort: response.reportedReasoningEffort, providerProtocol: response.providerProtocol).validated()
    }
}
