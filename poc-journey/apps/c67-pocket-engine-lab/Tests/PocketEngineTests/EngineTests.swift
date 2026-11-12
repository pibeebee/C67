import XCTest
@testable import PocketEngine

final class EngineTests: XCTestCase {
    func testRecommendationsRequireThreeRelevantEligiblePlaces() throws {
        let catalog = try Catalog.bundled().validated()
        var profile = Profile()
        profile.categories = ["test-category"]
        let pool = catalog.venues.prefix(4).enumerated().map { index, source in
            var venue = source
            venue.categories = index < 3 ? ["test-category"] : ["other-category"]
            return Recommender.assess(venue, profile: profile)
        }
        XCTAssertTrue(Recommender.recommendations(from: Array(pool.prefix(2)), profile: profile).isEmpty)
        XCTAssertEqual(Recommender.recommendations(from: pool, profile: profile).map(\.id), pool.prefix(3).map(\.id))
    }

    func testLegacyStopChoiceDecodesWithFlexibleVisitTime() throws {
        let data = Data(#"{"venueID":"legacy","required":true,"durationMinutes":60}"#.utf8)
        let choice = try Codec.decoder().decode(StopChoice.self, from: data)
        XCTAssertNil(choice.timing)
        XCTAssertEqual(choice.venueID, "legacy")
    }

    func testThrottledETAStopsTheSearchWithoutRetry() async throws {
        let venues = Array(try Catalog.bundled().validated().venues.prefix(3))
        let start = TripClock.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date().addingTimeInterval(86400))!
        let day = TripClock.day(start)
        let choices = venues.map { StopChoice(venueID: $0.id,
                                              override: .init(day: day, opens: 540, closes: 1020, publicAccessConfirmed: true)) }
        let input = TripInput(departure: start, deadline: start.addingTimeInterval(8 * 3600),
                              origin: venues[0].coordinate, returnToOrigin: true, maxWaitMinutes: 30, avoidRain: false)
        let requests = RequestCounter()
        do {
            _ = try await ItineraryPlanner.make(input: input, choices: choices, venues: venues, profile: Profile(),
                                                travel: { _, _, _ in
                                                    await requests.increment()
                                                    throw TravelQuoteError.throttled
                                                }, weather: { _, _, _ in .init(maxRainChance: nil, summary: "") })
            XCTFail("A throttled ETA cannot yield a valid plan")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("membatasi permintaan ETA"))
        }
        let count = await requests.count
        XCTAssertEqual(count, 1)
    }

    func testCatalogAndRequirements() throws {
        let catalog = try Catalog.bundled().validated()
        XCTAssertEqual(catalog.venues.count, 30)
        let venue = try XCTUnwrap(catalog.venues.first)
        var profile = Profile()
        profile.preferences[.reading] = .required
        XCTAssertFalse(Recommender.assess(venue, profile: profile).eligible)
        profile.preferences[.reading] = .avoided
        let result = Recommender.assess(venue, profile: profile)
        XCTAssertTrue(result.eligible)
        XCTAssertTrue(result.unknowns.contains(Facet.reading.title))
    }
    func testStaleEvidenceBecomesUnknown() throws {
        var venue = try XCTUnwrap(Catalog.bundled().venues.first)
        let now = Date()
        venue.facts = [Fact(field: .reading, status: .supported, value: "yes", sourceURL: "https://example.com", quote: "quoted text", checkedAt: now.addingTimeInterval(-31 * 86400), expiresAt: now.addingTimeInterval(86400))]
        XCTAssertEqual(venue.status(.reading, at: now), .unknown)
    }
    func testPlannerSchedulesManualAccessAndReturn() async throws {
        let venue = try XCTUnwrap(Catalog.bundled().venues.first)
        let start = TripClock.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date().addingTimeInterval(86400))!
        let input = TripInput(departure: start, deadline: start.addingTimeInterval(8 * 3600), origin: venue.coordinate, returnToOrigin: true, maxWaitMinutes: 30, avoidRain: false)
        let choice = StopChoice(venueID: venue.id, required: true, durationMinutes: 60, override: .init(day: TripClock.day(start), opens: 9 * 60, closes: 17 * 60, publicAccessConfirmed: true))
        let plan = try await ItineraryPlanner.make(input: input, choices: [choice], venues: [venue], profile: Profile(), travel: { _, _, _ in LegQuote(seconds: 600, meters: 1000) }, weather: { _, _, _ in WeatherReading(maxRainChance: 0, summary: "synthetic") })
        XCTAssertEqual(plan.stops.count, 1)
        XCTAssertEqual(plan.finish.timeIntervalSince(start), 4800, accuracy: 0.1)
        XCTAssertEqual(plan.returnSeconds, 600)
    }
    func testPlannerRejectsUnknownAccess() async throws {
        let venue = try XCTUnwrap(Catalog.bundled().venues.first)
        let start = TripClock.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date().addingTimeInterval(86400))!
        let input = TripInput(departure: start, deadline: start.addingTimeInterval(3600), origin: venue.coordinate, returnToOrigin: false, maxWaitMinutes: 0, avoidRain: false)
        do {
            _ = try await ItineraryPlanner.make(input: input, choices: [.init(venueID: venue.id)], venues: [venue], profile: Profile(), travel: { _, _, _ in LegQuote(seconds: 0, meters: 0) }, weather: { _, _, _ in WeatherReading(maxRainChance: 0, summary: "") })
            XCTFail("Unknown access must not be scheduled")
        } catch { XCTAssertTrue(error.localizedDescription.contains("akses")) }
    }
    func testMatchingFindsDifferentRepresentativesAndRejectsUnrelatedPositiveFacet() throws {
        let source = try XCTUnwrap(Catalog.bundled().venues.first)
        func venue(_ id: String, _ categories: [String]) -> Venue {
            var copy = source; copy.id = id; copy.categories = categories; return copy
        }
        var profile = Profile(); profile.categories = ["art", "garden", "animal"]
        let venues = [venue("a", ["art_gallery", "park"]), venue("b", ["art_gallery"]),
                      venue("c", ["animal"]), venue("d", ["art_gallery"])]
        let result = Recommender.recommendations(from: venues.map { Recommender.assess($0, profile: profile) }, profile: profile)
        XCTAssertEqual(Set(result.prefix(3).map(\.id)), ["a", "b", "c"])
        var unrelated = venue("e", ["library"])
        unrelated.facts = [Fact(field: .coffee, status: .supported, value: "coffee", sourceURL: "https://example.com", quote: "Coffee service", checkedAt: Date().addingTimeInterval(-10), expiresAt: Date().addingTimeInterval(86400))]
        profile.preferences[.coffee] = .liked
        XCTAssertTrue(Recommender.eligibleMatches(from: [Recommender.assess(unrelated, profile: profile)], profile: profile).isEmpty)
    }

    func testIndependentAndSessionDuplicatesOnlyCountOnce() throws {
        var source = try XCTUnwrap(Catalog.bundled().venues.first)
        source.id = "osm-node-new"; source.categories = ["restaurant"]
        var duplicate = source; duplicate.id = "overture-new"; duplicate.categories = ["japanese_cuisine"]
        var apple = source; apple.id = "apple-session-new"
        let merged = CandidatePool.merge(independent: [source, duplicate], session: [apple])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(Interests.matches("japanese_cuisine", categories: merged[0].categories))
    }

    func testAdministrativeAreaContainsInteriorAndExcludesOutside() throws {
        let area = try VisitArea.jakartaSelatan()
        XCTAssertTrue(area.contains(.init(latitude: -6.2615, longitude: 106.8106)))
        let outside = Coordinate(latitude: -6.1754, longitude: 106.8272)
        XCTAssertFalse(area.contains(outside))
        XCTAssertFalse(area.permits(outside, extensionMeters: 0))
    }

    func testDinnerNotBeforeAndShorterPlanPreserveMandatoryStopAndReturn() async throws {
        var places = Array(try Catalog.bundled().venues.prefix(3))
        for index in places.indices { places[index].id = "stop-\(index)" }
        let start = TripClock.calendar.date(bySettingHour: 17, minute: 0, second: 0, of: Date().addingTimeInterval(86400))!
        let end = TripClock.calendar.date(bySettingHour: 19, minute: 0, second: 0, of: start)!
        let choices = places.enumerated().map { index, venue in
            StopChoice(venueID: venue.id, required: index == 2, durationMinutes: index == 2 ? 45 : 30,
                       override: .init(day: TripClock.day(start), opens: 480, closes: 1140, publicAccessConfirmed: true),
                       timing: index == 2 ? .notBefore(1080) : nil)
        }
        let input = TripInput(departure: start, deadline: end, origin: places[0].coordinate,
                              returnToOrigin: true, maxWaitMinutes: 30, avoidRain: false, lastVenueID: "stop-2", maximumStops: 2)
        let plan = try await ItineraryPlanner.make(input: input, choices: choices, venues: places, profile: Profile(),
                                                   travel: { _, _, _ in .init(seconds: 600, meters: 1000) }, weather: { _, _, _ in .init(maxRainChance: nil, summary: "fixture") })
        XCTAssertEqual(plan.stops.count, 2)
        XCTAssertEqual(plan.stops.last?.venueID, "stop-2")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(plan.stops.last).visitStart, TripClock.calendar.date(bySettingHour: 18, minute: 0, second: 0, of: start)!)
        XCTAssertLessThanOrEqual(plan.finish, end)
        XCTAssertEqual(plan.returnSeconds, 600)
    }

    func testRestoredLabelOptionsAndReviewedCategory() throws {
        XCTAssertEqual(Interests.all.count, 53)
        XCTAssertEqual(Facet.activityOptions.count, 20)
        XCTAssertEqual(Facet.allCases.count, 69)
        var venue = try XCTUnwrap(Catalog.bundled().venues.first)
        venue.categories = ["museum"]
        var profile = Profile()
        profile.categories = ["art_museum"]
        profile.preferences[.rooftop] = .required
        let checked = Date().addingTimeInterval(-60)
        let expires = checked.addingTimeInterval(3600)
        func fact(_ field: Facet, _ status: FactStatus) -> Fact {
            Fact(field: field, status: status, value: "fixture", sourceURL: "https://example.com",
                 quote: "Fixture quotation", checkedAt: checked, expiresAt: expires)
        }
        XCTAssertFalse(Recommender.assess(venue, profile: profile).eligible)
        venue.facts = [fact(.art_museum, .supported), fact(.rooftop, .supported)]
        let result = Recommender.assess(venue, profile: profile)
        XCTAssertEqual(Recommender.eligibleMatches(from: [result], profile: profile).count, 1)
        venue.facts.append(fact(.art_museum, .contradicted))
        XCTAssertTrue(Recommender.eligibleMatches(from: [Recommender.assess(venue, profile: profile)], profile: profile).isEmpty)
        XCTAssertFalse(Recommender.assess(venue, profile: profile, now: expires).eligible)
    }

}

private actor RequestCounter {
    var count = 0
    func increment() { count += 1 }
}
