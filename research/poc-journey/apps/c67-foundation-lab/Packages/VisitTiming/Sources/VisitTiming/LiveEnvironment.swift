import Foundation
import MapKit

/// Fresh MapKit identity/coordinate + Open-Meteo forecast. No physical location permission.
/// WeatherKit's separate app provisioning is not changed by this experiment.
@MainActor public final class LiveTimingEnvironment {
    private var activeSearch: MKLocalSearch?
    public init() {}
    public func fetch(venue: VenueFacts, date: String) async throws -> TimingEnvironment {
        _ = try VenueClock.day(date, timeZone: venue.timeZone)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = venue.query
        request.region = .init(
            center: .init(latitude: -6.20, longitude: 106.82),
            span: .init(latitudeDelta: 0.45, longitudeDelta: 0.45))
        request.resultTypes = .pointOfInterest
        let search = MKLocalSearch(request: request)
        activeSearch = search
        let deadline = Task { @MainActor in
            try await Task.sleep(for: .seconds(20))
            search.cancel()
        }
        defer {
            deadline.cancel()
            activeSearch = nil
        }
        let response = try await withTaskCancellationHandler {
            try await search.start()
        } onCancel: {
            Task { @MainActor in self.activeSearch?.cancel() }
        }
        try Task.checkCancellation()
        let expected: [String]
        switch venue.id {
        case "gbk": expected = ["hutan", "kota"]
        case "ragunan": expected = ["ragunan"]
        default:
            throw TimingError.invalid(
                "Prakiraan live dibatasi ke dua venue luar ruang yang telah diperiksa.")
        }
        let matching = response.mapItems.filter { item in
            let name = (item.name ?? "").lowercased()
            let coordinate = item.placemark.coordinate
            return expected.allSatisfy { name.contains($0) }
                && (-6.45 ... -6.05).contains(coordinate.latitude)
                && (106.65 ... 107.0).contains(coordinate.longitude)
        }
        guard matching.count == 1, let item = matching.first else {
            throw TimingError.invalid(
                "Identitas MapKit ambigu/tidak ditemukan (\(matching.count) kecocokan); prakiraan tidak diambil."
            )
        }
        let coordinate = item.placemark.coordinate
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(coordinate.latitude)),
            .init(name: "longitude", value: String(coordinate.longitude)),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability"),
            .init(name: "daily", value: "sunrise,sunset"),
            .init(name: "start_date", value: date), .init(name: "end_date", value: date),
            .init(name: "timezone", value: venue.timeZone),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "temperature_unit", value: "celsius"),
        ]
        var network = URLRequest(url: components.url!)
        network.timeoutInterval = 20
        let (data, responseHTTP) = try await URLSession.shared.data(for: network)
        try Task.checkCancellation()
        guard let http = responseHTTP as? HTTPURLResponse, http.statusCode == 200 else {
            throw TimingError.invalid("Provider prakiraan menolak request; periksa tanggal dan jaringan.")
        }
        let result = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        guard result.hourly.time.count == result.hourly.rainProbability.count,
              result.hourly.time.count == result.hourly.temperatureC.count,
              !result.hourly.time.isEmpty, result.timezone == venue.timeZone,
              result.hourlyUnits.rainProbability == "%",
              result.hourlyUnits.temperatureC == "°C"
        else { throw TimingError.invalid("Kontrak/units prakiraan tidak sesuai.") }
        let fetched = Date()
        return .init(
            provider: "Open-Meteo live", fetchedAt: fetched,
            validUntil: fetched.addingTimeInterval(900), date: date, venueID: venue.id,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            locationName: item.name ?? venue.name,
            locationSource:
            "MapKit MKLocalSearch; \(venue.query); \(item.identifier?.rawValue ?? "ID unavailable"); unique name match, not on-site verification",
            hours: result.hourly.time.indices.map { i in
                .init(
                    start: Date(timeIntervalSince1970: result.hourly.time[i]),
                    rainChance: result.hourly.rainProbability[i].map { $0 / 100 },
                    temperatureC: result.hourly.temperatureC[i])
            },
            sunrise: result.daily.sunrise.first.flatMap { $0 }.map { Date(timeIntervalSince1970: $0) },
            sunset: result.daily.sunset.first.flatMap { $0 }.map { Date(timeIntervalSince1970: $0) },
            attributionURL: components.url!,
            attribution: "Weather data by Open-Meteo (CC BY 4.0); https://open-meteo.com/",
            errors: [])
    }
}

private struct OpenMeteoResponse: Decodable {
    var timezone: String
    var hourly: Hourly
    var hourlyUnits: Units
    var daily: Daily
    enum CodingKeys: String, CodingKey {
        case timezone, hourly, daily
        case hourlyUnits = "hourly_units"
    }
    struct Hourly: Decodable {
        var time: [Double]
        var rainProbability: [Double?]
        var temperatureC: [Double?]
        enum CodingKeys: String, CodingKey {
            case time
            case rainProbability = "precipitation_probability"
            case temperatureC = "temperature_2m"
        }
    }
    struct Units: Decodable {
        var rainProbability: String
        var temperatureC: String
        enum CodingKeys: String, CodingKey {
            case rainProbability = "precipitation_probability"
            case temperatureC = "temperature_2m"
        }
    }
    struct Daily: Decodable {
        var sunrise: [Double?]
        var sunset: [Double?]
    }
}
