import Foundation
import XCTest

@testable import C67LocalHarness

@MainActor final class NativeTripActiveTests: XCTestCase {
    let runtime = UUID()
    func report() -> NativeTripReport { NativeTripActiveSimulation.report() }
    func time(_ minutes: Int) -> Date { report().draft.clockDate(minutes: minutes) }
    func state() throws -> NativeTripActiveTrip { try .start(report: report(), at: time(480)) }
    func currentB() throws -> NativeTripActiveTrip {
        var value = try state()
        try action(&value, .arrive("A"), 490)
        try action(&value, .beginVisit("A"), 490)
        try action(&value, .depart("A"), 520)
        try action(&value, .arrive("B"), 530)
        try action(&value, .beginVisit("B"), 530)
        return value
    }
    func action(
        _ state: inout NativeTripActiveTrip, _ command: NativeTripActiveCommand, _ minute: Int,
        original: NativeTripReport? = nil, id: String = UUID().uuidString
    ) throws {
        try state.perform(
            command, actionID: id, at: time(minute), original: original ?? report(),
            runtimeSessionID: runtime)
    }
    func services(_ projection: NativeTripReplanProjection, missing: Bool = false)
        -> NativeTripAppleServices
    {
        let points = projection.draft.allPoints
        let arcs: [[String: Any]] = points.flatMap { from in
            points.filter { $0.id != from.id }.map { to in
                var arc: [String: Any] = [
                    "from": from.id, "to": to.id, "mode": projection.draft.modes[0].rawValue, "start": 0.0,
                    "end": 172800.0, "status": missing ? "unavailable" : "available",
                ]
                if !missing {
                    arc["seconds"] = NativeTripActiveSimulation.seconds(from: from.id, to: to.id)
                }
                return arc
            }
        }
        return NativeTripAppleServices(["oracle": arcs], draft: projection.draft)
    }
    func plan(_ state: NativeTripActiveTrip, minute: Int = 540, original: NativeTripReport? = nil)
        async throws -> NativeTripReplanProposal
    {
        let projection = try state.projection(
            original: original ?? report(), at: time(minute), anchorConfirmed: true)
        let result = try await NativeTripActivePlanner.plan(
            projection, services: services(projection), progress: { _ in })
        return .init(
            producerSessionID: runtime, projection: projection, report: result,
            baseline: result.candidates.first)
    }
    func store(_ active: NativeTripActiveTrip? = nil) throws -> NativeTripLocalStore {
        let repository = NativeTripLocalStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        _ = try repository.commit(
            .init(draft: report().draft, acceptedReport: report(), activeTrip: active), expected: nil)
        return repository
    }
    func controller(
        _ repository: NativeTripLocalStore, now: @escaping @MainActor () -> Date,
        planner: NativeTripActiveController.Planner? = nil, timeout: Double = 90
    ) -> NativeTripActiveController {
        .init(
            store: repository,
            logs: NativeTripLogStore(directory: repository.directory.appendingPathComponent("logs")),
            clock: now, timeoutSeconds: timeout, planner: planner)
    }
    func settle(_ value: NativeTripActiveController) async throws {
        let start = Date()
        while value.isBusy && Date().timeIntervalSince(start) < 3 {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertFalse(value.isBusy)
    }

    func testLifecycleRecordsManualFactsAndSingleCurrentVisit() throws {
        let value = try currentB()
        XCTAssertEqual(value.current?.stopID, "B")
        XCTAssertEqual(value.visits.first { $0.stopID == "A" }?.departedAt, time(520))
        XCTAssertEqual(value.actualLegs.count, 2)
        XCTAssertEqual(value.actualLegs[1].departedAt, time(520))
        XCTAssertEqual(value.pendingIDs, ["C", "D"])
    }
    func testCannotStartSecondVisitBeforeCompletingCurrent() throws {
        var value = try currentB()
        let before = try JSONEncoder().encode(value)
        XCTAssertThrowsError(try action(&value, .arrive("C"), 540))
        XCTAssertThrowsError(try action(&value, .beginVisit("C"), 540))
        XCTAssertEqual(try JSONEncoder().encode(value).count, before.count)
        XCTAssertEqual(value.current?.stopID, "B")
    }
    func testArrivalBeforeOpeningDoesNotInventActualStart() throws {
        var original = report()
        original.draft.stops[0].opening = .init(opensMinute: 600)
        var value = try state()
        try action(&value, .arrive("A"), 490, original: original)
        let projection = try value.projection(original: original, at: time(500), anchorConfirmed: true)
        XCTAssertNil(value.current?.startedAt)
        XCTAssertEqual(projection.draft.departure, time(630))
        XCTAssertEqual(value.current?.arrivedAt, time(490))
    }
    func testActualOutsideHoursRemainsFactWithWarning() throws {
        var original = report()
        original.draft.stops[0].opening = .init(opensMinute: 600)
        var value = try state()
        try action(&value, .arrive("A"), 490, original: original)
        try action(&value, .beginVisit("A"), 490, original: original)
        XCTAssertEqual(value.current?.startedAt, time(490))
        XCTAssertFalse(value.warnings(original: original).isEmpty)
    }
    func testClockCannotMoveBackwardsOrCreateNegativeVisit() throws {
        var value = try currentB()
        let revision = value.inputRevision
        XCTAssertThrowsError(try action(&value, .depart("B"), 529))
        XCTAssertEqual(value.inputRevision, revision)
        XCTAssertEqual(value.current?.status, .visiting)
    }
    func testExtendThirtyMinutesHasExact1130FinishAndFrozenPrefix() async throws {
        var value = try currentB()
        let prefix = value.visits.first { $0.stopID == "A" }!
        try action(&value, .extend(30), 540)
        XCTAssertEqual(value.current?.plannedLeaveAt, time(590))
        let proposal = try await plan(value)
        XCTAssertEqual(proposal.baseline?.finish, time(690))
        XCTAssertEqual(proposal.report.fastest?.finish, time(690))
        XCTAssertEqual(proposal.report.fastest?.order, ["C", "D"])
        XCTAssertEqual(proposal.totalRemainingMinutes, 150)
        XCTAssertEqual(proposal.report.fastest?.elapsedMinutes, 100)
        value.proposal = proposal
        try action(&value, .apply(proposal.id), 540)
        XCTAssertEqual(value.visits.first { $0.stopID == "A" }?.arrivedAt, prefix.arrivedAt)
        XCTAssertEqual(value.visits.first { $0.stopID == "A" }?.departedAt, prefix.departedAt)
        XCTAssertEqual(value.current?.stopID, "B")
        XCTAssertFalse(value.needsReplan)
    }
    func testOverdueExtensionUsesNowAndSetLeaveCannotGoBack() throws {
        var value = try currentB()
        try action(&value, .extend(30), 600)
        XCTAssertEqual(value.current?.plannedLeaveAt, time(630))
        XCTAssertThrowsError(try action(&value, .setLeave(time(599)), 600))
        XCTAssertEqual(value.current?.plannedLeaveAt, time(630))
    }
    func testProjectionKeepsOriginalEndpointWhenAnchorChanges() throws {
        let value = try currentB()
        let projection = try value.projection(original: report(), at: time(540), anchorConfirmed: true)
        XCTAssertEqual(projection.draft.origin.id, "B")
        XCTAssertEqual(projection.draft.endPoint.id, "O")
        XCTAssertFalse(projection.draft.returnsToOrigin)
        var original = report()
        original.draft.returnsToOrigin = false
        original.draft.end = .init(
            id: "E", title: "Endpoint lain", query: "", latitude: 0.01, longitude: 0)
        XCTAssertEqual(
            try value.projection(original: original, at: time(540), anchorConfirmed: true).draft.endPoint
                .id, "E")
    }
    func testOnlyPendingLegsAreRequested() async throws {
        let value = try currentB()
        let projection = try value.projection(original: report(), at: time(540), anchorConfirmed: true)
        let provider = services(projection)
        _ = try await NativeTripActivePlanner.plan(projection, services: provider, progress: { _ in })
        XCTAssertFalse(
            provider.requests.contains { ($0["to"] as? String) == "A" || ($0["to"] as? String) == "B" })
    }
    func testCurrentClosingConflictPreventsApply() async throws {
        var value = try currentB()
        var original = report()
        original.draft.stops[1].opening = .init(closesMinute: 550)
        let proposal = try await plan(value, original: original)
        XCTAssertFalse(proposal.canApply)
        value.proposal = proposal
        XCTAssertThrowsError(try action(&value, .apply(proposal.id), 540, original: original))
    }
    func testSkipIsExplicitAndDoesNotCreateCompletedHistory() throws {
        var value = try currentB()
        try action(&value, .skip("C"), 540)
        XCTAssertEqual(value.visits.first { $0.stopID == "C" }?.status, .skipped)
        XCTAssertNil(value.visits.first { $0.stopID == "C" }?.arrivedAt)
        XCTAssertEqual(value.pendingIDs, ["D"])
        XCTAssertThrowsError(try action(&value, .skip("A"), 540))
    }
    func testEndOnlyPreservesEndpointAndDoesNotMakeFakeStop() async throws {
        var value = try currentB()
        try action(&value, .skip("C"), 540)
        try action(&value, .skip("D"), 540)
        let proposal = try await plan(value)
        XCTAssertEqual(proposal.report.fastest?.order, [])
        XCTAssertEqual(proposal.report.fastest?.legs.count, 1)
        XCTAssertEqual(proposal.report.fastest?.legs.last?.to.id, "O")
        XCTAssertEqual(proposal.report.fastest?.legs.last?.dwellMinutes, 0)
        XCTAssertTrue(proposal.canApply)
    }
    func testZeroRemainingAtEndpointNeedsNoProviderRequests() async throws {
        var value = try state()
        for id in ["A", "B", "C", "D"] { try action(&value, .skip(id), 480) }
        let projection = try value.projection(original: report(), at: time(480), anchorConfirmed: true)
        let provider = services(projection)
        let result = try await NativeTripActivePlanner.plan(
            projection, services: provider, progress: { _ in })
        XCTAssertEqual(provider.directionRequests, 0)
        XCTAssertEqual(result.fastest?.elapsedMinutes, 0)
        try action(&value, .finish, 480)
        XCTAssertFalse(value.isActive)
    }
    func testDeadlineChangeDoesNotMoveDeadlineWithActualStart() throws {
        var value = try .start(report: report(), at: time(500)) as NativeTripActiveTrip
        XCTAssertEqual(value.finishBy, time(720))
        try action(&value, .deadline(time(660)), 500)
        XCTAssertEqual(
            try value.projection(original: report(), at: time(500), anchorConfirmed: true).draft.finishBy,
            time(660))
        XCTAssertThrowsError(try action(&value, .deadline(time(1500)), 500))
    }
    func testImpossibleDeadlineKeepsAllNonSkippedTargets() async throws {
        var value = try currentB()
        try action(&value, .deadline(time(580)), 540)
        let proposal = try await plan(value)
        XCTAssertFalse(proposal.canApply)
        XCTAssertEqual(proposal.projection.draft.stops.map(\.id), ["C", "D"])
        XCTAssertEqual(value.pendingIDs, ["C", "D"])
        value.proposal = proposal
        XCTAssertThrowsError(try action(&value, .apply(proposal.id), 540))
    }
    func testMissingETAIsIncompleteNotZero() async throws {
        let value = try currentB()
        let projection = try value.projection(original: report(), at: time(540), anchorConfirmed: true)
        let result = try await NativeTripActivePlanner.plan(
            projection, services: services(projection, missing: true), progress: { _ in })
        XCTAssertFalse(result.fastest?.feasible == true)
        XCTAssertFalse(result.candidates.contains { $0.complete })
        XCTAssertTrue(result.candidates.contains { !$0.conflicts.isEmpty })
    }
    func testSameActionIsIdempotentButDifferentPayloadIsRejected() throws {
        var value = try currentB()
        try action(&value, .extend(30), 540, id: "same")
        let revision = value.inputRevision
        try action(&value, .extend(30), 550, id: "same")
        XCTAssertEqual(value.inputRevision, revision)
        XCTAssertEqual(value.current?.plannedLeaveAt, time(590))
        XCTAssertThrowsError(try action(&value, .extend(15), 550, id: "same"))
    }
    func testProposalBecomesStaleAfterFactAndAfterSixtySeconds() async throws {
        var value = try currentB()
        let proposal = try await plan(value)
        value.proposal = proposal
        XCTAssertThrowsError(try action(&value, .apply(proposal.id), 562))
        try action(&value, .extend(30), 540)
        XCTAssertNil(value.proposal)
        XCTAssertThrowsError(try action(&value, .apply(proposal.id), 540))
    }
    func testRestoredProposalCannotApplyInNewRuntimeSession() async throws {
        var value = try currentB()
        let proposal = try await plan(value)
        value.proposal = proposal
        let repository = try store(value)
        let restored = controller(repository, now: { self.time(540) })
        XCTAssertNotNil(restored.active?.proposal)
        XCTAssertFalse(restored.canApply)
        restored.perform(.apply(proposal.id))
        XCTAssertNotNil(restored.error)
        XCTAssertEqual(restored.active?.inputRevision, value.inputRevision)
    }
    func testRejectKeepsAcceptedPlanAndFacts() async throws {
        var value = try currentB()
        let proposal = try await plan(value)
        value.proposal = proposal
        try action(&value, .reject(proposal.id), 540)
        XCTAssertNil(value.proposal)
        XCTAssertTrue(value.needsReplan)
        XCTAssertEqual(value.current?.startedAt, time(530))
        XCTAssertNil(value.acceptedRemaining)
    }
    func testCurrentInputsSurvivePlannerFailureAndRestore() async throws {
        let repository = try store(try currentB())
        let value = controller(
            repository, now: { self.time(540) },
            planner: { _, _ in throw URLError(.notConnectedToInternet) })
        value.perform(.extend(30), at: time(540))
        value.requestReplan(anchorConfirmed: true)
        try await settle(value)
        XCTAssertNotNil(value.error)
        XCTAssertEqual(try repository.load().session?.activeTrip?.current?.plannedLeaveAt, time(590))
        XCTAssertEqual(try repository.load().session?.activeTrip?.pendingIDs, ["C", "D"])
    }
    func testFailedFactSaveAndRetryPublishOnlyCommittedState() throws {
        let repository = try store(try currentB())
        let value = controller(repository, now: { self.time(540) })
        let revision = value.session!.revision
        value.failNextSave()
        value.perform(.extend(30), at: time(540))
        XCTAssertNotNil(value.error)
        XCTAssertEqual(value.session?.revision, revision)
        XCTAssertEqual(value.active?.current?.plannedLeaveAt, time(560))
        value.retry()
        XCTAssertNil(value.error)
        XCTAssertEqual(value.active?.current?.plannedLeaveAt, time(590))
        XCTAssertEqual(try repository.load().session?.activeTrip?.current?.plannedLeaveAt, time(590))
    }
    func testFailedApplyKeepsProposalAndRetryIsIdempotent() async throws {
        let repository = try store(try currentB())
        let value = controller(
            repository, now: { self.time(540) },
            planner: { projection, _ in
                try await NativeTripActivePlanner.plan(
                    projection, services: self.services(projection), progress: { _ in })
            })
        value.requestReplan(anchorConfirmed: true)
        try await settle(value)
        let proposal = try XCTUnwrap(value.active?.proposal)
        let revision = value.session!.revision
        value.failNextSave()
        value.perform(.apply(proposal.id), actionID: "apply")
        XCTAssertNotNil(value.error)
        XCTAssertEqual(value.session?.revision, revision)
        XCTAssertNil(value.active?.acceptedRemaining)
        XCTAssertNotNil(value.active?.proposal)
        value.retry()
        XCTAssertNil(value.error)
        XCTAssertNotNil(value.active?.acceptedRemaining)
        let appliedRevision = value.session!.revision
        value.perform(.apply(proposal.id), actionID: "apply")
        XCTAssertEqual(value.session?.revision, appliedRevision)
        XCTAssertEqual(value.active?.current?.startedAt, time(530))
    }
    func testV1PlannedSessionPromotesToV2WithoutChangingInitialPlan() throws {
        let repository = try store()
        let before = try repository.load().session!
        XCTAssertEqual(before.schemaVersion, 1)
        let value = controller(repository, now: { self.time(480) })
        value.start()
        XCTAssertNil(value.error)
        XCTAssertEqual(value.session?.schemaVersion, 2)
        XCTAssertEqual(
            value.session?.acceptedReport?.fastest?.order, before.acceptedReport?.fastest?.order)
        XCTAssertEqual(value.session?.activeTrip?.visits.count, 4)
    }
    func testActiveTripGuardsPlannerReplacementAndStorageRestore() throws {
        let repository = try store(try currentB())
        let model = NativeTripModel(
            logs: NativeTripLogStore(directory: repository.directory.appendingPathComponent("logs")),
            localStore: repository)
        let before = model.draft
        model.startNewTrip()
        model.useStorageExample()
        model.useActiveExample()
        model.saveLocal(acceptReport: true)
        XCTAssertEqual(model.draft, before)
        XCTAssertTrue(model.hasActiveTrip)
        XCTAssertNotNil(model.storageError)
        XCTAssertEqual(try repository.load().session?.activeTrip?.current?.stopID, "B")
    }
    func testPrivateCarAndTransitRequireExplicitSupportedScope() throws {
        var original = report()
        original.draft.carUse = "privateCar"
        XCTAssertThrowsError(try NativeTripActiveTrip.start(report: original, at: time(480)))
        original = report()
        original.draft.transit = true
        XCTAssertThrowsError(try NativeTripActiveTrip.start(report: original, at: time(480)))
    }
    func testStaleOperationalDateRejectedBeforePlanning() throws {
        let value = try currentB()
        var original = report()
        original.draft.stops[2].opening = .init(
            opensMinute: 600, serviceDate: "2026-11-06", timeZoneID: "Asia/Jakarta")
        XCTAssertThrowsError(
            try value.projection(original: original, at: time(540), anchorConfirmed: true))
    }
    func testRequestRequiresAnchorConfirmationAndSameServiceDay() throws {
        let value = try currentB()
        XCTAssertThrowsError(
            try value.projection(original: report(), at: time(540), anchorConfirmed: false))
        XCTAssertThrowsError(
            try value.projection(original: report(), at: time(1980), anchorConfirmed: true))
    }
    func testBaselineRetainedOnTieAndExplicitBudgetRespected() async throws {
        var value = try currentB()
        value.acceptedOrder = ["D", "C"]
        var projection = try value.projection(original: report(), at: time(540), anchorConfirmed: true)
        projection.draft.routingRequestLimit = 16
        let points = projection.draft.allPoints
        let arcs: [[String: Any]] = points.flatMap { from in
            points.filter { $0.id != from.id }.map { to in
                [
                    "from": from.id, "to": to.id, "mode": "automobile", "seconds": 600.0,
                    "status": "available", "start": 0.0, "end": 172800.0,
                ]
            }
        }
        let provider = NativeTripAppleServices(["oracle": arcs], draft: projection.draft)
        let result = try await NativeTripActivePlanner.plan(
            projection, services: provider, progress: { _ in })
        XCTAssertEqual(result.candidates.first?.order, ["D", "C"])
        XCTAssertEqual(result.fastest?.order, ["D", "C"])
        XCTAssertLessThanOrEqual(provider.directionRequests, 16)
        XCTAssertNil(result.weatherChoice)
    }
    func testLateResultAfterNewRequestCannotReplaceLatestProposal() async throws {
        let repository = try store(try currentB())
        var continuations: [CheckedContinuation<NativeTripReport, Error>] = []
        var projections: [NativeTripReplanProjection] = []
        let value = controller(
            repository, now: { self.time(540) },
            planner: { projection, _ in
                projections.append(projection)
                return try await withCheckedThrowingContinuation { continuations.append($0) }
            })
        value.requestReplan(anchorConfirmed: true)
        while continuations.count < 1 { await Task.yield() }
        value.perform(.extend(30), at: time(540))
        value.requestReplan(anchorConfirmed: true)
        while continuations.count < 2 { await Task.yield() }
        let resultB = try await NativeTripActivePlanner.plan(
            projections[1], services: services(projections[1]), progress: { _ in })
        continuations[1].resume(returning: resultB)
        try await settle(value)
        let latestID = value.active?.proposal?.projection.requestID
        let resultA = try await NativeTripActivePlanner.plan(
            projections[0], services: services(projections[0]), progress: { _ in })
        continuations[0].resume(returning: resultA)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(value.active?.proposal?.projection.requestID, latestID)
        XCTAssertEqual(value.active?.current?.plannedLeaveAt, time(590))
    }
    func testCancellationPreventsLateProposalPersistence() async throws {
        let repository = try store(try currentB())
        var continuation: CheckedContinuation<NativeTripReport, Error>?
        var captured: NativeTripReplanProjection?
        let value = controller(
            repository, now: { self.time(540) },
            planner: { projection, _ in
                captured = projection
                return try await withCheckedThrowingContinuation { continuation = $0 }
            })
        value.requestReplan(anchorConfirmed: true)
        while continuation == nil { await Task.yield() }
        value.cancel(reason: "background")
        continuation!.resume(
            returning: try await NativeTripActivePlanner.plan(
                captured!, services: services(captured!), progress: { _ in }))
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertFalse(value.isBusy)
        XCTAssertNil(value.active?.proposal)
        XCTAssertNil(try repository.load().session?.activeTrip?.proposal)
    }
    func testWatchdogStopsOperationAndKeepsFacts() async throws {
        let repository = try store(try currentB())
        let value = controller(
            repository, now: { self.time(540) },
            planner: { _, _ in
                try await Task.sleep(for: .seconds(10))
                throw CancellationError()
            }, timeout: 0.02)
        value.requestReplan(anchorConfirmed: true)
        try await settle(value)
        XCTAssertNotNil(value.error)
        XCTAssertEqual(value.active?.current?.stopID, "B")
    }
    func testMalformedActiveStateCannotCommit() throws {
        let repository = try store(try currentB())
        let initial = try repository.load().session!
        var value = initial
        value.activeTrip!.visits[0].departedAt = time(480)
        XCTAssertThrowsError(try repository.commit(value, expected: initial))
        XCTAssertEqual(try repository.load().session?.revision, initial.revision)
    }
    func testActualLegMustMatchRecordedArrivalAndPreviousDeparture() throws {
        var value = try currentB()
        value.actualLegs[1].departedAt = time(521)
        XCTAssertThrowsError(try value.validate(original: report()))
        value = try currentB()
        value.actualLegs[1].arrivedAt = time(531)
        XCTAssertThrowsError(try value.validate(original: report()))
        value = try currentB()
        value.actualLegs.removeLast()
        XCTAssertThrowsError(try value.validate(original: report()))
    }
    func testEqualTimestampsUseActualLegSequenceForLatestAnchor() throws {
        var value = try state()
        value.acceptedOrder = ["B", "A", "C", "D"]
        for id in ["B", "A"] {
            try action(&value, .arrive(id), 490)
            try action(&value, .beginVisit(id), 490)
            try action(&value, .depart(id), 490)
        }
        XCTAssertEqual(value.lastCompleted?.stopID, "A")
        XCTAssertEqual(
            try value.projection(original: report(), at: time(490), anchorConfirmed: true).draft.origin
                .id, "A")
        try action(&value, .arrive("C"), 490)
        XCTAssertEqual(value.actualLegs.last?.fromID, "A")
    }

}
