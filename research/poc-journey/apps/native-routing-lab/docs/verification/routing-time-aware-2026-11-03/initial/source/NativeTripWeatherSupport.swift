import Foundation

enum NativeTripWeatherProvider: String, Sendable {
    case weatherKit = "weatherkit"
    case openMeteo = "open_meteo"

    var title: String { self == .weatherKit ? "Apple Weather" : "Open-Meteo" }
    static let openMeteoCredit =
        "Data cuaca: Open-Meteo (https://open-meteo.com/), CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Peluang presipitasi dikonversi ke 0–1 dan interval satu jam sebelumnya untuk perhitungan paparan."
}

struct NativeTripHour: Sendable {
    /// Start of the interval to which precipitation probability applies.
    var date: Date
    var rainChance: Double
    var temperatureC: Double?
}

struct NativeTripForecast: Sendable {
    var pointID: String
    var hours: [NativeTripHour]
    var status: String
    var note: String
    /// Provider metadata timestamp, when supplied; not the download time.
    var fetchedAt: Date?
    var provider: NativeTripWeatherProvider? = nil
    var retrievedAt: Date? = nil
}

enum NativeTripWeatherFailure: LocalizedError {
    case unavailable(String)
    case outsideHorizon(String)
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason), .outsideHorizon(let reason): return reason
        case .invalidResponse:
            return
                "Respons Open-Meteo tidak valid atau tidak berisi peluang presipitasi yang dapat digunakan."
        case .http(let status): return "Open-Meteo mengembalikan HTTP \(status)."
        }
    }
}

/// Shared fallback policy, independent of Apple frameworks so failures can be checked offline.
@MainActor enum NativeTripWeatherFallback {
    static func resolve(
        pointID: String,
        primary: () async throws -> NativeTripForecast,
        backup: () async throws -> NativeTripForecast,
        onFailure: (NativeTripWeatherProvider, Error) -> Void
    ) async throws -> NativeTripForecast {
        try Task.checkCancellation()
        let primaryReason: String
        do {
            var result = try await primary()
            try Task.checkCancellation()
            guard !result.hours.isEmpty else {
                throw NativeTripWeatherFailure.unavailable(
                    "WeatherKit tidak memberi prakiraan untuk waktu trip.")
            }
            result.provider = .weatherKit
            return result
        } catch {
            try checkCancellation(error)
            onFailure(.weatherKit, error)
            primaryReason = String(error.localizedDescription.prefix(400))
        }
        do {
            var result = try await backup()
            try Task.checkCancellation()
            guard !result.hours.isEmpty else { throw NativeTripWeatherFailure.invalidResponse }
            result.provider = .openMeteo
            result.note = "Cadangan Open-Meteo. WeatherKit: \(primaryReason) \(result.note)"
            return result
        } catch {
            try checkCancellation(error)
            onFailure(.openMeteo, error)
            let outside: Bool
            if case NativeTripWeatherFailure.outsideHorizon = error {
                outside = true
            } else {
                outside = false
            }
            return .init(
                pointID: pointID, hours: [], status: outside ? "outside_forecast_horizon" : "unavailable",
                note:
                "WeatherKit: \(primaryReason) Open-Meteo: \(String(error.localizedDescription.prefix(400)))"
            )
        }
    }

    private static func checkCancellation(_ error: Error) throws {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }
}

struct NativeTripOpenMeteoClient {
    let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 30
            configuration.waitsForConnectivity = false
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func forecast(
        pointID: String, latitude: Double, longitude: Double, start: Date, end: Date, now: Date = .now
    ) async throws -> NativeTripForecast {
        try Task.checkCancellation()
        let request = try Self.request(
            latitude: latitude, longitude: longitude, start: start, end: end, now: now)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw NativeTripWeatherFailure.invalidResponse
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw NativeTripWeatherFailure.http(response.statusCode)
        }
        return try Self.decode(data, pointID: pointID, start: start, end: end, retrievedAt: .now)
    }

    static func request(latitude: Double, longitude: Double, start: Date, end: Date, now: Date) throws
        -> URLRequest
    {
        guard latitude.isFinite, longitude.isFinite, (-90 ... 90).contains(latitude),
              (-180 ... 180).contains(longitude),
              start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, end > start
        else { throw NativeTripWeatherFailure.invalidResponse }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: now)
        let lastDay = calendar.date(byAdding: .day, value: 15, to: today)!
        let limit = calendar.date(byAdding: .day, value: 16, to: today)!
        guard start < limit, end > today else {
            throw NativeTripWeatherFailure.outsideHorizon(
                "Tanggal di luar horizon prakiraan Open-Meteo hingga 16 hari. Tidak memakai data historis sebagai pengganti."
            )
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "hourly", value: "precipitation_probability,temperature_2m"),
            .init(name: "temperature_unit", value: "celsius"),
            .init(name: "timezone", value: "GMT"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "start_date", value: formatter.string(from: max(today, start))),
            // Include the endpoint hour: Open-Meteo probabilities describe the preceding hour.
            .init(name: "end_date", value: formatter.string(from: min(lastDay, end))),
        ]
        var request = URLRequest(
            url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func decode(_ data: Data, pointID: String, start: Date, end: Date, retrievedAt: Date)
        throws -> NativeTripForecast
    {
        guard data.count <= 2_000_000 else { throw NativeTripWeatherFailure.invalidResponse }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let hourly = response.hourly
        guard response.hourlyUnits.time == "unixtime",
              response.hourlyUnits.precipitationProbability == "%",
              response.hourlyUnits.temperature == "°C", !hourly.time.isEmpty,
              hourly.time.count == hourly.precipitationProbability.count,
              hourly.time.count == hourly.temperature.count,
              hourly.time.allSatisfy(\.isFinite),
              zip(hourly.time, hourly.time.dropFirst()).allSatisfy({ $1 - $0 == 3600 })
        else { throw NativeTripWeatherFailure.invalidResponse }
        let hours = hourly.time.indices.compactMap { index -> NativeTripHour? in
            let until = Date(timeIntervalSince1970: hourly.time[index])
            let from = until.addingTimeInterval(-3600)
            guard from < end, until > start, let chance = hourly.precipitationProbability[index],
                  chance.isFinite, (0 ... 100).contains(chance)
            else { return nil }
            // Temperature is instantaneous. Use the previous timestamp for the interval's start.
            let temperature =
                index > 0 ? hourly.temperature[index - 1].flatMap { $0.isFinite ? $0 : nil } : nil
            return .init(date: from, rainChance: chance / 100, temperatureC: temperature)
        }
        guard !hours.isEmpty else { throw NativeTripWeatherFailure.invalidResponse }
        return .init(
            pointID: pointID, hours: hours, status: "available",
            note:
            "Prakiraan area Open-Meteo, bukan jaminan cuaca tepat di tempat. Presipitasi mencakup hujan/salju; interval tanpa nilai tetap unknown. Titik dekat berbagi prakiraan sementara per sekitar 0,01 derajat.",
            provider: .openMeteo, retrievedAt: retrievedAt)
    }

    private struct Response: Decodable {
        var hourly: Hourly
        var hourlyUnits: Units
        enum CodingKeys: String, CodingKey {
            case hourly
            case hourlyUnits = "hourly_units"
        }
        struct Hourly: Decodable {
            var time: [Double]
            var precipitationProbability: [Double?]
            var temperature: [Double?]
            enum CodingKeys: String, CodingKey {
                case time
                case precipitationProbability = "precipitation_probability"
                case temperature = "temperature_2m"
            }
        }
        struct Units: Decodable {
            var time: String
            var precipitationProbability: String
            var temperature: String
            enum CodingKeys: String, CodingKey {
                case time
                case precipitationProbability = "precipitation_probability"
                case temperature = "temperature_2m"
            }
        }
    }
}
