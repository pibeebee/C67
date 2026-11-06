import Foundation
import XCTest

@testable import C67LocalHarness

@MainActor final class LocalTripTests: XCTestCase {
    func store() -> NativeTripLocalStore {
        NativeTripLocalStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
    func fixture() throws -> ([String: Any], NativeTripDraft) {
        let url = Bundle.module.url(
            forResource: "jakarta-recorded-static", withExtension: "json", subdirectory: "Fixtures")!
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let draft = try decoder.decode(
            NativeTripDraft.self, from: JSONSerialization.data(withJSONObject: input["draft"]!))
        return (input, draft)
    }
    func report() async throws -> NativeTripReport {
        let (input, draft) = try fixture()
        return try await NativeTripEngine.plan(
            draft, services: NativeTripAppleServices(input, draft: draft), progress: { _ in })
    }
    func model(_ repository: NativeTripLocalStore) -> NativeTripModel {
        NativeTripModel(
            logs: NativeTripLogStore(directory: repository.directory.appendingPathComponent("logs")),
            localStore: repository)
    }

    func testDefaultNativeLaunchDoesNotRequireLegacyBootstrap() {
        XCTAssertTrue(NativeTripLaunchRouting.usesNativePlanner(arguments: ["app"]))
        for flag in [
            "--legacy-poc", "--diary-demo", "--diary-ui-testing", "--ui-testing", "--demo-preview",
        ] {
            XCTAssertFalse(NativeTripLaunchRouting.usesNativePlanner(arguments: ["app", flag]))
            XCTAssertTrue(
                NativeTripLaunchRouting.usesNativePlanner(arguments: ["app", flag, "--native-itinerary"]))
        }
    }
    func testLocalDemoUsesValidSyntheticScheduleWithoutServices() throws {
        let report = NativeTripLocalSession.simulatedReport()
        XCTAssertNoThrow(try NativeTripLocalSession.validateAccepted(report))
        XCTAssertEqual(report.requests, 0)
        XCTAssertEqual(report.fastest?.elapsedMinutes, 170)
        XCTAssertTrue(report.optimizerNote!.contains("sintetis"))
    }
    func testFailedAcceptedSaveKeepsPreviousChoiceAndRetryWorks() throws {
        let repository = store()
        let controller = model(repository)
        controller.useStorageExample()
        controller.saveLocal(acceptReport: true)
        let bytes = try Data(contentsOf: repository.primaryURL)
        let revision = controller.localSession!.revision
        controller.failNextLocalSave()
        controller.saveLocal(acceptReport: true)
        XCTAssertNotNil(controller.storageError)
        XCTAssertEqual(try Data(contentsOf: repository.primaryURL), bytes)
        XCTAssertEqual(controller.localSession?.revision, revision)
        controller.saveLocal(acceptReport: true)
        XCTAssertNil(controller.storageError)
        XCTAssertEqual(controller.localSession?.revision, revision + 1)
    }
    func testLegacyDraftRetainsEndOfDayAndCarPolicy() throws {
        let (_, draft) = try fixture()
        XCTAssertNil(draft.finishBy)
        XCTAssertEqual(draft.deadline, draft.endOfDay)
        XCTAssertTrue(draft.deadlineSummary.contains("akhir hari"))
        var old = draft
        old.automobile = nil
        old.carUse = nil
        old.routingAdaptive = nil
        let decoded = try JSONDecoder().decode(NativeTripDraft.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.automobile)
        XCTAssertNil(decoded.finishBy)
    }
    func testRejectsDeadlineBeforeStartAndBeyondDay() throws {
        var (_, draft) = try fixture()
        draft.finishBy = draft.departure
        XCTAssertThrowsError(try draft.validate())
        draft.finishBy = draft.endOfDay.addingTimeInterval(1)
        XCTAssertThrowsError(try draft.validate())
        draft.finishBy = draft.endOfDay
        XCTAssertNoThrow(try draft.validate())
    }
    func testDeadlineReachesBothPipelineAndSnapshot() async throws {
        var (input, draft) = try fixture()
        draft.finishBy = draft.departure.addingTimeInterval(60 * 60)
        for algorithm in ["baseline", "hybrid"] {
            draft.routingAlgorithm = algorithm
            let value = try await NativeTripEngine.plan(
                draft, services: NativeTripAppleServices(input, draft: draft), progress: { _ in })
            XCTAssertFalse(value.fastest?.feasible == true)
            XCTAssertTrue(value.candidates.contains { !$0.conflicts.isEmpty })
        }
        let snapshot = try await NativeTripRoutingBridge.snapshot(
            draft, services: NativeTripAppleServices(input, draft: draft), progress: { _ in })
        XCTAssertEqual(snapshot.deadline, 3600)
    }
    func testAdaptiveCannotSkipDeadlineConflict() async throws {
        let value = try await report()
        var draft = value.draft
        draft.finishBy = value.fastest!.finish!.addingTimeInterval(-1)
        let (input, _) = try fixture()
        let services = NativeTripAppleServices(input, draft: draft)
        let result = try await NativeTripEngine.plan(draft, services: services, progress: { _ in })
        XCTAssertFalse(result.fastest?.feasible == true)
        XCTAssertTrue(
            services.events.contains {
                ($0["fields"] as? [String: String])?["reason"] == "baseline_infeasible_or_incomplete"
            })
    }
    func testExplicitTimeZoneChangePreservesBothWallClocks() throws {
        var (_, draft) = try fixture()
        draft.finishBy = draft.departure.addingTimeInterval(8 * 3600)
        let start = draft.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: draft.departure)
        let end = draft.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: draft.finishBy!)
        draft.changeTimeZone(to: "Asia/Tokyo")
        XCTAssertEqual(
            start,
            draft.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.departure))
        XCTAssertEqual(
            end,
            draft.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.finishBy!))
    }
    func testDeviceZoneDoesNotChangeDeadlineOrOperationalDate() throws {
        let (_, draft) = try fixture()
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        let deadline = draft.deadline
        let clock = draft.clock(draft.departure)
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(draft.deadline, deadline)
        XCTAssertEqual(draft.clock(draft.departure), clock)
    }
    func testEmptyUnresolvedDraftCanBeSavedWithoutAnyProvider() throws {
        let repository = store()
        let value = model(repository)
        value.draft.origin.title = "Belum dipilih"
        value.saveLocal()
        XCTAssertNil(value.storageError)
        XCTAssertEqual(try repository.load().session?.draft.origin.title, "Belum dipilih")
        XCTAssertFalse(value.hasUnsavedDraft)
    }
    func testAcceptedReportRoundTripPreservesScheduleAndUnknowns() async throws {
        let repository = store()
        let value = try await report()
        let saved = try repository.commit(
            .init(draft: value.draft, acceptedReport: value), expected: nil)
        let restored = try repository.load().session!
        XCTAssertEqual(saved.id, restored.id)
        XCTAssertEqual(restored.revision, 1)
        XCTAssertEqual(restored.acceptedReport?.fastest?.order, value.fastest?.order)
        XCTAssertEqual(restored.acceptedReport?.fastest?.elapsedMinutes, value.fastest?.elapsedMinutes)
        XCTAssertEqual(restored.acceptedReport?.fastest?.uncertainties, value.fastest?.uncertainties)
        XCTAssertEqual(restored.acceptedReport?.requests, value.requests)
        XCTAssertEqual(
            restored.acceptedReport?.generatedAt.timeIntervalSince1970 ?? 0,
            value.generatedAt.timeIntervalSince1970, accuracy: 1)
    }
    func testDraftEditsDoNotEraseAcceptedChoice() async throws {
        let repository = store()
        let value = try await report()
        _ = try repository.commit(.init(draft: value.draft, acceptedReport: value), expected: nil)
        let controller = model(repository)
        controller.draft.defaultDwell = 45
        controller.inputChanged()
        controller.saveLocal()
        XCTAssertNil(controller.report)
        XCTAssertEqual(try repository.load().session?.acceptedReport?.draft.defaultDwell, 30)
        XCTAssertEqual(try repository.load().session?.draft.defaultDwell, 45)
        controller.startNewTrip()
        XCTAssertTrue(controller.hasSavedPlan)
        XCTAssertNotNil(try repository.load().session?.acceptedReport)
    }
    func testSaveFailurePreservesDiskAndPublishedRevision() throws {
        let repository = store()
        let controller = model(repository)
        controller.saveLocal()
        let before = try Data(contentsOf: repository.primaryURL)
        let revision = controller.localSession!.revision
        controller.draft.searchContext = "Jakarta Selatan"
        controller.failNextLocalSave()
        controller.saveLocal()
        XCTAssertNotNil(controller.storageError)
        XCTAssertTrue(controller.hasUnsavedDraft)
        XCTAssertEqual(controller.localSession?.revision, revision)
        XCTAssertEqual(try Data(contentsOf: repository.primaryURL), before)
        controller.saveLocal()
        XCTAssertNil(controller.storageError)
        XCTAssertEqual(controller.localSession?.revision, revision + 1)
    }
    func testCorruptPrimaryRecoversValidatedBackup() throws {
        let repository = store()
        var value = NativeTripLocalSession(draft: .empty())
        value = try repository.commit(value, expected: nil)
        var newer = value
        newer.draft.searchContext = "new"
        _ = try repository.commit(newer, expected: value)
        try Data("broken".utf8).write(to: repository.primaryURL)
        let recovered = try repository.load()
        XCTAssertNotNil(recovered.notice)
        XCTAssertEqual(recovered.session?.revision, value.revision)
        let repaired = try repository.commit(recovered.session!, expected: recovered.session)
        XCTAssertEqual(try repository.load().session?.revision, repaired.revision)
    }
    func testMissingPrimaryUsesBackupWithVisibleNotice() throws {
        let repository = store()
        let first = try repository.commit(.init(draft: .empty()), expected: nil)
        _ = try repository.commit(first, expected: first)
        try FileManager.default.removeItem(at: repository.primaryURL)
        XCTAssertNotNil(try repository.load().notice)
    }
    func testBothCorruptRemainUntouchedAndBlockSaving() throws {
        let repository = store()
        try FileManager.default.createDirectory(
            at: repository.directory, withIntermediateDirectories: true)
        let bad = Data("bad".utf8)
        try bad.write(to: repository.primaryURL)
        try bad.write(to: repository.backupURL)
        let controller = model(repository)
        XCTAssertTrue(controller.storageBlocked)
        controller.saveLocal()
        XCTAssertEqual(try Data(contentsOf: repository.primaryURL), bad)
        XCTAssertEqual(try Data(contentsOf: repository.backupURL), bad)
    }
    func testFutureVersionBlocksEvenWithValidBackup() throws {
        let repository = store()
        let first = try repository.commit(.init(draft: .empty()), expected: nil)
        _ = try repository.commit(first, expected: first)
        let future = Data("{\"schemaVersion\":99}".utf8)
        try future.write(to: repository.primaryURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.commit(first, expected: first))
        XCTAssertEqual(try Data(contentsOf: repository.primaryURL), future)
    }
    func testStaleWriterCannotOverwriteNewerSavedDraft() throws {
        let repository = store()
        let a = model(repository)
        a.saveLocal()
        let b = model(repository)
        a.draft.searchContext = "A"
        a.saveLocal()
        b.draft.searchContext = "B"
        b.saveLocal()
        XCTAssertNotNil(b.storageError)
        XCTAssertEqual(try repository.load().session?.draft.searchContext, "A")
    }
    func testRestorationDoesNotClearReportOnObservationEcho() async throws {
        let repository = store()
        let value = try await report()
        _ = try repository.commit(.init(draft: value.draft, acceptedReport: value), expected: nil)
        let controller = model(repository)
        controller.inputChanged()
        XCTAssertNotNil(controller.report)
        XCTAssertNil(controller.storageError)
    }
    func testInvalidAcceptedArithmeticCannotCommit() async throws {
        let repository = store()
        var value = try await report()
        value.fastest!.legs[0].arrival = value.draft.departure
        XCTAssertThrowsError(
            try repository.commit(.init(draft: value.draft, acceptedReport: value), expected: nil))
        XCTAssertNil(try repository.load().session)
    }
    func testInfeasibleAcceptedPlanCannotCommit() async throws {
        var value = try await report()
        value.fastest!.conflicts = ["test conflict"]
        XCTAssertThrowsError(try NativeTripLocalSession.validateAccepted(value))
    }
    func testAcceptedEndpointCannotBeChangedSilently() async throws {
        var value = try await report()
        value.fastest!.legs[value.fastest!.legs.count - 1].to = value.draft.stops[0].point
        XCTAssertThrowsError(try NativeTripLocalSession.validateAccepted(value))
    }
    func testWeatherMetadataAndCreditSurviveRestore() async throws {
        var value = try await report()
        value.forecasts = [
            .init(
                pointID: "origin", hours: [.init(date: value.draft.departure, rainChance: 0.4)],
                status: "available", note: "Recorded test", fetchedAt: nil, provider: .weatherKit,
                retrievedAt: value.draft.departure)
        ]
        XCTAssertThrowsError(try NativeTripLocalSession.validateAccepted(value))
        value.storedWeatherCredit = .init(
            serviceName: "Apple Weather",
            legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
            combinedMarkLightURL: URL(string: "https://weatherkit.apple.com/light.svg")!,
            combinedMarkDarkURL: URL(string: "https://weatherkit.apple.com/dark.svg")!)
        let repository = store()
        _ = try repository.commit(.init(draft: value.draft, acceptedReport: value), expected: nil)
        let restored = try repository.load().session!.acceptedReport!
        XCTAssertEqual(restored.storedWeatherCredit?.serviceName, "Apple Weather")
        XCTAssertEqual(restored.forecasts[0].hours[0].rainChance, 0.4)
        XCTAssertNotNil(restored.forecasts[0].retrievedAt)
    }
    func testOversizedPrimaryIsNotDecodedOrOverwritten() throws {
        let repository = store()
        try FileManager.default.createDirectory(
            at: repository.directory, withIntermediateDirectories: true)
        let data = Data(repeating: 32, count: 8_000_001)
        try data.write(to: repository.primaryURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.primaryURL).count, data.count)
    }
}
