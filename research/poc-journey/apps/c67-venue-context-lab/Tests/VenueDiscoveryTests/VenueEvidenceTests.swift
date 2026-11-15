import Foundation
import XCTest
import PlaceContextEngine
@testable import VenueDiscovery

final class VenueEvidenceTests: XCTestCase {
    func testUnknownIsCachedForThirtyDays() {
        let checked = Date(timeIntervalSince1970: 1_700_000_000)
        let fact = VenueFact.unknown(.access, at: checked)
        XCTAssertTrue(fact.fresh(at: checked.addingTimeInterval(30 * 86400 - 1)))
        XCTAssertFalse(fact.fresh(at: checked.addingTimeInterval(30 * 86400)))
    }

    func testWeeklyHoursMustMatchCitedDaysAndTimes() {
        let weekdays = (2 ... 6).map { VenueHours(weekday: $0, startMinute: 540, endMinute: 1020, closed: false) }
        XCTAssertTrue(VenueHours.supported(weekdays, quote: "Senin–Jumat 09.00–17.00"))
        XCTAssertFalse(VenueHours.supported(weekdays, quote: "Sabtu 09.00–17.00"))
        XCTAssertFalse(VenueHours.supported(weekdays, quote: "Senin–Jumat 10.00–17.00"))
        XCTAssertFalse(VenueHours.supported(weekdays, quote: "Acara sementara Senin–Jumat 09.00–17.00"))
    }

    func testHoursStopApplyingAfterEvidenceValidity() throws {
        let checked = try XCTUnwrap(ContextClock.day("2026-11-10"))
        let fact = VenueFact(field: .hours, status: "supported", value: "Setiap hari", checkedAt: checked,
                             hours: (1 ... 7).map { .init(weekday: $0, startMinute: 540, endMinute: 1020, closed: false) },
                             validThrough: "2026-11-12")
        XCTAssertEqual(fact.resolution(day: "2026-11-12")?.state, "available")
        XCTAssertNil(fact.resolution(day: "2026-11-13"))
    }

    func testOvernightHoursSplitAtMidnight() throws {
        let saturday = try XCTUnwrap(ContextClock.day("2026-11-14"))
        let row = VenueHours(weekday: 7, startMinute: 20 * 60, endMinute: 26 * 60, closed: false)
        XCTAssertTrue(VenueHours.supported([row], quote: "Sabtu 20.00–02.00"))
        let fact = VenueFact(field: .hours, status: "supported", value: "Sabtu", checkedAt: saturday, hours: [row])
        let sunday = try XCTUnwrap(fact.resolution(day: "2026-11-15")?.intervals.first)
        XCTAssertEqual(sunday.start, saturday.addingTimeInterval(24 * 3600))
        XCTAssertEqual(sunday.end.timeIntervalSince(sunday.start), 2 * 3600)
    }
}

extension VenueEvidenceTests {
    func testDirectoryExcerptKeepsTheRequestedBranch() throws {
        let venue = OpenVenue(id: "osm-node-1", name: "Periplus Setiabudi One", aliases: ["Periplus"],
                              address: "Setiabudi One", branch: "Setiabudi One", latitude: -6.21, longitude: 106.82,
                              categories: ["book_store"], sourceIDs: ["osm-node-1"], sourceURLs: [],
                              operatorHosts: ["periplus.com"], branchAliases: ["Setiabudi One"])
        let page = SourcePage(url: try XCTUnwrap(URL(string: "https://www.periplus.com/_index_/Store-Locator")),
                              text: """
                              Setiabudi One
                              Lantai dasar
                              Jakarta Selatan

                              Business Hours

                              Kontak cabang
                              periplus.setiabudi
                              Periplus Lotte Mall Jakarta
                              Unit 08
                              Jakarta Selatan

                              Business Hours
                              Every Day 10.00 - 22.00
                              """, fetchedAt: Date())
        let excerpt = try XCTUnwrap(VenueEnrichment.excerpt(page, venue: venue))
        XCTAssertTrue(excerpt.text.contains("Setiabudi One"))
        XCTAssertFalse(excerpt.text.contains("Lotte"))
        XCTAssertFalse(excerpt.text.contains("22.00"))
    }
}
