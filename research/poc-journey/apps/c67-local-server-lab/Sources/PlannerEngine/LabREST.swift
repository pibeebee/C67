import CryptoKit
import Foundation
import MapKit

public struct LabHTTPResponse: Sendable {
    public var status: Int; public var headers: [String: String]; public var data: Data
    public init(status: Int, headers: [String: String] = [:], data: Data) {
        self.status = status; self.headers = headers; self.data = data
    }
}
@MainActor public protocol LabHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> LabHTTPResponse
}
@MainActor public final class LabURLSession: LabHTTPTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 30
        config.urlCache = nil; config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }
    public func send(_ request: URLRequest) async throws -> LabHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard data.count <= 5 * 1024 * 1024, let http = response as? HTTPURLResponse else {
            throw IntegrationError.invalid("Invalid/oversized provider response")
        }
        return .init(status: http.statusCode,
                     headers: http.allHeaderFields.reduce(into: [:]) { $0[String(describing: $1.key).lowercased()] = String(describing: $1.value) }, data: data)
    }
}
public enum LabRESTError: Error, LocalizedError, Sendable {
    case status(Int, retryAfter: String?), configuration, response
    public var errorDescription: String? {
        switch self {
        case .status(let code, let retry): "Provider HTTP \(code); retry-after=\(retry ?? "absent")"
        case .configuration: "REST configuration missing/invalid"
        case .response: "REST response invalid/incomplete"
        }
    }
}
public struct LabAppleConfig: Sendable {
    public var teamID: String; public var mapsKeyID: String; public var mapsKeyPath: String
    public var weatherKeyID: String; public var weatherKeyPath: String; public var weatherServiceID: String
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let names = ["APPLE_TEAM_ID", "MAPS_KEY_ID", "MAPS_KEY_PATH", "WEATHER_KEY_ID", "WEATHER_KEY_PATH", "WEATHER_SERVICE_ID"]
        guard names.allSatisfy({ !(environment[$0] ?? "").isEmpty }) else { throw LabRESTError.configuration }
        teamID = environment[names[0]]!; mapsKeyID = environment[names[1]]!; mapsKeyPath = environment[names[2]]!
        weatherKeyID = environment[names[3]]!; weatherKeyPath = environment[names[4]]!; weatherServiceID = environment[names[5]]!
    }
}
public enum LabJWT {
    public static func sign(team: String, keyID: String, pem: String, service: String? = nil, now: Date = .now) throws -> String {
        var header = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
        var claims: [String: Any] = ["iss": team, "iat": Int(now.timeIntervalSince1970), "exp": Int(now.timeIntervalSince1970) + 1800]
        if let service {
            header["id"] = team + "." + service; claims["sub"] = service
        } else {
            claims["scope"] = "server_api"
        }
        func encode(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        let input = try encode(JSONSerialization.data(withJSONObject: header, options: .sortedKeys)) + "." + encode(JSONSerialization.data(withJSONObject: claims, options: .sortedKeys))
        let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
        return try input + "." + encode(key.signature(for: Data(input.utf8)).rawRepresentation)
    }
}
/// Shared campaign guard. Token calls and failed attempts count. It never raises its own limits.
@MainActor public final class LabProviderBudget {
    public private(set) var calls = 0; public private(set) var cells = 0
    public let callLimit: Int; public let cellLimit: Int
    public init(callLimit: Int = 3000, cellLimit: Int = 6000) { self.callLimit = callLimit; self.cellLimit = cellLimit }
    public func consume(cells: Int = 0) throws {
        guard calls < callLimit, self.cells + cells <= cellLimit else { throw IntegrationError.invalid("budget_exhausted") }
        calls += 1; self.cells += cells
    }
}
@MainActor public final class LabAppleREST {
    let config: LabAppleConfig
    let http: any LabHTTPTransport
    public let budget: LabProviderBudget
    private var token: String?; private var expires = Date.distantPast
    private var nextETA = Date.distantPast
    private var retryNotBefore = Date.distantPast
    public init(config: LabAppleConfig, transport: any LabHTTPTransport = LabURLSession(), budget: LabProviderBudget = .init()) {
        self.config = config; http = transport; self.budget = budget
    }
    private func developerToken(weather: Bool) throws -> String {
        try LabJWT.sign(team: config.teamID, keyID: weather ? config.weatherKeyID : config.mapsKeyID,
                        pem: String(contentsOfFile: weather ? config.weatherKeyPath : config.mapsKeyPath, encoding: .utf8),
                        service: weather ? config.weatherServiceID : nil)
    }
    private func call(_ url: URL, bearer: String, cells: Int = 0) async throws -> LabHTTPResponse {
        let retryDelay = retryNotBefore.timeIntervalSinceNow
        if retryDelay > 0 { try await Task.sleep(for: .seconds(retryDelay)) }
        try Task.checkCancellation()
        try budget.consume(cells: cells)
        var request = URLRequest(url: url); request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25
        let result = try await http.send(request)
        guard result.status == 200 else {
            if let text = result.headers["retry-after"] {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                retryNotBefore = max(retryNotBefore, Double(text).map { Date().addingTimeInterval(max(0, $0)) } ?? formatter.date(from: text) ?? .distantPast)
            }
            throw LabRESTError.status(result.status, retryAfter: result.headers["retry-after"])
        }
        return result
    }
    public func maps(path: String, params: [URLQueryItem], cells: Int = 0) async throws -> Data {
        if token == nil || expires <= Date().addingTimeInterval(30) {
            let response = try await call(URL(string: "https://maps-api.apple.com/v1/token")!, bearer: developerToken(weather: false))
            struct Token: Decodable { var accessToken: String; var expiresInSeconds: Double }
            let value = try JSONDecoder().decode(Token.self, from: response.data)
            guard !value.accessToken.isEmpty, value.expiresInSeconds > 30 else { throw LabRESTError.response }
            token = value.accessToken; expires = Date().addingTimeInterval(value.expiresInSeconds)
        }
        var url = URLComponents(string: "https://maps-api.apple.com/v1/" + path)!
        url.queryItems = params
        if path == "etas" {
            let reserved = max(Date(), nextETA); nextETA = reserved.addingTimeInterval(1.2)
            let delay = reserved.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        }
        do { return try await call(url.url!, bearer: token!, cells: cells).data }
        catch {
            if case LabRESTError.status(401, _) = error { token = nil; expires = .distantPast }
            // No immediate retry on 401/429/5xx. A future operation may refresh; Retry-After is reported.
            throw error
        }
    }
    public func weather(path: String, params: [URLQueryItem] = []) async throws -> Data {
        var url = URLComponents(string: "https://weatherkit.apple.com/" + path)!
        url.queryItems = params.isEmpty ? nil : params
        return try await call(url.url!, bearer: developerToken(weather: true)).data
    }
}
@MainActor public final class LabRESTETA: LabETAProvider {
    let apple: LabAppleREST
    public private(set) var metrics = LabProviderMetrics()
    public init(apple: LabAppleREST) { self.apple = apple }
    public func values(_ queries: [LabETAQuery]) async throws -> [LabETAValue] {
        guard let first = queries.first, queries.count <= 10, Set(queries.map(\.groupKey)).count == 1,
              ["walking", "automobile"].contains(first.mode) else { throw LabRESTError.response }
        metrics.calls += 1; metrics.cells += queries.count; metrics.requests.append(queries)
        do {
            let data = try await apple.maps(path: "etas", params: [
                .init(name: "origin", value: "\(first.fromLatitude),\(first.fromLongitude)"),
                .init(name: "destinations", value: queries.map { "\($0.toLatitude),\($0.toLongitude)" }.joined(separator: "|")),
                .init(name: "transportType", value: first.mode == "walking" ? "Walking" : "Automobile"),
                .init(name: "departureDate", value: first.departure.ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ], cells: queries.count)
            let output = try Self.parse(data, queries: queries)
            metrics.failures += output.filter { $0.seconds == nil }.count
            return output
        } catch {
            try Task.checkCancellation()
            // Fatal auth/quota/budget errors stop the operation, rather than repeating every cell.
            if case LabRESTError.status(let code, _) = error, [401, 429].contains(code) { throw error }
            if error.localizedDescription.contains("budget_exhausted") { throw error }
            metrics.failures += queries.count
            return queries.map { .init(query: $0, status: "unavailable", note: error.localizedDescription) }
        }
    }
    public static func parse(_ data: Data, queries: [LabETAQuery]) throws -> [LabETAValue] {
        struct Location: Decodable { var latitude: Double; var longitude: Double }
        struct Item: Decodable {
            var destination: Location
            var transportType: String
            var distanceMeters: Double?
            var expectedTravelTimeSeconds: Double?
        }
        struct Response: Decodable { var etas: [Item] }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return queries.map { q in
            let items = response.etas.filter { abs($0.destination.latitude - q.toLatitude) < 0.000001 && abs($0.destination.longitude - q.toLongitude) < 0.000001 }
            guard items.count == 1, let item = items.first,
                  item.transportType.lowercased() == q.mode else {
                return .init(query: q, status: "unavailable", note: "Missing/duplicate/invalid REST destination or mode")
            }
            guard let seconds = item.expectedTravelTimeSeconds, let distance = item.distanceMeters else {
                let missingFields = [
                    item.expectedTravelTimeSeconds == nil ? "expectedTravelTimeSeconds" : nil,
                    item.distanceMeters == nil ? "distanceMeters" : nil
                ].compactMap { $0 }
                return .init(query: q, status: "unavailable",
                             note: "Apple ETA response missing fields: " + missingFields.joined(separator: ", "))
            }
            guard seconds.isFinite, seconds >= 0, distance.isFinite, distance >= 0 else {
                return .init(query: q, status: "unavailable", note: "Invalid REST travel time or distance")
            }
            return .init(query: q, seconds: seconds, distance: distance,
                         note: "Apple Maps Server API; exact requested departure; no motor/parking claim")
        }
    }
}
@MainActor public final class LabRESTSearch: TripPlaceSearching {
    let apple: LabAppleREST
    public init(apple: LabAppleREST) { self.apple = apple }
    public func cancel() {}
    public static func parameters(query: String) -> [URLQueryItem] {
        // Match MapKitTripSearch's POI-only policy and its 45 km Jakarta region hint.
        let region = MKCoordinateRegion(center: .init(latitude: -6.2, longitude: 106.83),
                                        latitudinalMeters: 45000, longitudinalMeters: 45000)
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        let west = region.center.longitude - region.span.longitudeDelta / 2
        return [.init(name: "q", value: query),
                .init(name: "searchRegion", value: "\(north),\(east),\(south),\(west)"),
                .init(name: "resultTypeFilter", value: "poi"), .init(name: "lang", value: "en-US")]
    }
    public func search(query: String) async throws -> [PlacePin] {
        let data = try await apple.maps(path: "search", params: Self.parameters(query: query))
        struct Coordinate: Decodable { var latitude: Double; var longitude: Double }
        struct Item: Decodable { var name: String; var coordinate: Coordinate; var formattedAddressLines: [String]? }
        struct Response: Decodable { var results: [Item] }
        return try JSONDecoder().decode(Response.self, from: data).results.prefix(10).map {
            var pin = PlacePin(id: "\($0.name):\($0.coordinate.latitude):\($0.coordinate.longitude)", name: $0.name,
                               address: ($0.formattedAddressLines ?? []).joined(separator: ", "), latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            pin.source = "Apple Maps Server API"; return pin
        }
    }
}
@MainActor public final class LabRESTWeather: TripWeatherFetching {
    let apple: LabAppleREST
    public init(apple: LabAppleREST) { self.apple = apple }
    public func fetch(pin: PlacePin, memberIDs: [String], start: Date, end: Date,
                      allowFallback: Bool, now: Date) async throws -> WeatherEvidence {
        let data = try await apple.weather(path: "api/v1/weather/en-US/\(pin.latitude)/\(pin.longitude)", params: [
            .init(name: "dataSets", value: "forecastHourly,forecastDaily"),
            .init(name: "hourlyStart", value: start.ISO8601Format()), .init(name: "hourlyEnd", value: end.ISO8601Format()),
            .init(name: "timezone", value: "Asia/Jakarta")])
        struct Metadata: Decodable { var readTime: Date; var expireTime: Date }
        struct Hour: Decodable { var forecastStart: Date; var precipitationChance: Double; var temperature: Double?; var cloudCover: Double? }
        struct Hourly: Decodable { var metadata: Metadata; var hours: [Hour] }
        struct Day: Decodable { var forecastStart: Date; var sunrise: Date?; var sunset: Date? }
        struct Daily: Decodable { var days: [Day] }
        struct Weather: Decodable { var forecastHourly: Hourly; var forecastDaily: Daily? }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Weather.self, from: data)
        let attribution = try await apple.weather(path: "attribution/en-US")
        guard let credit = try JSONSerialization.jsonObject(with: attribution) as? [String: String],
              let name = credit["serviceName"], let light = credit["logoLight@2x"], let dark = credit["logoDark@2x"] else {
            throw LabRESTError.response
        }
        let fetched = Date()
        let day = value.forecastDaily?.days.first { TripClock.day($0.forecastStart) == TripClock.day(start) }
        return .init(id: UUID().uuidString, representative: pin, memberIDs: memberIDs,
                     provider: "weatherkit", status: "available", fetchedAt: value.forecastHourly.metadata.readTime,
                     retrievedAt: fetched, expiresAt: min(value.forecastHourly.metadata.expireTime, fetched.addingTimeInterval(900)),
                     windowStart: start, windowEnd: end,
                     hours: WeatherPolicy.sanitized(value.forecastHourly.hours.map { .init(start: $0.forecastStart, rainChance: $0.precipitationChance, temperatureC: $0.temperature, cloudCover: $0.cloudCover) }),
                     sunrise: day?.sunrise, sunset: day?.sunset,
                     credit: .init(name: name, legalURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
                                   markLightURL: URL(string: light, relativeTo: URL(string: "https://weatherkit.apple.com"))?.absoluteURL,
                                   markDarkURL: URL(string: dark, relativeTo: URL(string: "https://weatherkit.apple.com"))?.absoluteURL), errors: [])
    }
}
