import Foundation

private enum CheckFailure: Error { case failed(String) }
private func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure.failed(message) }
}
private func reject(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw CheckFailure.failed("Expected rejection")
}

private final class WeatherResponseStub: URLProtocol {
    static var status = 200
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(
                url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!,
            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main @MainActor struct NativeTripWeatherChecks {
    static func main() async throws {
        let start = ISO8601DateFormatter().date(from: "2026-11-03T00:30:00Z")!
        let end = start.addingTimeInterval(3 * 3600)
        let base = start.addingTimeInterval(-1800)
        let usable = NativeTripForecast(
            pointID: "p", hours: [.init(date: base, rainChance: 0.5, temperatureC: 20)],
            status: "available", note: "fixture")
        var backups = 0
        var failures: [NativeTripWeatherProvider] = []
        let primary = try await NativeTripWeatherFallback.resolve(
            pointID: "p", primary: { usable },
            backup: {
                backups += 1
                return usable
            },
            onFailure: {
                failures.append($0)
                _ = $1
            })
        try expect(
            primary.provider == .weatherKit && backups == 0 && failures.isEmpty,
            "Primary success must not call backup")
        print("PASS primary success preserves WeatherKit and avoids fallback")

        let fallback = try await NativeTripWeatherFallback.resolve(
            pointID: "p", primary: { throw NativeTripWeatherFailure.unavailable("attribution failed") },
            backup: {
                backups += 1
                return usable
            },
            onFailure: {
                failures.append($0)
                _ = $1
            })
        try expect(
            backups == 1 && failures == [.weatherKit] && fallback.provider == .openMeteo
                && fallback.note.contains("attribution failed"), "Failure must use and identify backup")
        let empty = try await NativeTripWeatherFallback.resolve(
            pointID: "p", primary: { .init(pointID: "p", hours: [], status: "unavailable", note: "") },
            backup: { usable }, onFailure: { _, _ in })
        try expect(empty.provider == .openMeteo && !empty.hours.isEmpty, "Empty primary must fall back")
        print("PASS attribution/request failure and empty forecasts use labeled fallback")

        let missing = try await NativeTripWeatherFallback.resolve(
            pointID: "p", primary: { throw URLError(.timedOut) },
            backup: { throw NativeTripWeatherFailure.http(429) }, onFailure: { _, _ in })
        try expect(
            missing.hours.isEmpty && missing.provider == nil && missing.status == "unavailable"
                && missing.note.contains("429"), "Both failures must remain unknown")
        let horizon = try await NativeTripWeatherFallback.resolve(
            pointID: "p", primary: { throw NativeTripWeatherFailure.outsideHorizon("10 days") },
            backup: { throw NativeTripWeatherFailure.outsideHorizon("16 days") }, onFailure: { _, _ in })
        try expect(
            horizon.status == "outside_forecast_horizon" && horizon.hours.isEmpty,
            "No fabricated far-future weather")
        print("PASS both providers failing and outside horizons preserve missing data")

        let previousBackups = backups
        for cancellation: Error in [CancellationError(), URLError(.cancelled)] {
            do {
                _ = try await NativeTripWeatherFallback.resolve(
                    pointID: "p", primary: { throw cancellation },
                    backup: {
                        backups += 1
                        return usable
                    }, onFailure: { _, _ in })
                throw CheckFailure.failed("Cancellation swallowed")
            } catch is CancellationError {}
        }
        do {
            _ = try await NativeTripWeatherFallback.resolve(
                pointID: "p", primary: { throw URLError(.timedOut) }, backup: { throw CancellationError() },
                onFailure: { _, _ in })
            throw CheckFailure.failed("Backup cancellation swallowed")
        } catch is CancellationError {}
        try expect(backups == previousBackups, "Cancellation must not call backup")
        print("PASS primary/backup cancellation propagates without triggering new requests")

        let request = try NativeTripOpenMeteoClient.request(
            latitude: 35.32, longitude: 139.5, start: start, end: end, now: start)
        let parameters = Dictionary(
            uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                .queryItems!.map { ($0.name, $0.value!) })
        try expect(
            request.url!.host == "api.open-meteo.com" && parameters["timeformat"] == "unixtime"
                && parameters["timezone"] == "GMT" && parameters["start_date"] == "2026-11-03"
                && parameters["end_date"] == "2026-11-03" && parameters["apikey"] == nil,
            "Request must use UTC, no key, bounded dates")
        try reject {
            _ = try NativeTripOpenMeteoClient.request(
                latitude: 91, longitude: 139.5, start: start, end: end, now: start)
        }
        try reject {
            _ = try NativeTripOpenMeteoClient.request(
                latitude: 35.32, longitude: 139.5, start: start.addingTimeInterval(16 * 86400),
                end: end.addingTimeInterval(16 * 86400), now: start)
        }
        try reject {
            _ = try NativeTripOpenMeteoClient.request(
                latitude: 35.32, longitude: 139.5, start: start.addingTimeInterval(-2 * 86400),
                end: end.addingTimeInterval(-2 * 86400), now: start)
        }
        let day15 = try NativeTripOpenMeteoClient.request(
            latitude: 35.32, longitude: 139.5, start: start.addingTimeInterval(15 * 86400),
            end: end.addingTimeInterval(15 * 86400), now: start)
        try expect(day15.url != nil, "Day 16 of forecast may be requested")
        print("PASS request dates, coordinates and 16-day horizon boundaries")

        let null = NSNull()
        let object: [String: Any] = [
            "hourly_units": [
                "time": "unixtime", "precipitation_probability": "%", "temperature_2m": "°C",
            ],
            "hourly": [
                "time": (0 ..< 5).map { base.addingTimeInterval(Double($0) * 3600).timeIntervalSince1970 },
                "precipitation_probability": [0, 50, null, 100, 110],
                "temperature_2m": [20, null, 22, 23, 24],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try NativeTripOpenMeteoClient.decode(
            data, pointID: "p", start: start, end: end, retrievedAt: end)
        try expect(
            decoded.hours.count == 2 && decoded.hours[0].date == base
                && decoded.hours[0].rainChance == 0.5
                && decoded.hours[1].date == base.addingTimeInterval(7200)
                && decoded.hours[1].rainChance == 1,
            "Preceding-hour probabilities, nulls and out-of-range values")
        try expect(
            decoded.hours[0].temperatureC == 20 && decoded.provider == .openMeteo
                && decoded.fetchedAt == nil && decoded.retrievedAt == end,
            "Provider and actual retrieval timestamp must be distinct from issue time")
        print("PASS interval alignment, percent conversion, nulls and source provenance")

        var wrong = object
        wrong["hourly_units"] = [
            "time": "iso8601", "precipitation_probability": "%", "temperature_2m": "°C",
        ]
        try reject {
            _ = try NativeTripOpenMeteoClient.decode(
                JSONSerialization.data(withJSONObject: wrong), pointID: "p", start: start, end: end,
                retrievedAt: end)
        }
        wrong = object
        wrong["hourly"] = [
            "time": [base.timeIntervalSince1970, base.timeIntervalSince1970],
            "precipitation_probability": [20, 30], "temperature_2m": [20, 20],
        ]
        try reject {
            _ = try NativeTripOpenMeteoClient.decode(
                JSONSerialization.data(withJSONObject: wrong), pointID: "p", start: start, end: end,
                retrievedAt: end)
        }
        try reject {
            _ = try NativeTripOpenMeteoClient.decode(
                Data("{}".utf8), pointID: "p", start: start, end: end, retrievedAt: end)
        }
        print("PASS malformed data, units and overlapping intervals are rejected")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeatherResponseStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = NativeTripOpenMeteoClient(session: session)
        WeatherResponseStub.status = 200
        WeatherResponseStub.body = data
        let http = try await client.forecast(
            pointID: "p", latitude: 35.32, longitude: 139.5, start: start, end: end, now: start)
        try expect(http.hours.count == 2 && http.provider == .openMeteo, "HTTP response must decode")
        WeatherResponseStub.status = 429
        do {
            _ = try await client.forecast(
                pointID: "p", latitude: 35.32, longitude: 139.5, start: start, end: end, now: start)
            throw CheckFailure.failed("HTTP rate limit swallowed")
        } catch NativeTripWeatherFailure.http(429) {}
        print("PASS HTTP client success and rate limit via local URLProtocol; no live requests")
        print("8 weather check groups passed")
    }
}
