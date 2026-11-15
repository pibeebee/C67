import Foundation
import PreferenceQuality

/// Engineering replay only. Coordinates, travel and weather below are authored inputs,
/// not MapKit/WeatherKit observations. Published venue hours keep their original dates.
@MainActor public enum IntegrationReplay {
    public static let now = TripClock.date("2026-11-05T07:00:00Z")
    public static func request() -> TripRequest {
        var value = TripRequest(now: now)
        value.useEmbedding = false
        value.requiredCandidateIDs = ["cikini", "bdt-rbbj"]
        value.desiredCount = 2
        return value
    }
    public static func pipeline() throws -> IntegrationPipeline {
        let pipeline = IntegrationPipeline(catalog: try .load(), search: ReplaySearch(),
                                           weather: TripWeatherCoordinator(provider: ReplayWeather()), logDirectory:
                                           FileManager.default.temporaryDirectory.appendingPathComponent("C67P3ReplayLogs-\(UUID())"))
        pipeline.replayETA = { from, to, mode, departure in
            try Task.checkCancellation()
            return NativeTripETA(id: "\(from.id)>\(to.id)", mode: mode, seconds: 1200,
                                 distance: 5000, expectedDeparture: departure, expectedArrival: departure.addingTimeInterval(1200),
                                 status: "available", note: "Synthetic 20-minute leg for P3 replay; not MapKit ETA.")
        }
        return pipeline
    }
}

@MainActor final class ReplaySearch: TripPlaceSearching {
    func cancel() {}
    func search(query: String) async throws -> [PlacePin] {
        let lower = query.lowercased()
        var pin: PlacePin
        if lower.contains("bundaran") {
            pin = .init(id: "replay-origin", name: "Bundaran HI", address: "Jakarta Pusat", latitude: -6.195, longitude: 106.823)
        } else if lower.contains("tebet") {
            pin = .init(id: "replay-bdt", name: "Baca Di Tebet", address: "Tebet, Jakarta Selatan", latitude: -6.238, longitude: 106.853)
        } else if lower.contains("cikini") {
            pin = .init(id: "replay-cikini", name: "Perpustakaan Jakarta Cikini", address: "Cikini, Jakarta Pusat", latitude: -6.190, longitude: 106.839)
        } else if lower.contains("erasmus") {
            pin = .init(id: "replay-erasmus", name: "Erasmus Huis Library", address: "Kuningan Jakarta Selatan", latitude: -6.229, longitude: 106.832)
        } else if lower.contains("ragunan") {
            pin = .init(id: "replay-ragunan", name: "Taman Margasatwa Ragunan", address: "Jakarta Selatan", latitude: -6.311, longitude: 106.820)
        } else {
            pin = .init(id: "replay-gbk", name: "Hutan Kota GBK", address: "Gelora Jakarta", latitude: -6.220, longitude: 106.807)
        }
        pin.source = "Synthetic replay coordinate; not an observed MapKit result"
        return [pin]
    }
}

@MainActor final class ReplayWeather: TripWeatherFetching {
    func fetch(pin: PlacePin, memberIDs: [String], start: Date, end: Date,
               allowFallback: Bool, now: Date) async throws -> WeatherEvidence {
        let count = Int(ceil(end.timeIntervalSince(start) / 3600))
        return WeatherEvidence(id: "replay-\(pin.id)", representative: pin, memberIDs: memberIDs,
                               provider: "synthetic_replay", status: "available", fetchedAt: now, retrievedAt: now,
                               expiresAt: now.addingTimeInterval(900), windowStart: start, windowEnd: end,
                               hours: (0 ..< count).map { .init(start: start.addingTimeInterval(Double($0) * 3600), rainChance: $0 < 5 ? 0.1 : 0.8) },
                               sunrise: TripClock.calendar.date(bySettingHour: 5, minute: 30, second: 0, of: start),
                               sunset: TripClock.calendar.date(bySettingHour: 17, minute: 45, second: 0, of: start),
                               credit: .init(name: "AUTHORED REPLAY · not a weather provider", legalURL: URL(string: "https://example.invalid/p3-replay")!),
                               errors: ["Synthetic weather scenario; no live provider request."])
    }
}
