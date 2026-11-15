import Foundation
import Testing
@testable import TripSenseCore

@MainActor private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}
private actor Attempts {
    var count = 0
    func hit() { count += 1 }
    func next() -> Int { count += 1; return count }
}

@Suite @MainActor struct OverpassRequestTests {
    let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    let place = Place(id: "test", name: "Test", coordinate: .init(-6.1754, 106.8272), category: "Museum", themes: [.history])
    func fetch(_ provider: OSMHoursProvider) async -> [String: OpeningHours] {
        await provider.fetchHours(for: [place], start: Date(), end: Date().addingTimeInterval(3600), timeZone: TimeZone(identifier: "Asia/Jakarta")!)
    }
    @Test func requestUsesClearIdentityAndLongerTimeout() {
        let request = OverpassHTTP.request(endpoint: endpoint, query: "[out:json];node(1);out;")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 60)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("TripSensePOC/0.1") == true)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(String(data: request.httpBody!, encoding: .utf8)?.contains("data=") == true)
    }
    @Test func retryAfterAcceptsSecondsAndHTTPDate() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(OSMRequestGate.retryDate("120", now: date) == date.addingTimeInterval(120))
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        #expect(OSMRequestGate.retryDate(formatter.string(from: date.addingTimeInterval(90)), now: date) == date.addingTimeInterval(90))
        for invalid in ["bad", "-5", "1.5", ""] { #expect(OSMRequestGate.retryDate(invalid, now: date) == nil) }
    }
    @Test func minimumCooldownAndLongerServerDelayAreHonored() throws {
        let clock = TestClock(); let gate = OSMRequestGate(now: { clock.now })
        #expect(gate.reject(endpoint, retryAfter: "5") == clock.now.addingTimeInterval(30))
        #expect(throws: (any Error).self) { try gate.acquire(endpoint) }
        clock.now = clock.now.addingTimeInterval(31)
        try gate.acquire(endpoint); gate.release(endpoint)
        #expect(gate.reject(endpoint, retryAfter: "120") == clock.now.addingTimeInterval(120))
    }
    @Test func status406And429SuppressNewProviderRequestsUntilCooldownExpires() async {
        for status in [406, 429] {
            let clock = TestClock(); let gate = OSMRequestGate(now: { clock.now }); let attempts = Attempts()
            let loader: OSMHoursProvider.Loader = { _ in await attempts.hit(); throw HoursServiceError.httpStatus(status, retryAfter: "90") }
            let first = await fetch(OSMHoursProvider(diagnostics: Diagnostics(), loader: loader, gate: gate))
            let blocked = await fetch(OSMHoursProvider(diagnostics: Diagnostics(), loader: loader, gate: gate))
            #expect(first[place.id]?.windows == nil && blocked[place.id]?.windows == nil)
            #expect(await attempts.count == 1)
            clock.now = clock.now.addingTimeInterval(89)
            _ = await fetch(OSMHoursProvider(diagnostics: Diagnostics(), loader: loader, gate: gate))
            #expect(await attempts.count == 1)
            clock.now = clock.now.addingTimeInterval(2)
            _ = await fetch(OSMHoursProvider(diagnostics: Diagnostics(), loader: loader, gate: gate))
            #expect(await attempts.count == 2)
        }
    }
    @Test func pastDateAndInvalidRetryHeaderStillPauseThirtySeconds() {
        let clock = TestClock()
        for header in [nil, "invalid", "0", "Wed, 01 Jan 2020 00:00:00 GMT"] as [String?] {
            let gate = OSMRequestGate(now: { clock.now })
            #expect(gate.reject(endpoint, retryAfter: header) == clock.now.addingTimeInterval(30))
        }
    }
    @Test func cancellationReleasesTheEndpointGate() async throws {
        let gate = OSMRequestGate(); let attempts = Attempts()
        let provider = OSMHoursProvider(diagnostics: Diagnostics(), loader: { _ in
            if await attempts.next() == 1 { try await Task.sleep(for: .seconds(30)) }
            return Data("{\"elements\":[]}".utf8)
        }, gate: gate)
        let task = Task { await fetch(provider) }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel(); _ = await task.value
        _ = await fetch(provider)
        #expect(await attempts.count == 2)
    }
    @Test func defaultSharedGateSurvivesProviderRecreation() async {
        let unique = URL(string: "https://shared-gate-test.invalid/api/interpreter")!
        let attempts = Attempts()
        let loader: OSMHoursProvider.Loader = { _ in await attempts.hit(); throw HoursServiceError.httpStatus(406, retryAfter: nil) }
        _ = await fetch(OSMHoursProvider(diagnostics: Diagnostics(), endpoint: unique, loader: loader))
        let result = await fetch(OSMHoursProvider(diagnostics: Diagnostics(), endpoint: unique, loader: loader))
        #expect(result[place.id]?.windows == nil)
        #expect(await attempts.count == 1)
    }
    @Test func gatePreventsConcurrentRequestsOnTheSameHost() throws {
        let gate = OSMRequestGate()
        try gate.acquire(endpoint)
        #expect(throws: (any Error).self) { try gate.acquire(URL(string: "https://overpass-api.de/api/status")!) }
        gate.release(endpoint)
        try gate.acquire(endpoint); gate.release(endpoint)
    }
}
