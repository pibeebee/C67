import XCTest
import CryptoKit
import PlannerContracts
@testable import PlannerEngine

@MainActor private final class StubHTTP: LabHTTPTransport {
    var responses: [LabHTTPResponse]
    var paths: [String] = []
    init(_ responses: [LabHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> LabHTTPResponse {
        try Task.checkCancellation(); paths.append(request.url!.path)
        guard !responses.isEmpty else { throw URLError(.timedOut) }
        return responses.removeFirst()
    }
}
@MainActor final class RESTFaultTests: XCTestCase {
    func testRESTSearchUsesNativePOIPolicyAndJakartaRegion() throws {
        let query = "Perpustakaan Jakarta — Cikini, Jakarta"
        let params = Dictionary(uniqueKeysWithValues: LabRESTSearch.parameters(query: query).map { ($0.name, $0.value!) })
        XCTAssertEqual(params["q"], query)
        XCTAssertEqual(params["resultTypeFilter"], "poi")
        XCTAssertNil(params["searchLocation"], "REST rejects simultaneous location and region hints")
        let region = try XCTUnwrap(params["searchRegion"]).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(region.count, 4)
        XCTAssertGreaterThan(region[0], -6.2); XCTAssertLessThan(region[2], -6.2)
        XCTAssertGreaterThan(region[1], 106.83); XCTAssertLessThan(region[3], 106.83)
    }
    private func config() throws -> LabAppleConfig {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lab-test-key-\(UUID()).p8")
        try P256.Signing.PrivateKey().pemRepresentation.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try .init(environment: ["APPLE_TEAM_ID": "TEAM", "MAPS_KEY_ID": "MAPSKEY", "MAPS_KEY_PATH": url.path,
                                       "WEATHER_KEY_ID": "WEATHERKEY", "WEATHER_KEY_PATH": url.path, "WEATHER_SERVICE_ID": "service"])
    }
    private var token: LabHTTPResponse { .init(status: 200, data: Data(#"{"accessToken":"stub-access-token","expiresInSeconds":1800}"#.utf8)) }
    private var q: LabETAQuery { .init(fromID: "a", toID: "b", fromLatitude: -6.2, fromLongitude: 106.8,
                                       toLatitude: -6.21, toLongitude: 106.81, mode: "automobile", departure: LabMatrix.now) }
    private var success: LabHTTPResponse { .init(status: 200, data: Data(#"{"etas":[{"destination":{"latitude":-6.21,"longitude":106.81},"transportType":"AUTOMOBILE","distanceMeters":1000,"expectedTravelTimeSeconds":100}]}"#.utf8)) }
    func test401InvalidatesAccessTokenAndNextOperationRefreshes() async throws {
        let http = StubHTTP([token, .init(status: 401, data: Data()), token, success])
        let apple = LabAppleREST(config: try config(), transport: http)
        let eta = LabRESTETA(apple: apple)
        do { _ = try await eta.values([q]); XCTFail("401 must stop") }
        catch { if case LabRESTError.status(401, _) = error {} else { XCTFail("Wrong error") } }
        XCTAssertEqual(http.paths.count, 2)
        let values = try await eta.values([q]); XCTAssertEqual(values[0].seconds, 100)
        XCTAssertEqual(http.paths.filter { $0 == "/v1/token" }.count, 2)
    }
    func test429PreservesRetryAfterAndDoesNotLoop() async throws {
        let http = StubHTTP([token, .init(status: 429, headers: ["retry-after": "60"], data: Data())])
        let eta = LabRESTETA(apple: LabAppleREST(config: try config(), transport: http))
        do { _ = try await eta.values([q]); XCTFail("429 must stop") }
        catch { if case LabRESTError.status(429, let retry) = error { XCTAssertEqual(retry, "60") } else { XCTFail("Wrong error") } }
        XCTAssertEqual(http.paths.count, 2)
    }
    func test5xxBecomesUnknownWithOneAttempt() async throws {
        let http = StubHTTP([token, .init(status: 503, data: Data())])
        let eta = LabRESTETA(apple: LabAppleREST(config: try config(), transport: http))
        let value = try await eta.values([q])[0]
        XCTAssertNil(value.seconds); XCTAssertEqual(eta.metrics.failures, 1); XCTAssertEqual(http.paths.count, 2)
    }
    func testTransportTimeoutCannotProduceZeroTravel() async throws {
        let http = StubHTTP([token])
        let eta = LabRESTETA(apple: LabAppleREST(config: try config(), transport: http))
        let values = try await eta.values([q]); XCTAssertNil(values[0].seconds)
    }
    func testTokenExpiryRefreshesWithoutReusingExpiredToken() async throws {
        let short = LabHTTPResponse(status: 200, data: Data(#"{"accessToken":"short","expiresInSeconds":31}"#.utf8))
        let http = StubHTTP([short, success, token, success])
        let eta = LabRESTETA(apple: LabAppleREST(config: try config(), transport: http))
        _ = try await eta.values([q])
        try await Task.sleep(for: .milliseconds(1100))
        _ = try await eta.values([q]); XCTAssertEqual(http.paths.filter { $0 == "/v1/token" }.count, 2)
    }
    func testWeatherAttributionAndHoursSurviveMapping() async throws {
        let weather = #"{"forecastHourly":{"metadata":{"readTime":"2026-11-06T00:00:00Z","expireTime":"2026-11-06T00:15:00Z"},"hours":[{"forecastStart":"2026-11-07T00:00:00Z","precipitationChance":0.3,"temperature":29}]}}"#
        let attribution = #"{"serviceName":"Apple Weather","logoLight@2x":"/assets/light.png","logoDark@2x":"/assets/dark.png"}"#
        let http = StubHTTP([.init(status: 200, data: Data(weather.utf8)), .init(status: 200, data: Data(attribution.utf8))])
        let provider = LabRESTWeather(apple: LabAppleREST(config: try config(), transport: http))
        let pin = PlacePin(id: "a", name: "a", address: "Jakarta", latitude: -6.2, longitude: 106.8)
        let start = TripClock.date("2026-11-07T00:00:00Z")
        let result = try await provider.fetch(pin: pin, memberIDs: ["a"], start: start, end: start.addingTimeInterval(3600), allowFallback: false, now: LabMatrix.now)
        XCTAssertEqual(result.hours[0].rainChance, 0.3)
        XCTAssertEqual(result.credit?.markLightURL?.absoluteString, "https://weatherkit.apple.com/assets/light.png")
        // Past expiry remains past; mapping must not manufacture a fresh forecast.
        XCTAssertLessThan(result.expiresAt, result.retrievedAt)
    }
}
