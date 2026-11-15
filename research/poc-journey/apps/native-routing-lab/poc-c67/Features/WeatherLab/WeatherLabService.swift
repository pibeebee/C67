import CoreLocation
import Foundation
import WeatherKit

@MainActor final class WeatherLabLiveProvider: WeatherLabProvider {
    private let apple = WeatherService.shared
    private let backup = NativeTripOpenMeteoClient()
    private var credit: NativeTripWeatherCredit?

    func fetch(_ provider: NativeTripWeatherProvider, point: WeatherLabPoint,
               window: WeatherLabWindow) async throws -> WeatherLabPayload {
        try Task.checkCancellation()
        if provider == .openMeteo {
            let forecast = try await backup.forecast(pointID: point.id, latitude: point.latitude,
                                                     longitude: point.longitude, start: window.start, end: window.end)
            try Task.checkCancellation()
            return .init(forecast: forecast, expiresAt: (forecast.retrievedAt ?? .now).addingTimeInterval(900))
        }
        do {
            let hourly = try await apple.weather(
                for: CLLocation(latitude: point.latitude, longitude: point.longitude),
                including: .hourly(startDate: window.start, endDate: window.end))
            try Task.checkCancellation()
            // No Apple data is published or cached until attribution is available.
            let attribution: NativeTripWeatherCredit
            if let credit { attribution = credit }
            else {
                let value = try await apple.attribution
                try Task.checkCancellation()
                attribution = .init(serviceName: value.serviceName, legalPageURL: value.legalPageURL,
                                    combinedMarkLightURL: value.combinedMarkLightURL, combinedMarkDarkURL: value.combinedMarkDarkURL)
                credit = attribution
            }
            return .init(forecast: .init(pointID: point.id, hours: hourly.forecast.filter {
                             $0.date >= window.start && $0.date < window.end
                         }.map {
                             .init(date: $0.date, rainChance: $0.precipitationChance,
                                   temperatureC: $0.temperature.converted(to: .celsius).value)
                         }, status: "ok", note: "Prakiraan per jam untuk titik perwakilan; bukan pengukuran di setiap tempat.",
                         fetchedAt: hourly.metadata.date, provider: .weatherKit, retrievedAt: .now),
                         expiresAt: hourly.metadata.expirationDate, credit: attribution)
        } catch WeatherError.permissionDenied {
            throw WeatherLabError.authentication("WeatherError.permissionDenied")
        }
    }
}

#if DEBUG
    /// Opt-in deterministic UI fixture; the screen and export explicitly label this simulation.
    @MainActor final class WeatherLabDemoProvider: WeatherLabProvider {
        func fetch(_ provider: NativeTripWeatherProvider, point: WeatherLabPoint,
                   window: WeatherLabWindow) async throws -> WeatherLabPayload {
            try await Task.sleep(nanoseconds: 120_000_000)
            if provider == .weatherKit { throw WeatherLabError.authentication("SIMULASI kegagalan autentikasi") }
            var hours: [NativeTripHour] = [], cursor = window.start
            while cursor < window.end {
                hours.append(.init(date: cursor, rainChance: 0.35, temperatureC: 29)); cursor += 3_600
            }
            return .init(forecast: .init(pointID: point.id, hours: hours, status: "simulated",
                                         note: "SIMULASI; bukan prakiraan aktual.", fetchedAt: .now, provider: provider, retrievedAt: .now),
                         expiresAt: Date().addingTimeInterval(900))
        }
    }
#endif
