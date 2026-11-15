import Foundation
import PlaceContextEngine
import DynamicTripContracts

@MainActor public enum ContextExperiments {
    public static let scenarios: [ContextScenario] = [
        .init(id: "dry", title: "Cuaca kering, jam buka normal"),
        .init(id: "rain_morning", title: "Hujan pagi, outdoor setelah hujan"),
        .init(id: "rain_afternoon", title: "Hujan sore, outdoor lebih awal"),
        .init(id: "rain_indoor", title: "Aktivitas taman dipindah ke indoor"),
        .init(id: "weather_missing", title: "Prakiraan belum tersedia"),
        .init(id: "weather_stale", title: "Prakiraan kedaluwarsa"),
        .init(id: "exposure_unknown", title: "Paparan aktivitas belum diketahui"),
        .init(id: "early_close", title: "Museum tutup pukul 10.30"),
        .init(id: "late_open", title: "Museum baru buka pukul 12.00"),
        .init(id: "split_session", title: "Museum buka 09–10.30 dan 13–18"),
        .init(id: "closed", title: "Museum tutup sehari"),
        .init(id: "hours_stale", title: "Jam operasional kedaluwarsa"),
        .init(id: "required_conflict", title: "Jam wajib berbenturan dengan jam tutup"),
        .init(id: "tight_deadline", title: "Deadline tidak memuat semua kunjungan"),
        .init(id: "eta_unavailable", title: "ETA tidak tersedia"),
        .init(id: "budget_cut", title: "Anggaran ETA di bawah satu perjalanan"),
        .init(id: "five_grid15", title: "Lima tujuan dengan grid 15 menit"),
        .init(id: "five_grid5", title: "Lima tujuan dengan grid 5 menit")
    ]

    private struct FixedTravel: ContextTravelProvider {
        var seconds: Double
        var unavailable: Bool
        func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
            guard !unavailable else { return nil }
            return .init(seconds: seconds, departure: departure, source: "SYNTHETIC controlled fixed travel")
        }
    }

    public static func run(_ id: String, now: Date = .now) async throws -> ContextExperimentResponse {
        guard let scenario = scenarios.first(where: { $0.id == id }) else { throw ContextError.invalid("Unknown controlled scenario") }
        let began = ContinuousClock.now
        let base = ContextClock.calendar.startOfDay(for: now).addingTimeInterval(86400)
        let day = ContextClock.label(base)
        let five = id.hasPrefix("five_")
        let ids = five ? ["museum", "park", "gallery", "library", "exhibit"] : ["museum", "park", "gallery"]
        let travel = five ? 137.0 : 900.0
        var stops: [ContextPlanStop] = []
        for key in ids {
            var bounds = [[540, 1080]]
            if key == "museum" {
                switch id {
                case "early_close", "required_conflict": bounds = [[540, 630]]
                case "late_open": bounds = [[720, 1080]]
                case "split_session": bounds = [[540, 630], [780, 1080]]
                case "closed": bounds = []
                default: break
                }
            }
            let periods = (0 ... 6).flatMap { weekday in
                bounds.map { range in
                    ["open": ["day": weekday, "hour": range[0] / 60, "minute": range[0] % 60],
                     "close": ["day": weekday, "hour": range[1] / 60, "minute": range[1] % 60]]
                }
            }
            let object: [String: Any] = ["id": key, "displayName": ["text": "SYNTHETIC " + key],
                                         "businessStatus": "OPERATIONAL", "timeZone": ["id": "Asia/Jakarta"],
                                         "regularOpeningHours": ["periods": periods]]
            let place = try JSONDecoder().decode(VenuePlace.self, from: JSONSerialization.data(withJSONObject: object))
            var snapshot = PlaceSnapshot(place: place, fetchedAt: now, fieldMask: "SYNTHETIC", source: "SYNTHETIC controlled hours")
            if id == "hours_stale" && key == "museum" { snapshot.expiresAt = now.addingTimeInterval(-1) }
            var request = VisitContextRequest(placeID: key, day: day)
            request.identityConfirmed = true; request.availableStart = 540; request.availableEnd = 1080
            request.durationMinutes = 60; request.startStepMinutes = id == "five_grid15" ? 15 : 5
            request.exposure = key == "park" ? .outdoor : .indoor
            request.exposureEvidence = "SYNTHETIC activity classification"
            request.avoidRain = key == "park"
            if id == "rain_indoor" && key == "park" { request.exposure = .indoor }
            if id == "exposure_unknown" && key == "park" { request.exposure = .unknown }
            if id == "required_conflict" && key == "museum" { request.preferredTime = .init(earliest: 900, latest: 900, required: true) }
            let weatherHours = (8 ... 19).map { hour in
                var probability = 0.0
                if id == "rain_morning" || id == "rain_indoor" { probability = hour < 12 ? 0.9 : 0.05 }
                if id == "rain_afternoon" { probability = hour < 12 ? 0.05 : 0.9 }
                return WeatherContextHour(start: base.addingTimeInterval(Double(hour * 3600)), rainProbability: probability, temperatureC: 28)
            }
            var weather: VisitWeatherContext? = .init(source: "SYNTHETIC hourly weather", fetchedAt: now,
                                                      expiresAt: now.addingTimeInterval(900), hours: weatherHours)
            if id == "weather_missing" { weather = nil }
            if id == "weather_stale" { weather?.expiresAt = now.addingTimeInterval(-1) }
            stops.append(.init(snapshot: snapshot, request: request, weather: weather))
        }
        var input = ContextPlanRequest(originID: "origin", returnID: "origin", departure: base.addingTimeInterval(9 * 3600),
                                       deadline: base.addingTimeInterval(Double((id == "tight_deadline" ? 11 : 18) * 3600)), stops: stops)
        input.maximumTotalWaitingMinutes = 30; input.allVisitSlots = true
        input.policy = .beam; input.beamWidth = 12; input.maxTravelCalls = id == "budget_cut" ? 2 : 96
        let preparation = DynamicTripService.seconds(began)
        let routeStart = ContinuousClock.now
        let result = try await ContextItineraryPlanner.plan(input, provider: FixedTravel(seconds: travel, unavailable: id == "eta_unavailable"), now: now)
        let routing = DynamicTripService.seconds(routeStart)
        let output = DynamicPlanResponse(itinerary: result, metrics: .init(preparationSeconds: preparation,
                                                                           routingSeconds: routing, etaAdapterSeconds: 0, serverTotalSeconds: DynamicTripService.seconds(began), etaCalls: result.travelCalls,
                                                                           unavailableETA: id == "eta_unavailable" ? result.travelCalls : 0, weatherStatus: id == "weather_missing" ? "missing" : "synthetic",
                                                                           evidenceMode: "CONTROLLED_SYNTHETIC"))
        return .init(scenario: scenario, input: input, now: now, fixedTravelSeconds: travel,
                     travelUnavailable: id == "eta_unavailable", output: output)
    }
}
