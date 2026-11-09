import Foundation
import Testing
@testable import PlannerEngine

@MainActor private final class CountingWeather: TripWeatherFetching {
    var calls = 0
    var authenticationFailure = false
    var fail = false
    func fetch(pin: PlacePin, memberIDs: [String], start: Date, end: Date,
               allowFallback: Bool, now: Date) async throws -> WeatherEvidence {
        calls += 1
        if fail { throw IntegrationError.invalid("Injected transport failure") }
        var value = try await ReplayWeather().fetch(pin: pin, memberIDs: memberIDs, start: start, end: end,
                                                    allowFallback: allowFallback, now: now)
        value.provider = allowFallback ? "open_meteo" : "weatherkit"
        if authenticationFailure { value.status = "authentication_failure"; value.hours = []; value.credit = nil }
        return value
    }
}

@MainActor private final class SlowWeather: TripWeatherFetching {
    func fetch(pin: PlacePin, memberIDs: [String], start: Date, end: Date,
               allowFallback: Bool, now: Date) async throws -> WeatherEvidence {
        try await Task.sleep(for: .seconds(60))
        throw IntegrationError.invalid("Slow injected provider")
    }
}

@Suite("P3 weather cache and isolated persistence", .serialized)
@MainActor struct WeatherStorageTests {
    let now = IntegrationReplay.now
    func location(_ id: String, lat: Double = -6.19) -> LocationReview {
        let pin = PlacePin(id: id, name: id, address: "Jakarta", latitude: lat, longitude: 106.83)
        return .init(id: id, query: id, candidates: [pin], selected: pin)
    }
    @Test func cacheReusedOnlyForCoveredFreshWindowAndProviderPolicy() async throws {
        let provider = CountingWeather(); let coordinator = TripWeatherCoordinator(provider: provider)
        var request = IntegrationReplay.request()
        let locations = [location("a")]
        _ = try await coordinator.fetch(locations, request: request, now: now)
        let cached = try await coordinator.fetch(locations, request: request, now: now.addingTimeInterval(60))
        #expect(provider.calls == 1); #expect(cached[0].cached)
        request.deadline = request.deadline.addingTimeInterval(3600)
        _ = try await coordinator.fetch(locations, request: request, now: now.addingTimeInterval(120))
        #expect(provider.calls == 2)
        _ = try await coordinator.fetch(locations, request: request, now: now.addingTimeInterval(901))
        #expect(provider.calls == 2) // The expanded window was fetched at now+120: still fresh.
        _ = try await coordinator.fetch(locations, request: request, now: now.addingTimeInterval(1021))
        #expect(provider.calls == 3)
    }
    @Test func fallbackCacheCannotMaskWeatherKitOnlyDiagnosis() async throws {
        let provider = CountingWeather(); let coordinator = TripWeatherCoordinator(provider: provider)
        var request = IntegrationReplay.request(); request.allowOpenMeteo = true
        _ = try await coordinator.fetch([location("a")], request: request, now: now)
        request.allowOpenMeteo = false
        let value = try await coordinator.fetch([location("a")], request: request, now: now.addingTimeInterval(60))
        #expect(provider.calls == 2)
        #expect(value[0].provider == "weatherkit")
        #expect(!value[0].cached)
    }
    @Test func cooperativeTimeoutProducesUnknownWeather() async throws {
        let coordinator = TripWeatherCoordinator(provider: SlowWeather(), timeout: .milliseconds(5))
        let result = try await coordinator.fetch([location("a")], request: IntegrationReplay.request(), now: now)
        #expect(result.count == 1)
        #expect(!result[0].complete && result[0].hours.isEmpty)
        #expect(result[0].errors.contains { $0.contains("batas waktu") })
    }
    @Test func authenticationFailureSkipsRemainingGroupsAndIsNotCached() async throws {
        let provider = CountingWeather(); provider.authenticationFailure = true
        let coordinator = TripWeatherCoordinator(provider: provider)
        let locations = [location("a"), location("b", lat: -6.30)]
        let first = try await coordinator.fetch(locations, request: IntegrationReplay.request(), now: now)
        #expect(provider.calls == 1); #expect(first.count == 2)
        #expect(first.allSatisfy { !$0.complete && $0.hours.isEmpty })
        _ = try await coordinator.fetch(locations, request: IntegrationReplay.request(), now: now)
        #expect(provider.calls == 2)
    }
    @Test func weatherFailureStillAllowsRouteWithExplicitUnknown() async throws {
        let provider = CountingWeather(); provider.fail = true
        let pipeline = IntegrationPipeline(catalog: try .load(), search: ReplaySearch(),
                                           weather: .init(provider: provider))
        pipeline.replayETA = { from, to, mode, departure in
            .init(id: "\(from.id)>\(to.id)", mode: mode, seconds: 1200, expectedDeparture: departure,
                  expectedArrival: departure.addingTimeInterval(1200), status: "available", note: "Injected replay")
        }
        let request = IntegrationReplay.request()
        let review = try await pipeline.recommend(request, now: now)
        let prepared = try await pipeline.prepare(review, selectedIDs: request.requiredCandidateIDs, now: now)
        let plan = try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: now)
        #expect(plan.feasible)
        #expect(plan.stops.allSatisfy { $0.rainChance == nil && $0.weatherProvider == nil })
        #expect(plan.weather.allSatisfy { !$0.complete })
        #expect(plan.uncertainties.contains { $0.contains("WeatherKit berhasil") })
    }
    @Test func corruptFileWithoutBackupDoesNotResetToEmpty() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("P3Corrupt-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: folder.appendingPathComponent("session.json"))
        let store = TripStore(directory: folder)
        await #expect(throws: (any Error).self) { try await store.load() }
        #expect(try Data(contentsOf: folder.appendingPathComponent("session.json")) == Data("broken".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix("session.corrupt-") })
    }
}
