import Foundation

public enum ContextError: Error, LocalizedError, Sendable {
    case invalid(String), missingKey, provider(Int, String), budget, response
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        case .missingKey: "Set GOOGLE_PLACES_API_KEY in the private local configuration."
        case .provider(let status, let code): "Google Places HTTP \(status) (\(code)); no automatic retry or fallback."
        case .budget: "Google Places request budget exhausted."
        case .response: "Google Places response incomplete, mismatched, or invalid."
        }
    }
}
public enum ContextJSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }
}
public struct PlacesConfiguration: Sendable {
    let apiKey: String
    public let maxRequests: Int
    public init(apiKey: String, maxRequests: Int = 20) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ContextError.missingKey }
        guard apiKey.count <= 256, !apiKey.contains(where: { $0.isWhitespace || $0.isNewline }), (1 ... 100).contains(maxRequests) else { throw ContextError.invalid("Invalid Places configuration") }
        self.apiKey = apiKey; self.maxRequests = maxRequests
    }
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard let limit = Int(environment["GOOGLE_PLACES_MAX_REQUESTS"] ?? "20") else { throw ContextError.invalid("GOOGLE_PLACES_MAX_REQUESTS must be an integer") }
        try self.init(apiKey: environment["GOOGLE_PLACES_API_KEY"] ?? "", maxRequests: limit)
    }
}
public struct PlacesHTTPResponse: Sendable {
    public var status: Int; public var data: Data
    public init(status: Int, data: Data) { self.status = status; self.data = data }
}
@MainActor public protocol PlacesHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> PlacesHTTPResponse
}
@MainActor public final class PlacesURLSession: PlacesHTTPTransport {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private let session: URLSession
    public init() {
        let c = URLSessionConfiguration.ephemeral; c.urlCache = nil; c.httpCookieStorage = nil
        c.timeoutIntervalForRequest = 20; c.timeoutIntervalForResource = 25
        session = URLSession(configuration: c, delegate: NoRedirect(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> PlacesHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 2 * 1024 * 1024 else { throw ContextError.response }
        return .init(status: http.statusCode, data: data)
    }
}
public struct PlacesText: Codable, Sendable { public var text: String?; public var languageCode: String? }
public struct PlacesCoordinate: Codable, Sendable { public var latitude: Double; public var longitude: Double }
public struct PlacesDate: Codable, Sendable { public var year: Int?; public var month: Int?; public var day: Int? }
public struct PlacesPoint: Codable, Sendable {
    public var date: PlacesDate?; public var truncated: Bool?; public var day: Int?; public var hour: Int?; public var minute: Int?
}
public struct PlacesPeriod: Codable, Sendable { public var open: PlacesPoint?; public var close: PlacesPoint? }
public struct PlacesSpecialDay: Codable, Sendable { public var date: PlacesDate?; public var exceptionalHours: Bool? }
public struct PlacesHours: Codable, Sendable {
    public var openNow: Bool?; public var periods: [PlacesPeriod]?; public var weekdayDescriptions: [String]?
    public var specialDays: [PlacesSpecialDay]?
}
public struct PlacesTimeZone: Codable, Sendable { public var id: String?; public var version: String? }
public struct PlacesAuthor: Codable, Sendable { public var displayName: String?; public var uri: String?; public var photoUri: String? }
public struct PlacesReview: Codable, Sendable {
    public var name: String?; public var text: PlacesText?; public var originalText: PlacesText?; public var rating: Double?
    public var authorAttribution: PlacesAuthor?; public var publishTime: String?; public var visitDate: PlacesDate?; public var googleMapsUri: String?
}
public struct PlacesAttribution: Codable, Sendable { public var provider: String?; public var providerUri: String? }
public struct GooglePlace: Codable, Sendable {
    public var id: String?; public var displayName: PlacesText?; public var formattedAddress: String?; public var location: PlacesCoordinate?
    public var businessStatus: String?; public var googleMapsUri: String?; public var types: [String]?; public var primaryType: String?
    public var utcOffsetMinutes: Int?; public var timeZone: PlacesTimeZone?
    public var currentOpeningHours: PlacesHours?; public var regularOpeningHours: PlacesHours?
    public var rating: Double?; public var userRatingCount: Int?; public var outdoorSeating: Bool?
    public var reviews: [PlacesReview]?; public var attributions: [PlacesAttribution]?
}
public struct PlaceSnapshot: Codable, Sendable {
    public var place: GooglePlace; public var fetchedAt: Date; public var expiresAt: Date; public var fieldMask: String
    public var source: String; public var attribution: String
    public init(place: GooglePlace, fetchedAt: Date, fieldMask: String, source: String = "Google Places API (New)") {
        self.place = place; self.fetchedAt = fetchedAt; expiresAt = fetchedAt.addingTimeInterval(900); self.fieldMask = fieldMask
        self.source = source; attribution = "Google Maps; retain provider/review author attributions and links."
    }
}
@MainActor public final class GooglePlacesClient {
    public static let searchMask = "places.id,places.displayName,places.formattedAddress,places.location,places.businessStatus,places.googleMapsUri"
    public static let hoursMask = "id,displayName,formattedAddress,location,businessStatus,googleMapsUri,types,primaryType,utcOffsetMinutes,timeZone,currentOpeningHours,regularOpeningHours,attributions"
    public static let experienceMask = hoursMask + ",reviews,rating,userRatingCount,outdoorSeating"
    public private(set) var requests = 0
    private let configuration: PlacesConfiguration; private let transport: any PlacesHTTPTransport
    private var inFlight = false
    public init(configuration: PlacesConfiguration, transport: any PlacesHTTPTransport = PlacesURLSession()) {
        self.configuration = configuration; self.transport = transport
    }
    nonisolated public static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 256 && id.utf8.allSatisfy { (65 ... 90).contains($0) || (97 ... 122).contains($0) || (48 ... 57).contains($0) || $0 == 45 || $0 == 95 }
    }
    private func call(path: String, method: String, mask: String, body: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        guard !inFlight else { throw ContextError.invalid("Google Places request already in progress; single-provider concurrency") }
        guard requests < configuration.maxRequests else { throw ContextError.budget }
        inFlight = true; defer { inFlight = false }
        requests += 1
        var r = URLRequest(url: URL(string: "https://places.googleapis.com/v1/" + path)!)
        r.httpMethod = method; r.httpBody = body; r.timeoutInterval = 20
        r.setValue(configuration.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        r.setValue(mask, forHTTPHeaderField: "X-Goog-FieldMask"); r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.cachePolicy = .reloadIgnoringLocalCacheData
        let response: PlacesHTTPResponse
        do { response = try await transport.send(r) }
        catch { if error is CancellationError { throw CancellationError() }; try Task.checkCancellation(); throw ContextError.invalid("Google Places transport failed; details suppressed to protect credentials.") }
        try Task.checkCancellation()
        guard response.data.count <= 2 * 1024 * 1024 else { throw ContextError.response }
        guard response.status == 200 else {
            // Do not emit raw provider bodies, request headers, URLs with credentials, or API keys.
            let statuses = [400: "INVALID_ARGUMENT", 401: "UNAUTHENTICATED", 403: "PERMISSION_DENIED", 404: "NOT_FOUND", 429: "RESOURCE_EXHAUSTED"]
            throw ContextError.provider(response.status, statuses[response.status] ?? "PROVIDER_ERROR")
        }
        return response.data
    }
    public func search(_ text: String, limit: Int = 5) async throws -> [GooglePlace] {
        try await searchPage(text, limit: limit).places
    }
    public func searchPage(_ text: String, limit: Int = 5, pageToken: String? = nil) async throws -> (places: [GooglePlace], nextPageToken: String?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 300, (1 ... 5).contains(limit),
              pageToken.map({ !$0.isEmpty && $0.count <= 4096 }) ?? true else { throw ContextError.invalid("Search requires 1–300 characters and limit 1–5") }
        var body: [String: Any] = ["textQuery": text, "pageSize": limit, "languageCode": "id", "regionCode": "ID",
                                   "locationRestriction": ["rectangle": ["low": ["latitude": -6.6, "longitude": 106.5], "high": ["latitude": -5.9, "longitude": 107.2]]]]
        if let pageToken { body["pageToken"] = pageToken }
        let data = try await call(path: "places:searchText", method: "POST", mask: Self.searchMask + ",nextPageToken", body: JSONSerialization.data(withJSONObject: body))
        struct Result: Decodable { var places: [GooglePlace]?; var nextPageToken: String? }
        let result = try JSONDecoder().decode(Result.self, from: data), places = result.places ?? []
        guard places.count <= limit, Set(places.compactMap(\.id)).count == places.count,
              places.allSatisfy({ $0.id.map(Self.validID) == true }) else { throw ContextError.response }
        let next = result.nextPageToken.flatMap{ !$0.isEmpty && $0.count <= 4096 && $0 != pageToken ? $0 : nil }
        return (places, next)
    }
    public func details(_ id: String, includeReviews: Bool = false, now: Date = .now) async throws -> PlaceSnapshot {
        guard Self.validID(id) else { throw ContextError.invalid("Invalid Google place ID; paths and URLs are not accepted") }
        let mask = includeReviews ? Self.experienceMask : Self.hoursMask
        let data = try await call(path: "places/" + id + "?languageCode=id&regionCode=ID", method: "GET", mask: mask)
        var p = try JSONDecoder().decode(GooglePlace.self, from: data)
        guard p.id == id, let name = p.displayName?.text,!name.isEmpty, let point = p.location,
              point.latitude.isFinite, point.longitude.isFinite, (-90 ... 90).contains(point.latitude), (-180 ... 180).contains(point.longitude) else { throw ContextError.response }
        if !includeReviews { p.reviews = nil; p.rating = nil; p.userRatingCount = nil; p.outdoorSeating = nil }
        else if (p.reviews?.count ?? 0) > 5 { throw ContextError.response }
        return .init(place: p, fetchedAt: now, fieldMask: mask)
    }
}
