import Foundation
import XCTest
import PlaceContextEngine
@testable import VenueDiscovery

final class ResearchQualityTests: XCTestCase {
    private func venue() -> OpenVenue {
        .init(id: "osm-node-1", name: "Contoh Library", aliases: ["Contoh Library"], address: "Jalan Cipete 12",
              branch: "Cipete Selatan", latitude: -6.27, longitude: 106.8, categories: ["library"], sourceIDs: [],
              sourceURLs: [], operatorHosts: ["example.org"])
    }
    func testStructuredHoursRequireTheCorrectBranchAndIgnoreDescriptionIdentity() throws {
        let raw = #"{"@type":"Library","name":"Contoh Library","address":{"streetAddress":"Jalan Cipete 12","addressLocality":"Cipete Selatan"},"openingHours":"Mo-Fr 09:00-17:00"}"#
        let page = SourcePage(url: URL(string: "https://example.org/cipete")!, text: "", fetchedAt: Date(),
                              blocks: [.init(kind: "jsonld", text: raw)])
        let fact = try XCTUnwrap(StructuredVenueEvidence.hours(in: page, venue: venue()))
        XCTAssertEqual(fact.hours?.map(\.weekday), [2, 3, 4, 5, 6])
        XCTAssertEqual(fact.quote, raw)
        let other = raw.replacingOccurrences(of: "Cipete", with: "Kemang")
        let wrong = SourcePage(url: page.url, text: "", fetchedAt: Date(),
                               blocks: [.init(kind: "jsonld", text: other.dropLast() + #", "description":"Cipete Selatan Jalan Cipete 12"}"#)])
        XCTAssertNil(StructuredVenueEvidence.hours(in: wrong, venue: venue()))
    }
    func testStructuredHolidayAndAmbiguousSchedulesAreWithheld() {
        XCTAssertNil(StructuredVenueEvidence.parseHours(["openingHoursSpecification": [
            "dayOfWeek": "Monday", "opens": "09:00", "closes": "17:00", "validThrough": "2020-01-01"]]))
        XCTAssertNil(StructuredVenueEvidence.parseHours(["openingHours": "Mo-Su 00:00-00:00"]))
        XCTAssertNil(StructuredVenueEvidence.parseHours(["openingHours": "Mo-Fr 25:00-26:00"]))
        XCTAssertNil(StructuredVenueEvidence.parseHours(["openingHours": "Mo-Fr 09:00-17:00", "specialOpeningHoursSpecification": []]))
    }
    func testStructuredOvernightSpecificationAndOverlaps() throws {
        let rows = try XCTUnwrap(StructuredVenueEvidence.parseHours(["openingHoursSpecification": [
            "dayOfWeek": ["https://schema.org/Saturday"], "opens": "20:00", "closes": "02:00"]]))
        XCTAssertEqual(rows.first?.weekday, 7)
        XCTAssertEqual(rows.first?.endMinute, 1560)
        XCTAssertNil(StructuredVenueEvidence.parseHours(["openingHours": ["Mo 09:00-17:00", "Mo 12:00-19:00"]]))
    }
    func testCrossBranchFactsCannotBeAssembledAcrossCards() {
        let text = "Contoh Library Cipete Selatan\n[Bagian terpisah]\nContoh Library Kemang\nTerbuka untuk umum setiap hari."
        let page = SourcePage(url: URL(string: "https://example.org/stores")!, text: text, fetchedAt: Date())
        let claim = GiovancExtractor.Claim(field: .access, status: "supported", value: "Terbuka untuk umum", page: 1,
                                           quote: "Terbuka untuk umum setiap hari.", branchQuote: "Contoh Library Cipete Selatan")
        let result = VenueEnrichment.assess(claim, venue: venue(), pages: [page], now: Date())
        XCTAssertNil(result.fact)
        XCTAssertEqual(result.reason, "quote_not_in_same_source_block")
    }
    func testRejectedClaimsHaveSpecificReasons() {
        let page = SourcePage(url: URL(string: "https://example.org/stores")!,
                              text: "Contoh Library Cipete Selatan\nSenin 09.00-17.00", fetchedAt: Date())
        let claim = GiovancExtractor.Claim(field: .hours, status: "supported", value: "Setiap hari 9-17", page: 1,
                                           quote: "Senin 09.00-17.00", branchQuote: "Contoh Library Cipete Selatan",
                                           hours: (1 ... 7).map { .init(weekday: $0, startMinute: 540, endMinute: 1020, closed: false) })
        XCTAssertEqual(VenueEnrichment.assess(claim, venue: venue(), pages: [page], now: Date()).reason,
                       "hours_not_bound_to_cited_days_and_times")
    }
    @MainActor func testLegacyCacheDecodesWithoutDiagnosticsAndPreservesFacts() throws {
        struct LegacyState: Encodable {
            var facts: [String: [VenueField: VenueFact]]
            var pages: [String: SourcePage] = [:]
            var lastFailure: [String: Date] = [:]
            var reservedCredits = 0
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let checked = Date(timeIntervalSince1970: 1_700_000_000)
        let old = LegacyState(facts: [venue().id: Dictionary(uniqueKeysWithValues: VenueField.allCases.map {
            ($0, VenueFact.unknown($0, at: checked))
        })])
        try ContextJSON.encoder().encode(old).write(to: dir.appendingPathComponent("venue-evidence-v1.json"))
        let service = try VenueEnrichment(directory: dir, environment: [:])
        XCTAssertTrue(service.diagnostics().isEmpty)
        XCTAssertEqual(service.facts(for: venue().id, now: checked.addingTimeInterval(29 * 86400)).count, 3)
        XCTAssertTrue(service.facts(for: venue().id, now: checked.addingTimeInterval(30 * 86400)).isEmpty)
    }
}

extension ResearchQualityTests {
    func testAMPMHoursWithoutMinutesRemainBoundToTheirQuotedRange() {
        let rows = (1 ... 7).map { VenueHours(weekday: $0, startMinute: 420, endMinute: 1260, closed: false) }
        XCTAssertTrue(VenueHours.supported(rows, quote: "open daily from 7am - 9pm"))
        XCTAssertFalse(VenueHours.supported(rows, quote: "open daily from 7am - 8pm"))
        XCTAssertFalse(VenueHours.supported(rows, quote: "daily 7 - 9"))
    }
    func testBrandedDomainStillRequiresStreetAndNumber() {
        let v = OpenVenue(id: "osm-node-1", name: "One Fifteenth Coffee Kemang", aliases: [], address: "Kemang Raya 37",
                          branch: "Kemang Raya 37", latitude: -6.2, longitude: 106.8, categories: [], sourceIDs: [], sourceURLs: [],
                          operatorHosts: ["onefifteenthcoffee.squarespace.com"])
        let source = URL(string: "https://onefifteenthcoffee.squarespace.com/location")!
        XCTAssertTrue(StructuredVenueEvidence.identityMatches("Kemang Jl. Kemang Raya No.37", venue: v, source: source))
        XCTAssertFalse(StructuredVenueEvidence.identityMatches("Kemang Jl. Kemang Raya No.99", venue: v, source: source))
        XCTAssertFalse(StructuredVenueEvidence.identityMatches("Kemang Jl. Kemang Raya No.37", venue: v, source: URL(string: "https://unrelated.example")))
    }
    func testDedicatedArticleScopeCanBindDistantEvidenceButOtherArticleCannot() {
        let text = "Contoh Library Cipete Selatan\n" + String(repeating: "Informasi koleksi. ", count: 60) + "\nPengunjung dapat membaca koleksi di ruang baca."
        let claim = GiovancExtractor.Claim(field: .activity, status: "supported", value: "Membaca koleksi", page: 1,
                                           quote: "Pengunjung dapat membaca koleksi di ruang baca.", branchQuote: "Contoh Library Cipete Selatan")
        let page = SourcePage(url: URL(string: "https://example.org/cipete")!, text: text, fetchedAt: Date(),
                              blocks: [.init(kind: "article", text: text, title: "Contoh Library Cipete Selatan")])
        XCTAssertNotNil(VenueEnrichment.assess(claim, venue: venue(), pages: [page], now: Date()).fact)
        let other = SourcePage(url: page.url, text: text, fetchedAt: Date(),
                               blocks: [.init(kind: "article", text: "Daftar berbagai perpustakaan\n" + text, title: "Daftar berbagai perpustakaan")])
        XCTAssertEqual(VenueEnrichment.assess(claim, venue: venue(), pages: [other], now: Date()).reason, "fact_too_far_from_branch")
    }
}

extension ResearchQualityTests {
    @MainActor func testRateLimitedSourceIsNotFetchedAgainForAnotherBranch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("collector.cjs")
        try #"""
        const fs = require('node:fs');
        const input = JSON.parse(fs.readFileSync(0, 'utf8'));
        const blocked = input.blockedHosts.includes('example.org');
        process.stdout.write(JSON.stringify({pages: [], discoveredURLs: [], attempts: [{
          url: input.urls[0], attempt: blocked ? 0 : 1, status: blocked ? 0 : 429,
          reason: blocked ? 'host_cooldown' : 'http_429', durationSeconds: 0
        }]}));
        """#.write(to: script, atomically: true, encoding: .utf8)
        var environment = ProcessInfo.processInfo.environment
        environment["VENUE_ENRICHMENT_ENABLED"] = "1"
        environment["VENUE_WEB_PROVIDER"] = "playwright"
        environment["GIOVANC_API_KEY"] = "test-only-no-model-request"
        environment["VENUE_PLAYWRIGHT_SCRIPT"] = script.path
        do {
            let service = try VenueEnrichment(directory: dir, environment: environment)
            var second = venue()
            second.id = "osm-node-2"
            second.branch = "Kemang"
            XCTAssertTrue(service.enqueue(venue()))
            XCTAssertTrue(service.enqueue(second))
            for _ in 0 ..< 200 {
                if service.status()["pending"] == "0" { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            await service.shutdown()
            let reports = service.diagnostics()
            XCTAssertEqual(reports.count, 2)
            XCTAssertEqual(reports.first?.pageAttempts.first?.reason, "http_429")
            XCTAssertEqual(reports.last?.pageAttempts.first?.reason, "host_cooldown")
            XCTAssertTrue(service.facts(for: venue().id).isEmpty)
            XCTAssertFalse(service.enqueue(venue())) // Technical retry backoff, not a 30-day unknown.
            XCTAssertEqual(service.status()["freshUnknownFacts"], "0")
        }
        let restarted = try VenueEnrichment(directory: dir, environment: environment)
        var third = venue()
        third.id = "osm-node-3"
        XCTAssertTrue(restarted.enqueue(third))
        for _ in 0 ..< 200 {
            if restarted.status()["pending"] == "0" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await restarted.shutdown()
        XCTAssertEqual(restarted.diagnostics().first(where: { $0.venueID == third.id })?.pageAttempts.first?.reason, "host_cooldown")

    }
}

extension ResearchQualityTests {
    func testCapturedPublicJSONResponseKeepsItsOwnEvidenceURL() {
        let text = "Contoh Library Cipete Selatan: Pengunjung dapat membaca koleksi di ruang baca."
        let url = URL(string: "https://example.org/api/branches/cipete")!
        let page = SourcePage(url: URL(string: "https://example.org/stores")!, text: text, fetchedAt: Date(),
                              blocks: [.init(kind: "network", text: text, sourceURL: url)])
        let claim = GiovancExtractor.Claim(field: .activity, status: "supported", value: "Membaca koleksi", page: 1,
                                           quote: "Pengunjung dapat membaca koleksi di ruang baca.", branchQuote: "Contoh Library Cipete Selatan")
        XCTAssertEqual(VenueEnrichment.assess(claim, venue: venue(), pages: [page], now: Date()).fact?.source, url)
    }
}
