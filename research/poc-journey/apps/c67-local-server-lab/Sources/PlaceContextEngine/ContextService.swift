import Foundation

public struct GoogleContextEvaluationInput: Codable, Sendable {
    public var request: VisitContextRequest; public var weather: VisitWeatherContext?; public var includeReviews: Bool
    public init(request: VisitContextRequest, weather: VisitWeatherContext? = nil, includeReviews: Bool = false) { self.request = request; self.weather = weather; self.includeReviews = includeReviews }
    enum CodingKeys: String, CodingKey { case request, weather, includeReviews }
    public init(from decoder: Decoder)throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        request = try c.decode(VisitContextRequest.self, forKey: .request); weather = try c.decodeIfPresent(VisitWeatherContext.self, forKey: .weather)
        includeReviews = try c.decodeIfPresent(Bool.self, forKey: .includeReviews) ?? false
    }
}
@MainActor public enum GoogleContextService {
    public static func evaluate(_ input: GoogleContextEvaluationInput, client: GooglePlacesClient, now: Date = .now) async throws -> VisitContextResult {
        try input.request.validate()
        guard input.request.identityConfirmed else { throw ContextError.invalid("Select and explicitly confirm the Google place ID before requesting details") }
        let snapshot = try await client.details(input.request.placeID, includeReviews: input.includeReviews, now: now)
        return try VisitContextEngine.evaluate(snapshot: snapshot, request: input.request, weather: input.weather, now: now)
    }
}

/// Synthetic HTTP-shaped end-to-end demo; no credentials, network or real venue claims.
@MainActor public enum PlaceContextDemo {
    public static let now = Date(timeIntervalSince1970: 1794009600) // 2026-11-07 00:00 UTC
    public static let day = "2026-11-09"
    public static func fixture(id: String) -> Data {
        let periods = (0 ... 6).map { d in ["open": ["day": d, "hour": 8, "minute": 0], "close": ["day": d, "hour": 18, "minute": 0]] }
        let park = id == "synthetic-park"
        let object: [String: Any] = ["id": id, "displayName": ["text": park ? "SYNTHETIC Park" : "SYNTHETIC Museum", "languageCode": "en"],
                                     "location": ["latitude": -6.2, "longitude": 106.83], "formattedAddress": "Synthetic fixture, not a real destination",
                                     "businessStatus": "OPERATIONAL", "timeZone": ["id": "Asia/Jakarta"], "utcOffsetMinutes": 420,
                                     "regularOpeningHours": ["periods": periods], "googleMapsUri": "https://example.invalid/synthetic-place",
                                     "reviews": park ? [["name": "synthetic-review-1", "originalText": ["text": "Hari kerja pagi sepi dan tenang.", "languageCode": "id"], "publishTime": "2026-11-01T00:00:00Z", "authorAttribution": ["displayName": "Synthetic author"]]] : []]
        return try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }
    public final class Transport: PlacesHTTPTransport {
        public private(set) var calls = 0
        public init() {}
        public func send(_ request: URLRequest) async throws -> PlacesHTTPResponse {
            calls += 1
            if request.url!.path.hasSuffix("places:searchText") {
                let objects = try ["synthetic-park", "synthetic-museum"].map { try JSONSerialization.jsonObject(with: fixture(id: $0)) }
                return .init(status: 200, data: try JSONSerialization.data(withJSONObject: ["places": objects]))
            }
            let id = request.url!.lastPathComponent
            return .init(status: 200, data: fixture(id: id))
        }
    }
    public struct FixedTravel: ContextTravelProvider {
        public init() {}
        public func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
            .init(seconds: 900, departure: departure, source: "SYNTHETIC fixed 15-minute travel; not Apple or Google ETA")
        }
    }
    public struct Output: Codable, Sendable {
        public var evidenceMode: String; public var simulatedHTTPCalls: Int
        public var quietReader: ContextItineraryResult; public var afternoonPhotographer: ContextItineraryResult; public var rainAvoider: ContextItineraryResult
    }
    public static func run() async throws -> Output {
        let transport = Transport(); let client = GooglePlacesClient(configuration: try .init(apiKey: "synthetic-not-a-real-key"), transport: transport)
        _ = try await client.search("SYNTHETIC example", limit: 2)
        var park = try await client.details("synthetic-park", includeReviews: true, now: now)
        var museum = try await client.details("synthetic-museum", now: now)
        park.source = "SYNTHETIC Google-shaped fixture"; museum.source = park.source
        let midnight = ContextClock.day(day)!
        var parkRequest = VisitContextRequest(placeID: "synthetic-park", day: day)
        parkRequest.identityConfirmed = true; parkRequest.seeksQuiet = true
        parkRequest.exposure = .outdoor; parkRequest.exposureEvidence = "SYNTHETIC area observation"
        var museumRequest = VisitContextRequest(placeID: "synthetic-museum", day: day)
        museumRequest.identityConfirmed = true; museumRequest.exposure = .indoor; museumRequest.exposureEvidence = "SYNTHETIC area observation"
        func input(_ p: VisitContextRequest, weather: VisitWeatherContext? = nil) -> ContextPlanRequest {
            .init(originID: "origin", returnID: "origin", departure: midnight.addingTimeInterval(9 * 3600), deadline: midnight.addingTimeInterval(18 * 3600), stops: [.init(snapshot: park, request: p, weather: weather), .init(snapshot: museum, request: museumRequest)])
        }
        let quiet = try await ContextItineraryPlanner.plan(input(parkRequest), provider: FixedTravel(), now: now)
        parkRequest.seeksQuiet = false; parkRequest.preferredTime = .init(earliest: 15 * 60, latest: 16 * 60)
        let photographer = try await ContextItineraryPlanner.plan(input(parkRequest), provider: FixedTravel(), now: now)
        parkRequest.preferredTime = nil; parkRequest.avoidRain = true
        let weather = VisitWeatherContext(source: "SYNTHETIC hourly forecast", fetchedAt: now, expiresAt: now.addingTimeInterval(900), hours: (8 ... 18).map { .init(start: midnight.addingTimeInterval(Double($0 * 3600)), rainProbability: $0 < 13 ? 0.9 : 0.1, temperatureC: 28) })
        let rain = try await ContextItineraryPlanner.plan(input(parkRequest, weather: weather), provider: FixedTravel(), now: now)
        return .init(evidenceMode: "SYNTHETIC; no live API or human relevance validation", simulatedHTTPCalls: transport.calls, quietReader: quiet, afternoonPhotographer: photographer, rainAvoider: rain)
    }
}
