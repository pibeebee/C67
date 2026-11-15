import Foundation
import PreferenceQuality
import Testing
import VisitTiming
@testable import PlannerEngine

// Written for the P3 handoff. DO NOT RUN until the user confirms WeatherKit activation.
@Suite("P3 contracts and sourced time rules")
struct ContractTests {
    let now = TripClock.date("2026-11-05T07:00:00Z")
    @Test func publishedFridayEntryPause() throws {
        let catalog = try IntegrationCatalog.load()
        var request = TripRequest(now: now)
        request.departure = TripClock.date("2026-11-06T04:00:00Z") // 11:00 WIB Friday
        let run = try #require(try catalog.timingRun(candidateID: "cikini", request: request, now: now))
        let next = VisitStartPolicy.earliest(arrival: TripClock.date("2026-11-06T04:30:00Z"),
                                             tripDate: request.departure, ranges: run.validStartRanges)
        #expect(next == TripClock.date("2026-11-06T06:00:00Z")) // Entry resumes 13:00
        #expect(VisitStartPolicy.earliest(arrival: TripClock.date("2026-11-06T04:15:00Z"),
                                          tripDate: request.departure, ranges: run.validStartRanges) == TripClock.date("2026-11-06T04:15:00Z"))
    }
    @Test func publishedGBKSessionGapRequiresFullStay() throws {
        let catalog = try IntegrationCatalog.load()
        let request = TripRequest(now: now)
        let run = try #require(try catalog.timingRun(candidateID: "gbk", request: request, now: now))
        #expect(VisitStartPolicy.earliest(arrival: TripClock.date("2026-11-06T02:45:00Z"),
                                          tripDate: request.departure, ranges: run.validStartRanges) == TripClock.date("2026-11-06T08:00:00Z"))
    }
    @Test func mondayClosuresAndUnknownHoursDoNotTurnIntoOpen() throws {
        let catalog = try IntegrationCatalog.load()
        var request = TripRequest(now: now)
        request.departure = TripClock.date("2026-11-09T02:00:00Z")
        request.deadline = TripClock.date("2026-11-09T12:00:00Z")
        for id in ["gbk", "ragunan", "bdt-rbbj", "erasmus"] {
            let run = try #require(try catalog.timingRun(candidateID: id, request: request, now: now))
            #expect(run.status == "closed_regular")
            #expect(run.validStartRanges.isEmpty)
        }
        #expect(try catalog.timingRun(candidateID: "dialogue", request: request, now: now) == nil)
    }
    @Test func staleFactsAndSuspendedMuseumBlock() throws {
        let catalog = try IntegrationCatalog.load()
        let request = TripRequest(now: now)
        let suspended = try #require(try catalog.timingRun(candidateID: "macan-gallery", request: request, now: now))
        #expect(suspended.validStartRanges.isEmpty)
        let old = try #require(try catalog.timingRun(candidateID: "cikini", request: request,
                                                     now: now.addingTimeInterval(8 * 86400)))
        #expect(old.status == "needs_recheck")
    }
    @Test func wrongDayAndDuplicateAreasRejected() throws {
        let catalog = try IntegrationCatalog.load()
        var request = TripRequest(now: now)
        request.deadline = request.deadline.addingTimeInterval(86400)
        #expect(throws: (any Error).self) { try request.validate(catalog: catalog, now: now) }
        request = TripRequest(now: now)
        request.requiredCandidateIDs = ["bdt-rbbj", "bdt-silent"]
        #expect(throws: (any Error).self) { try request.validate(catalog: catalog, now: now) }
    }
    @Test func limitsAndNegationConflictRejected() throws {
        let catalog = try IntegrationCatalog.load()
        var request = TripRequest(now: now)
        request.desiredCount = 7
        #expect(throws: (any Error).self) { try request.validate(catalog: catalog, now: now) }
        request.desiredCount = 3; request.defaultDuration = 61
        #expect(throws: (any Error).self) { try request.validate(catalog: catalog, now: now) }
        request.defaultDuration = 60; request.profile.must = [.coffee]; request.profile.avoid = [.coffee]
        #expect(throws: (any Error).self) { try request.validate(catalog: catalog, now: now) }
    }
    @Test func WIBDateAndRoundingNeverRoundBackward() {
        let date = TripClock.date("2026-11-05T18:00:00Z")
        #expect(TripClock.day(date) == "2026-11-06")
        let arrival = TripClock.date("2026-11-06T02:00:01Z")
        #expect(VisitStartPolicy.earliest(arrival: arrival, tripDate: date, ranges: [.init(540, 600)])
            == TripClock.date("2026-11-06T02:15:00Z"))
    }
    @Test func supersededOperationCannotPublish() {
        var epoch = OperationEpoch()
        let old = epoch.current
        epoch.invalidate()
        #expect(!epoch.isCurrent(old))
        #expect(epoch.isCurrent(epoch.current))
    }
}

@Suite("P3 location and interval weather")
struct EvidenceTests {
    func pin(_ id: String, _ name: String = "Perpustakaan Jakarta", _ address: String = "Cikini Jakarta",
             lat: Double = -6.19, lon: Double = 106.839) -> PlacePin {
        .init(id: id, name: name, address: address, latitude: lat, longitude: lon)
    }
    @Test func duplicateSearchResultsCollapseAndOutsideJakartaExcluded() {
        let review = PlaceIdentityPolicy.review(id: "cikini", query: "library", words: ["perpustakaan", "jakarta"],
                                                branch: "cikini", results: [pin("1"), pin("2"), pin("3", lat: -6.9, lon: 107.6)])
        #expect(review.candidates.count == 1)
        #expect(review.selected?.id == "1")
    }
    @Test func ambiguousBranchNeedsExplicitSelection() throws {
        let result = PlaceIdentityPolicy.review(id: "cikini", query: "library", words: ["perpustakaan", "jakarta"],
                                                branch: "cikini", results: [pin("1"), pin("2", lat: -6.192)])
        #expect(result.selected == nil)
        var prepared = PreparedTrip(request: .init(), selectedIDs: ["cikini"], locations: [result], searchRequests: 1)
        try prepared.choose("2", for: "cikini")
        #expect(prepared.locations[0].manualConfirmation)
        #expect(throws: (any Error).self) { try prepared.choose("invented-id", for: "cikini") }
    }
    @Test func wrongBranchNotAutomaticallyAccepted() {
        let result = PlaceIdentityPolicy.review(id: "cikini", query: "library", words: ["perpustakaan", "jakarta"],
                                                branch: "cikini", results: [pin("wrong", "Perpustakaan Jakarta", "Nyi Ageng Serang Kuningan")])
        #expect(result.selected == nil)
        #expect(result.candidates.isEmpty)
    }
    @Test func observedEnglishCikiniNameRequiresMatchingBranchAddress() {
        let result = PlaceIdentityPolicy.review(id: "cikini", query: "Perpustakaan Jakarta Cikini",
                                                words: ["perpustakaan", "jakarta"], branch: "cikini",
                                                results: [pin("actual-name", "Jakarta Provincial Library", "Jalan Cikini Raya No. 73, Central Jakarta")])
        #expect(result.selected?.id == "actual-name")
    }
    @Test func englishAliasCannotTransferCikiniFactsToAnotherBranch() {
        let result = PlaceIdentityPolicy.review(id: "cikini", query: "Perpustakaan Jakarta Cikini",
                                                words: ["perpustakaan", "jakarta"], branch: "cikini",
                                                results: [pin("wrong-branch", "Jakarta Provincial Library", "Nyi Ageng Serang Kuningan, Jakarta")])
        #expect(result.selected == nil && result.candidates.isEmpty)
    }
    @Test func crossingAnHourlyBoundaryUsesBothIntervals() {
        let start = TripClock.date("2026-11-06T02:00:00Z")
        let hours: [WeatherHour] = [.init(start: start, rainChance: 0.1), .init(start: start.addingTimeInterval(3600), rainChance: 0.9)]
        #expect(WeatherPolicy.rain(hours, start: start.addingTimeInterval(1800), end: start.addingTimeInterval(5400)) == 0.9)
        #expect(WeatherPolicy.rain(hours, start: start, end: start.addingTimeInterval(3600)) == 0.1)
        #expect(WeatherPolicy.rain([hours[0]], start: start, end: start.addingTimeInterval(5400)) == nil)
    }
    @Test func duplicateOrInvalidWeatherNeverBecomesZero() {
        let start = TripClock.date("2026-11-06T02:00:00Z")
        #expect(WeatherPolicy.sanitized([.init(start: start, rainChance: 1.2)]).isEmpty)
        #expect(WeatherPolicy.sanitized([.init(start: start, rainChance: 0.1), .init(start: start, rainChance: 0.9)]).isEmpty)
        #expect(WeatherPolicy.rain([], start: start, end: start.addingTimeInterval(3600)) == nil)
    }
    @Test func groupingBoundsEveryMemberAgainstRepresentative() {
        let groups = WeatherPolicy.groups([("a", pin("a")), ("b", pin("b", lat: -6.20)), ("c", pin("c", lat: -6.25))])
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { group in group.allSatisfy { WeatherPolicy.distance(group[0].1, $0.1) <= 3000 } })
    }
}

@Suite("P3 complete replay and failure paths", .serialized)
@MainActor struct PipelineTests {
    let now = IntegrationReplay.now
    func run(_ pipeline: IntegrationPipeline, request: TripRequest) async throws -> IntegratedPlan {
        let review = try await pipeline.recommend(request, now: now)
        var prepared = try await pipeline.prepare(review, selectedIDs: request.requiredCandidateIDs, now: now)
        for location in prepared.locations where location.selected == nil {
            let pin = try #require(location.candidates.first)
            try prepared.choose(pin.id, for: location.id)
        }
        return try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: now)
    }
    @Test func fullReplayPreservesPlacesAndExactArithmetic() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        let request = IntegrationReplay.request()
        let plan = try await run(pipeline, request: request)
        #expect(plan.feasible)
        #expect(plan.evidenceMode == "synthetic_replay")
        #expect(Set(plan.stops.map(\.id)) == Set(request.requiredCandidateIDs))
        #expect(plan.legs.count == 3)
        #expect(plan.travelMinutes == 60)
        try PlanAudit.validate(plan)
        #expect(plan.rawRoutingReport != nil)
    }
    @Test func emptyProfileIsGeneralRatherThanPersonalized() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        let review = try await pipeline.recommend(IntegrationReplay.request(), now: now)
        #expect(review.quality.status == "general_not_personalized")
        let selected = review.suggestions.filter(\.recommended)
        #expect(Set(selected.map(\.venueID)).count == selected.count)
        #expect(selected.allSatisfy { $0.selectable })
    }
    @Test func unknownMandatoryFeatureCannotBorrowEvidenceFromOtherVenue() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        var request = IntegrationReplay.request()
        request.requiredCandidateIDs = ["cikini"]; request.profile.must = [.wifi]
        let review = try await pipeline.recommend(request, now: now)
        let required = try #require(review.suggestions.first { $0.id == "cikini" })
        #expect(required.required && !required.selectable)
        await #expect(throws: (any Error).self) { try await pipeline.prepare(review, selectedIDs: ["cikini"], now: now) }
    }
    @Test func unknownSourceReferenceRejectedByFinalAudit() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        var plan = try await run(pipeline, request: IntegrationReplay.request())
        plan.stops[0].sourceIDs.append("invented-source")
        #expect(throws: (any Error).self) { try PlanAudit.validate(plan) }
    }
    @Test func thirtyMoreMinutesPropagatesAndOriginalStaysUnchanged() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        var request = IntegrationReplay.request(); request.requiredCandidateIDs = ["cikini"]
        let original = try await run(pipeline, request: request)
        let bytes = try IntegrationJSON.encoder().encode(original)
        request.id = UUID(); request.revision += 1; request.durationByVenue["cikini"] = 90
        let updated = try await run(pipeline, request: request)
        #expect(updated.finish == original.finish?.addingTimeInterval(1800))
        #expect(updated.stops[0].leave == original.stops[0].leave.addingTimeInterval(1800))
        #expect(try IntegrationJSON.encoder().encode(original) == bytes)
    }
    @Test func deadlineFailureCannotBeAppliedAndDoesNotDropPlace() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        var request = IntegrationReplay.request(); request.requiredCandidateIDs = ["cikini"]
        request.deadline = TripClock.date("2026-11-06T03:45:00Z") // 10:45 return; one 20m leg + rounded 60m visit +20m return cannot fit
        let plan = try await run(pipeline, request: request)
        #expect(!plan.feasible)
        #expect(plan.prepared.selectedIDs == ["cikini"])
        var session = IntegrationSession(); session.proposal = plan
        #expect(throws: (any Error).self) { try session.apply(now: now) }
        #expect(session.accepted == nil)
    }
    @Test func unsupportedRequiredPlaceIsKeptForCorrection() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        var request = IntegrationReplay.request(); request.requiredCandidateIDs = ["dialogue"]
        let review = try await pipeline.recommend(request, now: now)
        #expect(review.suggestions.contains { $0.id == "dialogue" && $0.required && !$0.selectable })
        await #expect(throws: (any Error).self) { try await pipeline.prepare(review, selectedIDs: ["dialogue"], now: now) }
    }
    @Test func intentMustBeConfirmedAndMandatorySelectionsCannotDisappear() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        var request = IntegrationReplay.request(); request.profile.direction = "Coffee, not a silent room."
        let review = try await pipeline.recommend(request, now: now)
        #expect(review.quality.status == "preference_review_required")
        await #expect(throws: (any Error).self) { try await pipeline.prepare(review, selectedIDs: ["cikini"], now: now) }
    }
    @Test func unavailableETAProducesConflictInsteadOfInventedDuration() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        pipeline.replayETA = { from, to, mode, _ in
            .init(id: "\(from.id)>\(to.id)", mode: mode, seconds: nil, status: "unavailable", note: "Injected outage")
        }
        let plan = try await run(pipeline, request: IntegrationReplay.request())
        #expect(!plan.feasible)
        #expect(plan.prepared.selectedIDs.count == 2)
        #expect(plan.legs.allSatisfy { $0.seconds == nil })
    }
    @Test func cancellationNeverBecomesSuccess() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        let enteredETA = AsyncStream<Void>.makeStream()
        pipeline.replayETA = { _, _, _, _ in
            enteredETA.continuation.yield(())
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }
        let task = Task {
            defer { enteredETA.continuation.finish() }
            return try await run(pipeline, request: IntegrationReplay.request())
        }
        var iterator = enteredETA.stream.makeAsyncIterator()
        guard await iterator.next() != nil else {
            _ = try await task.value
            Issue.record("Routing finished without entering the expected pending ETA operation.")
            return
        }
        pipeline.cancel()
        task.cancel()
        enteredETA.continuation.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func changedRevisionAndForgedPinRejectedBeforeRouting() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        let review = try await pipeline.recommend(IntegrationReplay.request(), now: now)
        var prepared = try await pipeline.prepare(review, selectedIDs: review.request.requiredCandidateIDs, now: now)
        prepared.request.revision += 1
        await #expect(throws: (any Error).self) { try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: now) }
        prepared.request.revision -= 1
        prepared.locations[0].selected = PlacePin(id: "forged", name: "Fake", address: "Jakarta", latitude: -6.2, longitude: 106.8)
        await #expect(throws: (any Error).self) { try await pipeline.plan(prepared, review: review, baseAcceptedID: nil, now: now) }
    }
    @Test func applyRejectAndStaleBaseGuard() async throws {
        let pipeline = try IntegrationReplay.pipeline()
        let plan = try await run(pipeline, request: IntegrationReplay.request())
        var session = IntegrationSession(); session.proposal = plan
        #expect(throws: (any Error).self) { try session.apply(now: now.addingTimeInterval(901)) }
        try session.apply(now: now); #expect(session.accepted?.id == plan.id); #expect(session.proposal == nil)
        session.proposal = plan // Created with nil base; accepted now exists.
        #expect(throws: (any Error).self) { try session.apply(now: now) }
        session.proposal = nil
        #expect(session.accepted?.id == plan.id)
    }
    @Test func storageRoundTripBackupRecoveryAndExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("P3Store-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TripStore(directory: folder)
        let pipeline = try IntegrationReplay.pipeline()
        let plan = try await run(pipeline, request: IntegrationReplay.request())
        var session = IntegrationSession(); session.proposal = plan
        try await store.save(session)
        #expect(try await store.load().session.proposal?.id == plan.id)
        try session.apply(now: now); try await store.save(session)
        try Data("corrupt".utf8).write(to: folder.appendingPathComponent("session.json"))
        let restored = try await store.load()
        #expect(restored.session.proposal?.id == plan.id)
        #expect(!restored.warnings.isEmpty)
        let export = try await store.export(plan)
        #expect(FileManager.default.fileExists(atPath: export.appendingPathComponent("native-report.json").path))
        #expect(try String(contentsOf: export.appendingPathComponent("REPORT.md"), encoding: .utf8).contains("synthetic_replay"))
    }
}
