import Foundation
import XCTest
@testable import PlaceContextEngine

@MainActor final class PlaceContextTests: XCTestCase {
    let now = PlaceContextDemo.now
    func snapshot(_ change: ([String: Any]) -> [String: Any] = { $0 }) throws -> PlaceSnapshot {
        let object = try JSONSerialization.jsonObject(with: PlaceContextDemo.fixture(id: "synthetic-park")) as! [String: Any]
        let data = try JSONSerialization.data(withJSONObject: change(object))
        return .init(place: try JSONDecoder().decode(GooglePlace.self, from: data), fetchedAt: now, fieldMask: "SYNTHETIC", source: "SYNTHETIC")
    }
    func request() -> VisitContextRequest {
        var r = VisitContextRequest(placeID: "synthetic-park", day: PlaceContextDemo.day); r.identityConfirmed = true; return r
    }
    func testFullStayAndLunchBreakArePreserved() throws {
        let s = try snapshot { d in var d = d; d["regularOpeningHours"] = ["periods": [["open": ["day": 1, "hour": 9], "close": ["day": 1, "hour": 12]], ["open": ["day": 1, "hour": 14], "close": ["day": 1, "hour": 17]]]]; return d }
        var r = request(); r.durationMinutes = 90
        let v = try VisitContextEngine.evaluate(snapshot: s, request: r, now: now)
        XCTAssertFalse(v.options.isEmpty)
        for option in v.options {
            let minutes = option.start.timeIntervalSince(ContextClock.day(r.day)!) / 60
            XCTAssertTrue(minutes <= 630 || minutes >= 840)
            XCTAssertEqual(option.end.timeIntervalSince(option.start), 5400)
        }
    }
    func testCurrentDatedClosureOverridesRegularHours() throws {
        let s = try snapshot { d in var d = d; d["currentOpeningHours"] = ["periods": []]; return d }
        XCTAssertEqual(try VisitContextEngine.evaluate(snapshot: s, request: request(), now: now).status, "closed")
    }
    func testDatedExceptionDoesNotRepeatWeekly() throws {
        let s = try snapshot { d in var d = d; d["currentOpeningHours"] = ["periods": [["open": ["date": ["year": 2026, "month": 11, "day": 9], "hour": 13], "close": ["date": ["year": 2026, "month": 11, "day": 9], "hour": 15]]]]; return d }
        let v = try VisitContextEngine.evaluate(snapshot: s, request: request(), now: now)
        XCTAssertEqual(v.options.first?.start, ContextClock.day("2026-11-09")!.addingTimeInterval(13 * 3600))
        var r = request(); r.day = "2026-11-10"
        XCTAssertEqual(try VisitContextEngine.evaluate(snapshot: s, request: r, now: now).status, "closed")
    }
    func testOvernightFridayIntoSaturdayAndWeeklyBoundary() throws {
        let s = try snapshot { d in var d = d; d["regularOpeningHours"] = ["periods": [["open": ["day": 5, "hour": 22], "close": ["day": 6, "hour": 2]]]]; return d }
        let hours = GoogleHoursResolver.resolve(s, day: "2026-11-07", allowRegular: true, now: now)
        XCTAssertEqual(hours.intervals.count, 1); XCTAssertEqual(hours.intervals[0].start, ContextClock.day("2026-11-07"))
        XCTAssertEqual(hours.intervals[0].end.timeIntervalSince(hours.intervals[0].start), 7200)
    }
    func testAlwaysOpenOnlyRecognizedFromCanonicalFormat() throws {
        let s = try snapshot { d in var d = d; d["regularOpeningHours"] = ["periods": [["open": ["day": 0, "hour": 0, "minute": 0]]]]; return d }
        XCTAssertEqual(GoogleHoursResolver.resolve(s, day: PlaceContextDemo.day, allowRegular: true, now: now).intervals[0].end.timeIntervalSince(ContextClock.day(PlaceContextDemo.day)!), 86400)
        let malformed = try snapshot { d in var d = d; d["regularOpeningHours"] = ["periods": [["open": ["day": 1, "hour": 9]]]]; return d }
        XCTAssertEqual(try VisitContextEngine.evaluate(snapshot: malformed, request: request(), now: now).status, "needs_hours")
    }
    func testOpenNowAndWeekdayTextDoNotInventSchedule() throws {
        let s = try snapshot { d in var d = d; d["regularOpeningHours"] = ["openNow": true, "weekdayDescriptions": ["Monday: 08:00–18:00"]]; return d }
        XCTAssertEqual(try VisitContextEngine.evaluate(snapshot: s, request: request(), now: now).status, "needs_hours")
    }
    func testMissingTimezoneAndStaleSnapshotBlockOptions() throws {
        var s = try snapshot { d in var d = d; d.removeValue(forKey: "timeZone"); d.removeValue(forKey: "utcOffsetMinutes"); return d }
        XCTAssertEqual(try VisitContextEngine.evaluate(snapshot: s, request: request(), now: now).status, "needs_hours")
        s = try snapshot(); s.expiresAt = now.addingTimeInterval(-1)
        XCTAssertEqual(try VisitContextEngine.evaluate(snapshot: s, request: request(), now: now).status, "needs_hours")
    }
    func testPermanentClosureAndIdentityMismatch() throws {
        let s = try snapshot { d in var d = d; d["businessStatus"] = "CLOSED_PERMANENTLY"; return d }
        XCTAssertEqual(try VisitContextEngine.evaluate(snapshot: s, request: request(), now: now).status, "closed")
        var r = request(); r.placeID = "another-place"
        XCTAssertThrowsError(try VisitContextEngine.evaluate(snapshot: s, request: r, now: now))
    }
    func testRequiredTimeDoesNotExtendOpeningHours() throws {
        var r = request(); r.preferredTime = .init(earliest: 18 * 60, latest: 19 * 60, required: true)
        XCTAssertEqual(try VisitContextEngine.evaluate(snapshot: snapshot(), request: r, now: now).status, "no_feasible_visit_window")
    }
    func testUnknownExposureIsNotInferredFromOutdoorSeating() throws {
        let s = try snapshot { d in var d = d; d["outdoorSeating"] = true; return d }
        var r = request(); r.avoidRain = true
        let result = try VisitContextEngine.evaluate(snapshot: s, request: r, now: now)
        XCTAssertEqual(result.status, "options_with_unknowns"); XCTAssertTrue(result.options.allSatisfy { $0.assessments.first?.penalty == nil })
        r.exposure = .outdoor
        XCTAssertThrowsError(try VisitContextEngine.evaluate(snapshot: s, request: r, now: now))
    }
    func testPartialWeatherNeverMeansZeroRain() throws {
        var r = request(); r.avoidRain = true; r.exposure = .outdoor; r.exposureEvidence = "SYNTHETIC observation"; r.durationMinutes = 90
        let start = ContextClock.day(r.day)!.addingTimeInterval(8 * 3600)
        let weather = VisitWeatherContext(source: "SYNTHETIC", fetchedAt: now, expiresAt: now.addingTimeInterval(900), hours: [.init(start: start, rainProbability: 0.2, temperatureC: 28)])
        let result = try VisitContextEngine.evaluate(snapshot: snapshot(), request: r, weather: weather, now: now)
        XCTAssertTrue(result.options.allSatisfy { $0.assessments.first?.penalty == nil })
    }
    func testReviewNegationAndNoTimestampInference() throws {
        let s = try snapshot { d in var d = d; d["reviews"] = [
            ["name": "r1", "originalText": ["text": "Pagi tidak ramai.", "languageCode": "id"], "publishTime": "2026-11-01T00:00:00Z"],
            ["name": "r2", "originalText": ["text": "Bagus sekali.", "languageCode": "id"], "rating": 5, "publishTime": "2026-11-01T01:00:00Z"],
            ["name": "r3", "originalText": ["text": "Mungkin pagi sepi.", "languageCode": "id"], "publishTime": "2026-11-01T00:00:00Z"]]; return d }
        let hints = ReviewTimeExtractor.extract(s.place.reviews!, now: now)
        XCTAssertEqual(hints.count, 1); XCTAssertEqual(hints[0].aspect, "quiet"); XCTAssertEqual(hints[0].reviewID, "r1")
        let result = try VisitContextEngine.evaluate(snapshot: s, request: request(), now: now)
        XCTAssertEqual(result.reviewAttributions.count, 3)
        XCTAssertEqual(result.reviewAttributions[0].originalText?.text, "Pagi tidak ramai.")
        XCTAssertEqual(result.googleMapsURI, s.place.googleMapsUri)
    }
    func testConflictingReviewsAndWrongDayRemainUnknown() throws {
        let s = try snapshot { d in var d = d; d["reviews"] = [
            ["name": "r1", "originalText": ["text": "Hari kerja pagi sepi.", "languageCode": "id"], "publishTime": "2026-11-01T00:00:00Z"],
            ["name": "r2", "originalText": ["text": "Hari kerja pagi ramai.", "languageCode": "id"], "publishTime": "2026-11-01T00:00:00Z"]]; return d }
        var r = request(); r.seeksQuiet = true
        let result = try VisitContextEngine.evaluate(snapshot: s, request: r, now: now)
        XCTAssertTrue(result.options.allSatisfy { $0.assessments.first?.penalty == nil })
        r.day = "2026-11-08"
        XCTAssertTrue(try VisitContextEngine.evaluate(snapshot: s, request: r, now: now).options.allSatisfy { $0.assessments.first?.penalty == nil })
    }
    func testHumanPreferencesChangeOrderInSyntheticEndToEndPipeline() async throws {
        let output = try await PlaceContextDemo.run()
        XCTAssertEqual(output.simulatedHTTPCalls, 3)
        XCTAssertEqual(output.quietReader.visits.map(\.placeID), ["synthetic-park", "synthetic-museum"])
        XCTAssertEqual(output.afternoonPhotographer.visits.map(\.placeID), ["synthetic-museum", "synthetic-park"])
        XCTAssertEqual(output.rainAvoider.visits.map(\.placeID), ["synthetic-museum", "synthetic-park"])
        for result in [output.quietReader, output.afternoonPhotographer, output.rainAvoider] {
            XCTAssertEqual(result.visits.count, 2); XCTAssertEqual(result.legs.count, 3)
            XCTAssertTrue(result.legs.allSatisfy { $0.evidence.seconds == 900 && $0.departure == $0.evidence.departure })
            XCTAssertTrue(result.visits.allSatisfy { $0.visit.start >= $0.arrival && $0.visit.end.timeIntervalSince($0.visit.start) == 3600 })
            XCTAssertEqual(result.legs.last?.to, "origin")
            XCTAssertEqual(result.elapsedSeconds!, result.travelSeconds + result.waitingSeconds + result.dwellSeconds, accuracy: 0.001)
        }
        XCTAssertEqual(output.rainAvoider.status, "candidate_with_unknown_preferences")
        XCTAssertGreaterThan(output.rainAvoider.waitingSeconds, 0)
    }
    struct NoTravel: ContextTravelProvider {
        func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? { nil }
    }
    func testMissingTravelNeverFabricatesACompletePlan() async throws {
        let s = try snapshot(); let midnight = ContextClock.day(PlaceContextDemo.day)!
        let input = ContextPlanRequest(originID: "origin", returnID: "origin", departure: midnight.addingTimeInterval(9 * 3600), deadline: midnight.addingTimeInterval(18 * 3600), stops: [.init(snapshot: s, request: request())])
        let result = try await ContextItineraryPlanner.plan(input, provider: NoTravel(), now: now)
        XCTAssertEqual(result.status, "incomplete_travel_data"); XCTAssertNil(result.finish); XCTAssertTrue(result.visits.isEmpty)
    }
    func testBudgetCutoffIsNotInfeasibilityProof() async throws {
        let midnight = ContextClock.day(PlaceContextDemo.day)!
        var input = ContextPlanRequest(originID: "origin", returnID: "origin", departure: midnight.addingTimeInterval(9 * 3600), deadline: midnight.addingTimeInterval(18 * 3600), stops: [.init(snapshot: try snapshot(), request: request())]); input.maxTravelCalls = 1
        let result = try await ContextItineraryPlanner.plan(input, provider: PlaceContextDemo.FixedTravel(), now: now)
        // The planner now rejects an insufficient minimum tour budget before a paid call.
        XCTAssertEqual(result.travelCalls, 0); XCTAssertTrue(result.searchTruncated); XCTAssertNil(result.finish)
    }
    final class HTTP: PlacesHTTPTransport {
        var requests: [URLRequest] = []; var status = 200; var data = PlaceContextDemo.fixture(id: "synthetic-park"); var fail = false
        func send(_ request: URLRequest) async throws -> PlacesHTTPResponse {
            requests.append(request)
            if fail { throw NSError(domain: "sensitive-do-not-emit", code: 99) }
            return .init(status: status, data: data)
        }
    }
    func testExplicitFieldMasksAndHeaderOnlyKey() async throws {
        let http = HTTP(); let c = GooglePlacesClient(configuration: try .init(apiKey: "fake-sensitive"), transport: http)
        let basic = try await c.details("synthetic-park", now: now)
        XCTAssertNil(basic.place.reviews)
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Api-Key"), "fake-sensitive")
        XCTAssertFalse(request.url!.absoluteString.contains("fake-sensitive")); XCTAssertFalse(GooglePlacesClient.hoursMask.contains("reviews"))
        _ = try await c.details("synthetic-park", includeReviews: true, now: now)
        XCTAssertEqual(http.requests[1].value(forHTTPHeaderField: "X-Goog-FieldMask"), GooglePlacesClient.experienceMask)
    }
    func testUnconfirmedIdentityRejectedBeforePaidRequest() async throws {
        let http = HTTP(); let c = GooglePlacesClient(configuration: try .init(apiKey: "fake"), transport: http)
        var r = request(); r.identityConfirmed = false
        do { _ = try await GoogleContextService.evaluate(.init(request: r), client: c, now: now); XCTFail("Should reject") } catch {}
        XCTAssertEqual(c.requests, 0)
    }
    func testQuotaAndAuthorizationErrorsAreNotRetriedOrLeaked() async throws {
        for status in [401, 403, 429, 500] {
            let http = HTTP(); http.status = status; http.data = Data("sensitive-do-not-emit".utf8)
            let c = GooglePlacesClient(configuration: try .init(apiKey: "fake-sensitive"), transport: http)
            do { _ = try await c.details("synthetic-park"); XCTFail("Expected error") }
            catch { XCTAssertFalse(error.localizedDescription.contains("fake-sensitive")); XCTAssertFalse(error.localizedDescription.contains("sensitive-do-not-emit")) }
            XCTAssertEqual(c.requests, 1); XCTAssertEqual(http.requests.count, 1)
        }
    }
    func testBudgetAndInvalidIDsDoNotMakeMoreRequests() async throws {
        let http = HTTP(); let c = GooglePlacesClient(configuration: try .init(apiKey: "fake", maxRequests: 1), transport: http)
        do { _ = try await c.details("../bad"); XCTFail("Invalid path") } catch {}
        XCTAssertEqual(c.requests, 0)
        _ = try await c.details("synthetic-park")
        do { _ = try await c.details("synthetic-park"); XCTFail("Budget") } catch { XCTAssertTrue(error is ContextError) }
        XCTAssertEqual(http.requests.count, 1)
    }
    func testMismatchAndMalformedResponseAreRejected() async throws {
        let http = HTTP(); let c = GooglePlacesClient(configuration: try .init(apiKey: "fake"), transport: http)
        do { _ = try await c.details("different-place"); XCTFail("Mismatched identity") } catch {}
        http.data = Data("{}".utf8)
        do { _ = try await c.details("synthetic-park"); XCTFail("Incomplete response") } catch {}
    }
    func testSmallJSONRequestHasSafeDefaults() throws {
        let data = Data("{\"request\":{\"placeID\":\"synthetic-park\",\"day\":\"2026-11-09\"}}".utf8)
        let input = try ContextJSON.decoder().decode(GoogleContextEvaluationInput.self, from: data)
        XCTAssertFalse(input.includeReviews); XCTAssertFalse(input.request.identityConfirmed)
        XCTAssertEqual(input.request.durationMinutes, 60); XCTAssertEqual(input.request.exposure, .unknown)
        XCTAssertNil(ContextClock.day("2026-1-009")); XCTAssertNil(ContextClock.day("2026-02-30"))
        try input.request.validate()
    }
    func testOverlappingForecastsAndCrossBandVisitsStayUnknown() throws {
        var r = request(); r.avoidRain = true; r.exposure = .outdoor; r.exposureEvidence = "SYNTHETIC"; r.seeksQuiet = true
        r.availableStart = 630; r.availableEnd = 720
        let start = ContextClock.day(r.day)!.addingTimeInterval(10 * 3600)
        let w = VisitWeatherContext(source: "SYNTHETIC", fetchedAt: now, expiresAt: now.addingTimeInterval(900), hours: [
            .init(start: start, rainProbability: 0.1, temperatureC: 28), .init(start: start.addingTimeInterval(1800), rainProbability: 0.2, temperatureC: 29)])
        let v = try VisitContextEngine.evaluate(snapshot: snapshot(), request: r, weather: w, now: now)
        XCTAssertTrue(v.options.allSatisfy { $0.assessments.allSatisfy { $0.penalty == nil } })
    }
    func testSearchKeepsAmbiguityAndUsesBoundedQueryMask() async throws {
        let http = PlaceContextDemo.Transport(); let c = GooglePlacesClient(configuration: try .init(apiKey: "fake"), transport: http)
        let candidates = try await c.search("SYNTHETIC", limit: 2)
        XCTAssertEqual(candidates.count, 2); XCTAssertEqual(c.requests, 1)
    }
    func testCancellationPropagatesWithoutResult() async throws {
        struct Cancelled: PlacesHTTPTransport {
            func send(_ request: URLRequest) async throws -> PlacesHTTPResponse { throw CancellationError() }
        }
        let c = GooglePlacesClient(configuration: try .init(apiKey: "fake"), transport: Cancelled())
        do { _ = try await c.details("synthetic-park"); XCTFail("Cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }
}
