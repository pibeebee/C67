import C67Domain
import C67PlannerV5
import Foundation

enum PocketOpenMeteoScheduleForecast {
    static let source = "Open-Meteo"

    static func load(_ point: PlanningPoint) async throws -> PocketScheduleForecast {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(point.latitude)),
            .init(name: "longitude", value: String(point.longitude)),
            .init(name: "hourly", value: "apparent_temperature,uv_index,direct_radiation,precipitation_probability"),
            .init(name: "forecast_days", value: "16"),
            .init(name: "temperature_unit", value: "celsius"),
            .init(name: "timezone", value: "GMT"),
            .init(name: "timeformat", value: "unixtime")
        ]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> PocketScheduleForecast {
        struct Response: Decodable {
            struct Hours: Decodable {
                let time: [Double]
                let apparent_temperature: [Double?]?
                let uv_index: [Double?]?
                let direct_radiation: [Double?]?
                let precipitation_probability: [Double?]?
            }
            let hourly: Hours
            let hourly_units: [String: String]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let hours = response.hourly
        guard response.hourly_units["time"] == "unixtime",
              hours.time.allSatisfy({ $0.isFinite && abs($0) < 1e12 }),
              zip(hours.time, hours.time.dropFirst()).allSatisfy({ $1 - $0 >= 3600 }) else {
            throw URLError(.cannotParseResponse)
        }
        func samples(_ values: [Double?]?, key: String, unit: String, preceding: Bool,
                     valid: (Double) -> Bool) -> [PlannerV51WeatherSeries.Sample] {
            guard let values, values.count == hours.time.count, response.hourly_units[key] == unit else { return [] }
            return zip(hours.time, values).compactMap { time, value in
                guard let value, value.isFinite, valid(value) else { return nil }
                let start = Date(timeIntervalSince1970: preceding ? time - 3600 : time)
                return .init(interval: .init(start: start, duration: 3600), value: value)
            }
        }
        let temperature = samples(hours.apparent_temperature, key: "apparent_temperature", unit: "°C", preceding: false) { _ in true }
        let uv = samples(hours.uv_index, key: "uv_index", unit: "", preceding: true) { $0 >= 0 }
        let radiation = samples(hours.direct_radiation, key: "direct_radiation", unit: "W/m²", preceding: true) { $0 >= 0 }
        let rain = samples(hours.precipitation_probability, key: "precipitation_probability", unit: "%", preceding: true) {
            (0 ... 100).contains($0)
        }.map { PlannerV5RainSample(interval: $0.interval, probability: $0.value / 100, source: source) }
        let series = zip(PlannerV51WeatherKind.allCases, [temperature, radiation, uv]).compactMap { kind, values in
            values.isEmpty ? nil : PlannerV51WeatherSeries(kind: kind, source: source, samples: values)
        }
        let evidence = PlanningEvidence(id: "open-meteo-schedule", label: source,
                                        url: URL(string: "https://open-meteo.com/")!, checkedAt: .now,
                                        kind: "weather", summary: "Hourly forecast (CC BY 4.0)", synthetic: false)
        return .init(series: series, rain: rain, evidence: [evidence])
    }
}
