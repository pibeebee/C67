import CoreLocation
import Foundation
import WeatherKit

@MainActor public protocol TripWeatherFetching: Sendable {
    func fetch(pin: PlacePin, memberIDs: [String], start: Date, end: Date,
               allowFallback: Bool, now: Date) async throws -> WeatherEvidence
}

public enum WeatherPolicy {
    public static func sanitized(_ input: [WeatherHour]) -> [WeatherHour] {
        let grouped = Dictionary(grouping: input, by: \.start)
        return grouped.compactMap { _, values in
            guard values.count == 1, let value = values.first,
                  value.start.timeIntervalSince1970.isFinite, value.rainChance.isFinite,
                  (0 ... 1).contains(value.rainChance),
                  value.temperatureC.map({ $0.isFinite && (-100 ... 70).contains($0) }) ?? true
            else { return nil }
            return value
        }.sorted { $0.start < $1.start }
    }
    public static func rain(_ hours: [WeatherHour], start: Date, end: Date) -> Double? {
        guard end > start else { return nil }
        var cursor = start
        var highest = 0.0
        for hour in sanitized(hours) {
            let until = hour.start.addingTimeInterval(3600)
            if hour.start <= cursor && until > cursor {
                cursor = min(end, until); highest = max(highest, hour.rainChance)
                if cursor >= end { return highest }
            }
        }
        return nil
    }
    public static func canReuse(_ value: WeatherEvidence, pin: PlacePin, start: Date, end: Date,
                                allowFallback: Bool, now: Date) -> Bool {
        value.complete && (allowFallback || value.provider == "weatherkit")
            && now >= value.retrievedAt && now.timeIntervalSince(value.retrievedAt) < 900
            && now < value.expiresAt && value.windowStart <= start && value.windowEnd >= end
            && distance(pin, value.representative) <= 3000
    }
    public static func distance(_ a: PlacePin, _ b: PlacePin) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from:
            CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
    public static func groups(_ pins: [(String, PlacePin)]) -> [[(String, PlacePin)]] {
        var result: [[(String, PlacePin)]] = []
        for pair in pins.sorted(by: { $0.0 < $1.0 }) {
            if let index = result.firstIndex(where: { distance($0[0].1, pair.1) <= 3000 }) {
                result[index].append(pair)
            } else { result.append([pair]) }
        }
        return result
    }
}

@MainActor public final class WeatherKitTripProvider: TripWeatherFetching {
    private let apple = WeatherService.shared
    private let backup = NativeTripOpenMeteoClient()
    public init() {}
    public func fetch(pin: PlacePin, memberIDs: [String], start: Date, end: Date,
                      allowFallback: Bool, now: Date) async throws -> WeatherEvidence {
        var result = WeatherEvidence(id: UUID().uuidString, representative: pin, memberIDs: memberIDs,
                                     provider: "weatherkit", status: "unavailable", fetchedAt: now, retrievedAt: now,
                                     expiresAt: now, windowStart: start, windowEnd: end, hours: [], errors: [])
        // No history is synthesized. The native WeatherKit horizon is shorter than Open-Meteo's.
        guard start >= TripClock.calendar.startOfDay(for: now),
              end <= TripClock.calendar.startOfDay(for: now).addingTimeInterval(10 * 86400) else {
            result.status = "outside_forecast_horizon"
            result.errors = ["Tanggal di luar jangkauan WeatherKit 10 hari; tidak mengganti tanggal fixture."]
            return result
        }
        let location = CLLocation(latitude: pin.latitude, longitude: pin.longitude)
        do {
            let hourly = try await apple.weather(for: location,
                                                 including: .hourly(startDate: start, endDate: end))
            try Task.checkCancellation()
            let credit = try await apple.attribution
            try Task.checkCancellation()
            result.hours = WeatherPolicy.sanitized(hourly.forecast.map {
                .init(start: $0.date, rainChance: $0.precipitationChance,
                      temperatureC: $0.temperature.converted(to: .celsius).value)
            })
            guard !result.hours.isEmpty else { throw IntegrationError.invalid("WeatherKit tanpa jam cuaca yang valid.") }
            result.fetchedAt = hourly.metadata.date
            result.retrievedAt = Date()
            result.expiresAt = min(hourly.metadata.expirationDate, result.retrievedAt.addingTimeInterval(900))
            result.credit = .init(name: credit.serviceName, legalURL: credit.legalPageURL,
                                  markLightURL: credit.combinedMarkLightURL, markDarkURL: credit.combinedMarkDarkURL)
            result.status = "available"
            do {
                let daily = try await apple.weather(for: location, including: .daily(startDate: start, endDate: end))
                if let day = daily.forecast.first(where: { TripClock.day($0.date) == TripClock.day(start) }) {
                    result.sunrise = day.sun.sunrise; result.sunset = day.sun.sunset
                }
            } catch {
                try Task.checkCancellation()
                result.errors.append("Data matahari belum tersedia: \(ProviderDiagnostics.message(error))")
            }
            return result
        } catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            result.errors.append("WeatherKit: \(ProviderDiagnostics.message(error))")
            if case WeatherError.permissionDenied = error { result.status = "authentication_failure" }
        }
        guard allowFallback else { return result }
        do {
            let value = try await backup.forecast(pointID: pin.id, latitude: pin.latitude,
                                                  longitude: pin.longitude, start: start, end: end, now: now)
            try Task.checkCancellation()
            guard !value.hours.isEmpty else { throw IntegrationError.invalid(value.note) }
            result.provider = "open_meteo"
            result.hours = WeatherPolicy.sanitized(value.hours.map {
                .init(start: $0.date, rainChance: $0.rainChance, temperatureC: $0.temperatureC)
            })
            result.fetchedAt = value.fetchedAt ?? now
            result.retrievedAt = Date(); result.expiresAt = result.retrievedAt.addingTimeInterval(900)
            result.credit = .init(name: "Open-Meteo · CC BY 4.0", legalURL: URL(string: "https://open-meteo.com/en/terms")!)
            result.status = result.hours.isEmpty ? "unavailable" : "available"
        } catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            result.errors.append("Open-Meteo: \(ProviderDiagnostics.message(error))")
        }
        return result
    }
}

@MainActor public final class TripWeatherCoordinator {
    private let provider: any TripWeatherFetching
    private let timeout: Duration
    private var cache: [WeatherEvidence] = []
    public private(set) var requests = 0
    public init(provider: any TripWeatherFetching = WeatherKitTripProvider(), timeout: Duration = .seconds(45)) {
        self.provider = provider; self.timeout = timeout
    }
    public func resetMetrics() { requests = 0 }
    public func fetch(_ locations: [LocationReview], request: TripRequest, now: Date,
                      bypassCache: Bool = false) async throws -> [WeatherEvidence] {
        let pins = locations.compactMap { value in value.selected.map { (value.id, $0) } }
        let start = TripClock.calendar.dateInterval(of: .hour, for: request.departure)!.start
        let end = request.deadline.addingTimeInterval(3600)
        var output: [WeatherEvidence] = []
        var authenticationFailure: WeatherEvidence?
        for group in WeatherPolicy.groups(pins) {
            try Task.checkCancellation()
            let representative = group[0].1
            let members = group.map(\.0)
            if var skipped = authenticationFailure, !request.allowOpenMeteo {
                skipped.id = UUID().uuidString; skipped.representative = representative; skipped.memberIDs = members
                skipped.errors.append("Permintaan grup berikutnya dilewati setelah kegagalan otorisasi WeatherKit dalam operasi ini.")
                output.append(skipped); continue
            }
            if !bypassCache, var found = cache.first(where: {
                WeatherPolicy.canReuse($0, pin: representative, start: start, end: end,
                                       allowFallback: request.allowOpenMeteo, now: now)
            }) {
                // Every member must be within 3 km of the cached representative as well.
                if group.allSatisfy({ WeatherPolicy.distance($0.1, found.representative) <= 3000 }) {
                    found.memberIDs = members; found.cached = true; output.append(found); continue
                }
            }
            requests += 1
            let provider = self.provider
            let timeout = self.timeout
            var result: WeatherEvidence
            do {
                result = try await withThrowingTaskGroup(of: WeatherEvidence.self) { group in
                    // Hop through the Sendable actor-isolated protocol instead of annotating
                    // the task-group closure (which triggers an RBI compiler bug in Xcode 27.2).
                    group.addTask {
                        try await provider.fetch(pin: representative, memberIDs: members,
                                                 start: start, end: end, allowFallback: request.allowOpenMeteo, now: now)
                    }
                    group.addTask {
                        try await Task.sleep(for: timeout)
                        throw IntegrationError.invalid("Weather provider melewati batas waktu operasi.")
                    }
                    defer { group.cancelAll() }
                    return try await group.next()!
                }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                result = .init(id: UUID().uuidString, representative: representative, memberIDs: members,
                               provider: "weatherkit", status: "unavailable", fetchedAt: now, retrievedAt: now,
                               expiresAt: now, windowStart: start, windowEnd: end, hours: [], errors: [ProviderDiagnostics.message(error)])
            }
            try Task.checkCancellation()
            result.hours = WeatherPolicy.sanitized(result.hours)
            if result.status == "authentication_failure" { authenticationFailure = result }
            if result.complete { cache.append(result); cache = Array(cache.suffix(20)) }
            output.append(result)
        }
        return output
    }
}
