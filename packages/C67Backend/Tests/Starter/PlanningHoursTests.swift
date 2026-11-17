import Foundation
import Testing
@testable import C67Domain

private func hours(_ start: Int, _ end: Int, zone: String = "Asia/Jakarta") throws -> PlanningRegularHours {
    let days = (1 ... 7).map { day in "{\"weekday\":\(day),\"intervals\":[{\"startSeconds\":\(start),\"endSeconds\":\(end)}]}" }.joined(separator: ",")
    return try JSONDecoder().decode(PlanningRegularHours.self, from: Data("{\"placeId\":\"I123\",\"timezone\":\"\(zone)\",\"weekly\":[\(days)]}".utf8))
}

private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

@Test func regularHoursCheckFullVisitAndBoundaries() throws {
    let value = try hours(36_000, 79_200)
    #expect(value.match(start: instant("2026-11-17T03:00:00Z"), end: instant("2026-11-17T04:00:00Z")) == .within)
    #expect(value.match(start: instant("2026-11-17T02:30:00Z"), end: instant("2026-11-17T03:30:00Z")) == .partial)
    #expect(value.match(start: instant("2026-11-17T01:00:00Z"), end: instant("2026-11-17T02:00:00Z")) == .outside)
}

@Test func overnightHoursUsePreviousDayAndEndExclusively() throws {
    let value = try hours(36_000, 7200)
    #expect(value.match(start: instant("2026-11-17T17:00:00Z"), end: instant("2026-11-17T18:00:00Z")) == .within)
    #expect(value.match(start: instant("2026-11-17T19:00:00Z"), end: instant("2026-11-17T19:30:00Z")) == .outside)
}

@Test func invalidTimeZoneRemainsUnknown() throws {
    let value = try hours(36_000, 79_200, zone: "Not/AZone")
    #expect(value.match(start: instant("2026-11-17T03:00:00Z"), end: instant("2026-11-17T04:00:00Z")) == .unknown)
}
