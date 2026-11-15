import Foundation
import XCTest
@testable import C67LocalHarness

@MainActor private final class LabStub: WeatherLabProvider {
    var calls: [NativeTripWeatherProvider] = []
    var active = 0
    var maximum = 0
    var handler: ((NativeTripWeatherProvider, WeatherLabPoint, WeatherLabWindow) async throws -> WeatherLabPayload)?
    var now = Date(timeIntervalSince1970: 1_793_800_000)
    func fetch(_ provider: NativeTripWeatherProvider, point: WeatherLabPoint,
               window: WeatherLabWindow) async throws -> WeatherLabPayload {
        calls.append(provider); active += 1; maximum = max(maximum, active)
        defer { active -= 1 }
        if let handler { return try await handler(provider, point, window) }
        return payload(provider, point: point, window: window)
    }
    func payload(_ provider: NativeTripWeatherProvider, point: WeatherLabPoint,
                 window: WeatherLabWindow, expiry: Date? = nil) -> WeatherLabPayload {
        let credit = NativeTripWeatherCredit(serviceName: "Apple Weather",
                                             legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
                                             combinedMarkLightURL: URL(string: "https://weatherkit.apple.com/light.svg")!,
                                             combinedMarkDarkURL: URL(string: "https://weatherkit.apple.com/dark.svg")!)
        var cursor = window.hourly.start, hours: [NativeTripHour] = []
        while cursor < window.hourly.end {
            hours.append(.init(date: cursor, rainChance: Double(hours.count % 10) / 10, temperatureC: 29))
            cursor += 3_600
        }
        return .init(forecast: .init(pointID: point.id, hours: hours, status: "test", note: "Synthetic test fixture",
                                     fetchedAt: now, provider: provider, retrievedAt: now), expiresAt: expiry ?? now.addingTimeInterval(3_600),
                     credit: provider == .weatherKit ? credit : nil)
    }
}

@MainActor final class WeatherLabTests: XCTestCase {
    private let window = WeatherLabWindow(start: Date(timeIntervalSince1970: 1_793_800_800),
                                          end: Date(timeIntervalSince1970: 1_793_822_400))
    private func groups() throws -> [WeatherLabGroup] { try WeatherLabGroup.make(WeatherLabPoint.samples) }
    private func one() throws -> [WeatherLabGroup] { Array(try groups().prefix(1)) }
    private func engine(_ stub: LabStub, timeout: Double = 1) -> WeatherLabEngine {
        WeatherLabEngine(service: stub, timeout: timeout, now: { stub.now })
    }
    private func finish(_ model: WeatherLabModel) async throws {
        for _ in 0 ..< 300 {
            if !model.isRunning { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Model did not settle")
    }

    func testGroupingIsStableAndEveryMemberWithinRadius() async throws {
        let a = try groups(), b = try WeatherLabGroup.make(Array(WeatherLabPoint.samples.reversed()))
        XCTAssertEqual(a.count, 4)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.map { $0.members.map(\.id) }, b.map { $0.members.map(\.id) })
        XCTAssertEqual(a.flatMap(\.members).count, 6)
        XCTAssertTrue(a.allSatisfy { $0.maximumDistance <= 3_000 })
    }
    func testGroupingDoesNotChainDistantLocations() async throws {
        let points = [106.80, 106.82, 106.84].enumerated().map {
            WeatherLabPoint(id: "p\($0.offset)", name: "P", latitude: -6.2, longitude: $0.element)
        }
        let result = try WeatherLabGroup.make(points, radius: 2_500)
        XCTAssertEqual(result.map { $0.members.count }, [2, 1])
        XCTAssertTrue(result.allSatisfy { $0.maximumDistance <= 2_500 })
    }
    func testInvalidCoordinatesDuplicatesEmptyAndWindowAreRejected() async throws {
        XCTAssertThrowsError(try WeatherLabGroup.make([]))
        XCTAssertThrowsError(try WeatherLabGroup.make([WeatherLabPoint.samples[0], WeatherLabPoint.samples[0]]))
        var point = WeatherLabPoint.samples[0]; point.latitude = .nan
        XCTAssertThrowsError(try WeatherLabGroup.make([point]))
        point.latitude = -7; XCTAssertThrowsError(try WeatherLabGroup.make([point]))
        XCTAssertThrowsError(try WeatherLabWindow(start: window.end, end: window.start).validate())
        XCTAssertThrowsError(try WeatherLabWindow(start: window.start, end: window.start + 86_401).validate())
    }
    func testAutomaticUsesAppleWithAttributionAndNoBackup() async throws {
        let stub = LabStub(), e = engine(stub)
        let result = try await e.run(groups: groups(), window: window, mode: .automatic)
        XCTAssertTrue(result.allSatisfy { $0.payload?.forecast.provider == .weatherKit && $0.payload?.credit != nil })
        XCTAssertEqual(e.stats.weatherKitRequests, 4); XCTAssertEqual(e.stats.openMeteoRequests, 0)
    }
    func testReorderedGroupsAndNarrowerWindowReuseCache() async throws {
        let stub = LabStub(), e = engine(stub)
        _ = try await e.run(groups: groups(), window: window, mode: .automatic)
        let sub = WeatherLabWindow(start: window.start + 3_600, end: window.end - 3_600)
        let result = try await e.run(groups: Array(groups().reversed()), window: sub, mode: .automatic)
        XCTAssertEqual(e.stats.cacheHits, 4); XCTAssertEqual(e.stats.weatherKitRequests, 0)
        XCTAssertTrue(result.allSatisfy(\.cached)); XCTAssertEqual(stub.calls.count, 4)
    }
    func testDifferentRangeAndProviderCannotReuseWrongCache() async throws {
        let stub = LabStub(), e = engine(stub)
        _ = try await e.run(groups: one(), window: window, mode: .weatherKitOnly)
        _ = try await e.run(groups: one(), window: window, mode: .openMeteoOnly)
        XCTAssertEqual(e.stats.cacheHits, 0); XCTAssertEqual(e.stats.openMeteoRequests, 1)
        let shifted = WeatherLabWindow(start: window.start + 86_400, end: window.end + 86_400)
        _ = try await e.run(groups: one(), window: shifted, mode: .weatherKitOnly)
        XCTAssertEqual(e.stats.cacheHits, 0); XCTAssertEqual(e.stats.weatherKitRequests, 1)
    }
    func testCacheRespectsFifteenMinuteTTLAndAppleEarlierExpiry() async throws {
        let stub = LabStub(), e = engine(stub)
        var result = try await e.run(groups: one(), window: window, mode: .weatherKitOnly)
        XCTAssertEqual(try XCTUnwrap(result[0].payload).expiresAt, stub.now + 900)
        stub.now += 901
        result = try await e.run(groups: one(), window: window, mode: .weatherKitOnly)
        XCTAssertFalse(result[0].cached); XCTAssertEqual(e.stats.weatherKitRequests, 1)
        e.clearCache()
        stub.handler = { provider, point, range in stub.payload(provider, point: point, window: range, expiry: stub.now + 30) }
        result = try await e.run(groups: one(), window: window, mode: .weatherKitOnly)
        XCTAssertEqual(try XCTUnwrap(result[0].payload).expiresAt, stub.now + 30)
        stub.now += 31
        _ = try await e.run(groups: one(), window: window, mode: .weatherKitOnly)
        XCTAssertEqual(e.stats.weatherKitRequests, 1)
    }
    func testAuthenticationBreakerStopsFurtherAppleAndResetRetries() async throws {
        let stub = LabStub(), e = engine(stub)
        stub.handler = { provider, point, range in
            if provider == .weatherKit { throw WeatherLabError.authentication("fixture") }
            return stub.payload(provider, point: point, window: range)
        }
        let results = try await e.run(groups: groups(), window: window, mode: .automatic)
        XCTAssertTrue(e.authenticationBlocked); XCTAssertEqual(e.stats.weatherKitRequests, 1)
        XCTAssertEqual(e.stats.openMeteoRequests, 4)
        XCTAssertTrue(results.allSatisfy { $0.payload?.forecast.provider == .openMeteo })
        _ = try await e.run(groups: groups(), window: window, mode: .automatic)
        XCTAssertEqual(e.stats.weatherKitRequests, 0); XCTAssertEqual(e.stats.cacheHits, 4)
        e.resetAuthentication()
        _ = try await e.run(groups: one(), window: window, mode: .automatic)
        XCTAssertEqual(e.stats.weatherKitRequests, 1)
    }
    func testAuthenticationClassifierDoesNotTreatEveryCodeTwoAsAuth() async throws {
        XCTAssertTrue(WeatherLabError.isAuthentication(NSError(domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors", code: 2)))
        XCTAssertFalse(WeatherLabError.isAuthentication(NSError(domain: "unrelated", code: 2)))
        XCTAssertTrue(WeatherLabError.isAuthentication(NSError(domain: "WeatherDaemon.WDSJWTAuthenticatorServiceProxy.Errors", code: 0)))
        XCTAssertFalse(WeatherLabError.isAuthentication(NSError(domain: "WeatherDaemon.WDSJWTAuthenticatorServiceProxy.Errors", code: 1)))
        let inner = NSError(domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors", code: 2)
        XCTAssertTrue(WeatherLabError.isAuthentication(NSError(domain: "wrapper", code: 99, userInfo: [NSUnderlyingErrorKey: inner])))
    }
    func testProbeBypassesCacheBreakerAndNeverFallsBack() async throws {
        let stub = LabStub(), e = engine(stub)
        _ = try await e.run(groups: one(), window: window, mode: .weatherKitOnly)
        stub.handler = { _, _, _ in throw WeatherLabError.authentication("fixture") }
        let result = try await e.run(groups: groups(), window: window, mode: .automatic, probe: true)
        XCTAssertEqual(result.count, 1); XCTAssertNil(result[0].payload)
        XCTAssertEqual(e.stats.cacheHits, 0); XCTAssertEqual(e.stats.weatherKitRequests, 1); XCTAssertEqual(e.stats.openMeteoRequests, 0)
        _ = try await e.run(groups: groups(), window: window, mode: .automatic, probe: true)
        XCTAssertEqual(e.stats.weatherKitRequests, 1); XCTAssertEqual(e.stats.openMeteoRequests, 0)
    }
    func testMissingHoursMissingCreditAndExpiredResponseAreNotPublished() async throws {
        for problem in 0 ..< 3 {
            let stub = LabStub(), e = engine(stub)
            stub.handler = { provider, point, range in
                var payload = stub.payload(provider, point: point, window: range)
                if problem == 0 { payload.forecast.hours.removeLast() }
                if problem == 1 { payload.credit = nil }
                if problem == 2 { payload.expiresAt = stub.now - 1 }
                return payload
            }
            let result = try await e.run(groups: one(), window: window, mode: .weatherKitOnly)
            XCTAssertNil(result[0].payload); XCTAssertEqual(e.cacheCount, 0)
        }
    }
    func testBothFailuresRemainUnknownInsteadOfZeroRain() async throws {
        let stub = LabStub(), e = engine(stub)
        stub.handler = { _, _, _ in throw URLError(.notConnectedToInternet) }
        let result = try await e.run(groups: one(), window: window, mode: .automatic)
        XCTAssertNil(result[0].payload); XCTAssertEqual(result[0].notes.count, 2)
        XCTAssertEqual(e.cacheCount, 0); XCTAssertEqual(stub.calls.count, 2)
    }
    func testRefreshAndClearCacheForceNewRequests() async throws {
        let stub = LabStub(), e = engine(stub)
        _ = try await e.run(groups: one(), window: window, mode: .openMeteoOnly)
        let refreshed = try await e.run(groups: one(), window: window, mode: .openMeteoOnly, refresh: true)
        XCTAssertFalse(refreshed[0].cached); XCTAssertEqual(e.stats.openMeteoRequests, 1)
        e.clearCache(); XCTAssertEqual(e.cacheCount, 0)
        _ = try await e.run(groups: one(), window: window, mode: .openMeteoOnly)
        XCTAssertEqual(e.stats.openMeteoRequests, 1)
    }
    func testConcurrencyIsBoundedToTwoGroups() async throws {
        let stub = LabStub(), e = engine(stub)
        stub.handler = { provider, point, range in
            try await Task.sleep(nanoseconds: 20_000_000)
            return stub.payload(provider, point: point, window: range)
        }
        let result = try await e.run(groups: groups(), window: window, mode: .openMeteoOnly)
        XCTAssertEqual(result.count, 4); XCTAssertEqual(e.stats.maxConcurrentGroups, 2); XCTAssertEqual(stub.maximum, 2)
    }
    func testTransientRetryIsAtMostOnceWithinProviderBudget() async throws {
        let stub = LabStub(), e = engine(stub)
        stub.handler = { provider, point, range in
            if stub.calls.count == 1 { throw URLError(.networkConnectionLost) }
            return stub.payload(provider, point: point, window: range)
        }
        let result = try await e.run(groups: one(), window: window, mode: .weatherKitOnly)
        XCTAssertNotNil(result[0].payload); XCTAssertEqual(e.stats.weatherKitRequests, 2)
        e.clearCache(); stub.handler = { _, _, _ in throw URLError(.networkConnectionLost) }
        _ = try await e.run(groups: one(), window: window, mode: .weatherKitOnly)
        XCTAssertEqual(e.stats.weatherKitRequests, 2)
    }
    func testLateUncooperativeProviderCannotDelayFallbackOrFillCache() async throws {
        let stub = LabStub(), e = engine(stub, timeout: 0.02)
        var release: CheckedContinuation<WeatherLabPayload, Never>?
        stub.handler = { provider, point, range in
            if provider == .weatherKit { return await withCheckedContinuation { release = $0 } }
            return stub.payload(provider, point: point, window: range)
        }
        let started = Date()
        let result = try await e.run(groups: one(), window: window, mode: .automatic)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertEqual(result[0].payload?.forecast.provider, .openMeteo); XCTAssertEqual(e.cacheCount, 1)
        let group = try XCTUnwrap(one().first)
        release?.resume(returning: stub.payload(.weatherKit, point: group.representative, window: window)); release = nil
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(e.cacheCount, 1); XCTAssertFalse(e.authenticationBlocked)
    }
    func testCancellationStopsFallbackAndIgnoresLateResponse() async throws {
        let stub = LabStub(), e = engine(stub)
        var release: CheckedContinuation<WeatherLabPayload, Never>?
        stub.handler = { _, _, _ in await withCheckedContinuation { release = $0 } }
        let target = try one()
        let task = Task { try await e.run(groups: target, window: window, mode: .automatic) }
        while release == nil { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(e.stats.openMeteoRequests, 0); XCTAssertEqual(e.cacheCount, 0)
        release?.resume(returning: stub.payload(.weatherKit, point: target[0].representative, window: window)); release = nil
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(e.cacheCount, 0)
    }
    func testModelReportsSimulationProvenanceAndCapturedWindow() async throws {
        let stub = LabStub(), e = engine(stub), model = WeatherLabModel(engine: e, simulated: true)
        model.start = window.start; model.end = window.end; model.mode = .openMeteoOnly
        model.run(); try await finish(model)
        XCTAssertEqual(model.results.count, 4); XCTAssertFalse(model.isRunning)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(model.reportJSON.utf8)) as? [String: Any])
        XCTAssertEqual(json["simulation"] as? Bool, true)
        XCTAssertEqual(json["mode"] as? String, "openMeteoOnly")
        model.start += 86_400
        XCTAssertEqual(model.resultWindow, window)
        XCTAssertTrue(model.reportJSON.contains("Synthetic test fixture"))
        let export = try XCTUnwrap(model.reportURL)
        XCTAssertEqual(try String(contentsOf: export, encoding: .utf8), model.reportJSON)
    }
    func testModelCancelThenNewRunCannotReceiveOldResults() async throws {
        let stub = LabStub(), e = engine(stub), model = WeatherLabModel(engine: e, simulated: true)
        var release: CheckedContinuation<WeatherLabPayload, Never>?
        stub.handler = { _, _, _ in await withCheckedContinuation { release = $0 } }
        model.start = window.start; model.end = window.end
        model.run(probe: true)
        while release == nil { await Task.yield() }
        model.cancel(); model.run(); try await finish(model)
        XCTAssertTrue(model.results.isEmpty); XCTAssertTrue(model.status.contains("Dibatalkan"))
        stub.handler = nil; model.mode = .openMeteoOnly
        model.run(); try await finish(model)
        XCTAssertEqual(model.results.count, 4)
        let target = try XCTUnwrap(one().first)
        release?.resume(returning: stub.payload(.weatherKit, point: target.representative, window: window)); release = nil
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(model.results.count, 4)
        XCTAssertTrue(model.results.allSatisfy { $0.payload?.forecast.provider == .openMeteo })
    }
    func testLabDefaultAndExplicitNativeLaunchRemainSeparate() async throws {
        XCTAssertTrue(WeatherLabLaunchRouting.showsLab(arguments: []))
        for argument in ["--native-itinerary", "--jakarta-ui-testing", "--active-ui-testing"] {
            XCTAssertFalse(WeatherLabLaunchRouting.showsLab(arguments: [argument]))
        }
        XCTAssertTrue(WeatherLabLaunchRouting.showsLab(arguments: ["--weather-lab"]))
    }
    func testSuccessfulFreshProbeReopensAuthenticationCircuit() async throws {
        let stub = LabStub(), e = engine(stub)
        stub.handler = { _, _, _ in throw WeatherLabError.authentication("fixture") }
        _ = try await e.run(groups: one(), window: window, mode: .automatic)
        XCTAssertTrue(e.authenticationBlocked)
        stub.handler = nil
        let result = try await e.run(groups: groups(), window: window, mode: .automatic, probe: true)
        XCTAssertNotNil(result[0].payload); XCTAssertFalse(e.authenticationBlocked)
        XCTAssertEqual(e.stats.weatherKitRequests, 1); XCTAssertEqual(e.stats.openMeteoRequests, 0)
        XCTAssertEqual(e.cacheCount, 0)
    }
    func testImportCopiesCoordinatesWithoutChangingStoredPlan() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeTripLocalStore(directory: directory)
        let draft = NativeTripDraft.jakartaFivePlaces()
        _ = try store.commit(.init(draft: draft), expected: nil)
        let before = try Data(contentsOf: store.primaryURL)
        let stub = LabStub(), model = WeatherLabModel(engine: engine(stub), simulated: true,
                                                      loadSavedDraft: { try store.load().session?.draft })
        model.importSavedPlan()
        XCTAssertEqual(model.points.count, draft.allPoints.count)
        XCTAssertEqual(model.start, draft.departure); XCTAssertEqual(model.end, draft.deadline)
        XCTAssertEqual(try Data(contentsOf: store.primaryURL), before)
        XCTAssertTrue(stub.calls.isEmpty)
    }
    func testImportNeverSilentlyDropsUnresolvedPlace() async throws {
        var draft = NativeTripDraft.jakartaFivePlaces()
        draft.stops[0].point.latitude = nil
        let stub = LabStub(), model = WeatherLabModel(engine: engine(stub), simulated: true,
                                                      loadSavedDraft: { draft })
        let before = model.points
        model.importSavedPlan()
        XCTAssertEqual(model.points, before)
        XCTAssertTrue(model.status.contains("belum memiliki koordinat"))
    }
}
