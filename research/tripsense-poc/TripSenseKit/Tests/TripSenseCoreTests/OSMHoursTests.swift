import Foundation
import Testing
@testable import TripSenseCore

private actor RequestCounter {
    var value = 0
    func increment() { value += 1 }
    func next(_ valid: Data) -> Data { value += 1; return value == 1 ? Data("bad".utf8) : valid }
}

@Suite @MainActor struct OSMHoursTests {
    let zone = TimeZone(identifier: "Asia/Jakarta")!
    let start = ISO8601DateFormatter().date(from: "2026-11-03T02:00:00Z")!
    let place = Place(id: "museum", name: "National Museum", coordinate: .init(-6.176, 106.822), category: "Museum", themes: [.history])
    func response(_ elements: String) -> Data { "{\"elements\":[\(elements)]}".data(using: .utf8)! }
    var good: String { """
    {"type":"node","id":123,"lat":-6.176,"lon":106.822,"tags":{"name":"National Museum","opening_hours":"Mo-Su 09:00-17:00","website":"https://example.org","check_date:opening_hours":"2026-10-01"}}
    """ }
    func provider(_ data: Data) -> OSMHoursProvider {
        OSMHoursProvider(diagnostics: Diagnostics(), loader: { _ in data }, gate: OSMRequestGate())
    }
    @Test func parsesWeeklyIntervalsAndOvernight() throws {
        let windows = try #require(WeeklyHoursParser.windows("Tu 08:00-12:00,13:00-17:00; We 22:00-02:00", start: start,
                                                             end: start.addingTimeInterval(3 * 86400), timeZone: zone))
        #expect(windows.count == 3)
        #expect(windows[0].opens == ISO8601DateFormatter().date(from: "2026-11-03T01:00:00Z"))
        #expect(windows[2].closes.timeIntervalSince(windows[2].opens) == 4 * 3600)
    }
    @Test func merges24HourWindowsForMidnightVisits() throws {
        let windows = try #require(WeeklyHoursParser.windows("24/7", start: start, end: start.addingTimeInterval(86400), timeZone: zone))
        #expect(windows.count == 1)
        #expect(windows[0].opens < start && windows[0].closes > start.addingTimeInterval(86400))
    }
    @Test func unsupportedRulesNeverPartiallyApply() {
        #expect(WeeklyHoursParser.windows("Mo-Fr 09:00-17:00; PH off", start: start, end: start.addingTimeInterval(86400), timeZone: zone) == nil)
        #expect(WeeklyHoursParser.windows("Mo-Fr sunrise-sunset", start: start, end: start.addingTimeInterval(86400), timeZone: zone) == nil)
        #expect(WeeklyHoursParser.windows("Tu 09:00-17:00; Tu 12:00-13:00", start: start, end: start.addingTimeInterval(86400), timeZone: zone) == nil)
        #expect(WeeklyHoursParser.windows("Tu 22:00-02:00; We off", start: start, end: start.addingTimeInterval(86400), timeZone: zone) == nil)
    }
    @Test func uniqueMatchReturnsSourcedHoursAndMetadata() async throws {
        let hours = await provider(response(good)).fetchHours(for: [place], start: start, end: start.addingTimeInterval(86400), timeZone: zone)
        guard case let .sourced(windows, metadata) = hours[place.id] else { Issue.record("Expected sourced hours"); return }
        #expect(!windows.isEmpty)
        #expect(metadata.objectID == "node/123")
        #expect(metadata.checkedDate == "2026-10-01")
        #expect(metadata.websiteURL?.host() == "example.org")
    }
    @Test func ambiguousOrDistantMatchesStayUnknown() async {
        let ambiguous = await provider(response(good + "," + good.replacingOccurrences(of: "123", with: "124"))).fetchHours(for: [place], start: start, end: start.addingTimeInterval(86400), timeZone: zone)
        #expect(ambiguous[place.id]?.windows == nil)
        let distant = await provider(response(good.replacingOccurrences(of: "-6.176", with: "-6.276"))).fetchHours(for: [place], start: start, end: start.addingTimeInterval(86400), timeZone: zone)
        #expect(distant[place.id]?.windows == nil)
    }
    @Test func addressConflictCannotAttachAnotherBranch() async {
        var addressed = place; addressed.address = "Jl. Merdeka No. 12, Jakarta"
        let data = response(good.replacingOccurrences(of: "\"name\":\"National Museum\"", with: "\"addr:housenumber\":\"14\",\"name\":\"National Museum\""))
        let hours = await provider(data).fetchHours(for: [addressed], start: start, end: start.addingTimeInterval(86400), timeZone: zone)
        #expect(hours[addressed.id]?.windows == nil)
    }
    @Test func invalidResponseIsNotCached() async {
        let counter = RequestCounter(); let valid = response(good)
        let service = OSMHoursProvider(diagnostics: Diagnostics(), loader: { _ in await counter.next(valid) }, gate: OSMRequestGate())
        let first = await service.fetchHours(for: [place], start: start, end: start.addingTimeInterval(86400), timeZone: zone)
        let second = await service.fetchHours(for: [place], start: start, end: start.addingTimeInterval(86400), timeZone: zone)
        #expect(first[place.id]?.windows == nil)
        #expect(second[place.id]?.windows != nil)
        #expect(await counter.value == 2)
    }
    @Test func cachedResponseIsReusedAndWebsiteSurvivesUnknownHours() async throws {
        let counter = RequestCounter()
        let raw = response(good.replacingOccurrences(of: "Mo-Su 09:00-17:00", with: "Mo-Fr 09:00-17:00; PH off"))
        let provider = OSMHoursProvider(diagnostics: Diagnostics(), loader: { _ in await counter.increment(); return raw }, gate: OSMRequestGate())
        let first = await provider.fetchHours(for: [place], start: start, end: start.addingTimeInterval(86400), timeZone: zone)
        let second = await provider.fetchHours(for: [place], start: start, end: start.addingTimeInterval(172800), timeZone: zone)
        #expect(first[place.id]?.windows == nil && second[place.id]?.windows == nil)
        #expect(await counter.value == 1)
        #expect(provider.websites[place.id]?.host() == "example.org")
        #expect(provider.sourceLinks[place.id]?.absoluteString == "https://www.openstreetmap.org/node/123")
    }
    @Test func invalidResponseAndOversizedDataStayUnknown() async {
        for data in [Data("invalid".utf8), Data(repeating: 0, count: 2_000_001)] {
            let hours = await provider(data).fetchHours(for: [place], start: start, end: start.addingTimeInterval(86400), timeZone: zone)
            #expect(hours[place.id]?.windows == nil)
        }
    }
}
