import XCTest
import MapKit
@testable import poc_c67

@MainActor private final class RoutingDirectionsStub: DirectionsProviding {
    struct Call {
        let origin: CLLocationCoordinate2D
        let target: CLLocationCoordinate2D
        let result: CheckedContinuation<CalculatedRoute, Error>
    }
    var calls: [Call] = []
    var cancellations = 0
    func calculate(origin: CLLocationCoordinate2D, target: CLLocationCoordinate2D) async throws -> CalculatedRoute {
        try await withCheckedThrowingContinuation { calls.append(Call(origin: origin, target: target, result: $0)) }
    }
    func cancel() { cancellations += 1 }
    func complete(_ index: Int, error: Error? = nil) {
        guard calls.indices.contains(index) else { XCTFail("Request missing"); return }
        let call = calls[index]
        if let error { call.result.resume(throwing: error); return }
        let coords = [call.origin, call.target]
        call.result.resume(returning: CalculatedRoute(polyline: MKPolyline(coordinates: coords, count: 2),
                                                      distance: 500, expectedTravelTime: 360, instructions: ["Test fixture"]))
    }
}

@MainActor final class GroupRoutingTests: XCTestCase {
    func input(scope: String = "run|simulation|leader", destination: GroupRouteDestination = .person("P01"),
               latitude: Double = 0, revision: String = "epoch-1", problem: String? = nil) -> GroupRouteInput {
        GroupRouteInput(scope: scope, destination: destination, name: "Fixture target",
                        origin: .init(latitude: 0, longitude: 0), target: .init(latitude: latitude, longitude: 0.002),
                        sourceRevision: revision, problem: problem)
    }
    func settle() async { for _ in 0 ..< 10 { await Task.yield() }; try? await Task.sleep(for: .milliseconds(10)) }
    func sample(run: UUID, at: Date, accuracy: Double = 5, reduced: Bool = false) -> LocationSample {
        LocationSample(runID: run, epoch: UUID(), sequence: 1, latitude: -6.17, longitude: 106.82,
                       measuredAt: at, accuracy: accuracy, reduced: reduced, simulated: false)
    }

    func testParticipantRoutingCanOnlyResolveLeaderAndSelfIsRejected() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.loadDemo(.reviewed)
        XCTAssertNil(app.routingInput(for: .participant, destination: .person("TL")).problem)
        XCTAssertNotNil(app.routingInput(for: .participant, destination: .person("P02")).problem)
        XCTAssertNotNil(app.routingInput(for: .participant, destination: .person("YOU")).problem)
    }
    func testStaleParticipantRemainsVisibleButCannotBeRoutedTo() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.loadDemo(.reviewed)
        XCTAssertNotNil(app.mapPoints(for: .leader).first { $0.id == "P03" })
        let input = app.routingInput(for: .leader, destination: .person("P03"))
        XCTAssertTrue(input.problem?.contains("Lokasi tujuan") == true)
    }
    func testStaticDestinationWorksWithLocalGPSWithoutStartingCloudSharing() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        let now = Date.now
        try app.store.commit { $0.mode = .real; $0.meetingPoint = MeetingPointSnapshot(latitude: -6.18, longitude: 106.83, radius: 100) }
        let own = sample(run: app.store.state.runID, at: now)
        XCTAssertNil(app.routingInput(for: .leader, destination: .meeting, localSample: own, now: now).problem)
        XCTAssertFalse(app.sensor.running); XCTAssertFalse(app.leaderSharing.sensor.running)
        XCTAssertNil(app.store.state.owner); XCTAssertFalse(app.leaderSharing.hasConnections)
    }
    func testOriginQualityRejectsStaleReducedInaccurateWrongRunAndSimulatedRealFix() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        let now = Date.now
        try app.store.commit { $0.mode = .real; $0.meetingPoint = MeetingPointSnapshot(latitude: -6.18, longitude: 106.83, radius: 100) }
        var own = sample(run: app.store.state.runID, at: now.addingTimeInterval(-61))
        XCTAssertNotNil(app.routingInput(for: .leader, destination: .meeting, localSample: own, now: now).problem)
        own.measuredAt = now; own.reduced = true
        XCTAssertNotNil(app.routingInput(for: .leader, destination: .meeting, localSample: own, now: now).problem)
        own.reduced = false; own.accuracy = 66
        XCTAssertNotNil(app.routingInput(for: .leader, destination: .meeting, localSample: own, now: now).problem)
        own.accuracy = 5; own.runID = UUID()
        XCTAssertNotNil(app.routingInput(for: .leader, destination: .meeting, localSample: own, now: now).problem)
        own.runID = app.store.state.runID; own.simulated = true
        XCTAssertNotNil(app.routingInput(for: .leader, destination: .meeting, localSample: own, now: now).problem)
    }
    func testChangedAndDeletedStaticLocationProduceNewRevisionOrBlock() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.loadDemo(.reviewed)
        let first = app.routingInput(for: .leader, destination: .meeting)
        try app.store.commit { $0.meetingPoint = MeetingPointSnapshot(latitude: -6.2, longitude: 106.8, radius: 100) }
        XCTAssertNotEqual(first.sourceRevision, app.routingInput(for: .leader, destination: .meeting).sourceRevision)
        try app.store.commit { $0.meetingPoint = nil }
        XCTAssertNotNil(app.routingInput(for: .leader, destination: .meeting).problem)
        XCTAssertNotNil(app.routingInput(for: .leader, destination: .activity(UUID())).problem)
    }
    func testNoAutomaticRequestAndBlockedInputDoesNotUseSimulationFallback() async {
        let provider = RoutingDirectionsStub(), now = Date.now
        let session = GroupRouteSession(engine: RouteLab(provider: provider))
        session.enter(scope: input().scope)
        await settle(); XCTAssertTrue(provider.calls.isEmpty)
        session.start(input(problem: "GPS stale"), now: now)
        await settle(); XCTAssertTrue(provider.calls.isEmpty); XCTAssertFalse(session.inputsReady)
        session.refresh(input(), now: now, foreground: true)
        await settle(); XCTAssertEqual(provider.calls.count, 1)
        XCTAssertEqual(provider.calls.first?.target.longitude, 0.002)
        provider.complete(0); await settle(); session.stop()
    }
    func testStaleInputCancelsRequestAndRejectsLateCompletion() async {
        let provider = RoutingDirectionsStub(), now = Date.now
        let session = GroupRouteSession(engine: RouteLab(provider: provider))
        session.start(input(), now: now); await settle()
        session.refresh(input(problem: "GPS stale"), now: now.addingTimeInterval(1), foreground: true)
        XCTAssertFalse(session.engine.isCalculating); XCTAssertFalse(session.inputsReady)
        provider.complete(0); await settle()
        XCTAssertNil(session.engine.route); XCTAssertEqual(session.engine.successes, 0)
    }
    func testMovingDestinationUsesLatestPositionAfterCooldown() async {
        let provider = RoutingDirectionsStub(), now = Date.now
        let session = GroupRouteSession(engine: RouteLab(provider: provider))
        session.start(input(), now: now); await settle()
        provider.complete(0); await settle()
        session.refresh(input(latitude: 0.001), now: now.addingTimeInterval(5), foreground: true); await settle()
        XCTAssertEqual(provider.calls.count, 1)
        session.refresh(input(latitude: 0.002), now: now.addingTimeInterval(11), foreground: true); await settle()
        XCTAssertEqual(provider.calls.count, 2); XCTAssertEqual(provider.calls.last?.target.latitude, 0.002)
        provider.complete(1); await settle(); session.stop()
    }
    func testBackgroundCancelsRoutingAndForegroundResumesAfterCooldown() async {
        let provider = RoutingDirectionsStub(), now = Date.now
        let session = GroupRouteSession(engine: RouteLab(provider: provider))
        session.start(input(), now: now); await settle()
        session.refresh(input(), now: now.addingTimeInterval(1), foreground: false)
        XCTAssertTrue(session.active); XCTAssertFalse(session.inputsReady); XCTAssertFalse(session.engine.running)
        provider.complete(0); await settle(); XCTAssertNil(session.engine.route)
        session.refresh(input(), now: now.addingTimeInterval(11), foreground: true); await settle()
        XCTAssertEqual(provider.calls.count, 2); XCTAssertTrue(session.inputsReady)
        provider.complete(1); await settle(); session.stop()
    }
    func testNewSourceEpochDiscardsOldRequestButKeepsRequestCooldown() async {
        let provider = RoutingDirectionsStub(), now = Date.now
        let session = GroupRouteSession(engine: RouteLab(provider: provider))
        session.start(input(), now: now); await settle()
        session.refresh(input(revision: "epoch-2"), now: now.addingTimeInterval(2), foreground: true)
        provider.complete(0); await settle(); XCTAssertNil(session.engine.route)
        XCTAssertEqual(provider.calls.count, 1)
        session.refresh(input(revision: "epoch-2"), now: now.addingTimeInterval(11), foreground: true); await settle()
        XCTAssertEqual(provider.calls.count, 2)
        provider.complete(1); await settle(); session.stop()
    }
    func testRunChangeAndExplicitStopInvalidatePendingResults() async {
        let provider = RoutingDirectionsStub(), now = Date.now
        let session = GroupRouteSession(engine: RouteLab(provider: provider))
        session.start(input(), now: now); await settle()
        session.refresh(input(scope: "other-run"), now: now.addingTimeInterval(1), foreground: true)
        XCTAssertFalse(session.active); XCTAssertNil(session.destination)
        provider.complete(0); await settle(); XCTAssertNil(session.engine.route)
    }
    func testMapAndLabShareCooldownAndThrottleBackoff() async {
        let provider = RoutingDirectionsStub(), now = Date.now
        let engine = RouteLab(provider: provider), session = GroupRouteSession(engine: engine)
        session.start(input(), now: now); await settle()
        provider.complete(0, error: MKError(.loadingThrottled)); await settle()
        session.stop(); engine.select(stage: .staticRoute)
        engine.tick(at: now.addingTimeInterval(30)); engine.calculateManually(); await settle()
        XCTAssertEqual(provider.calls.count, 1); XCTAssertGreaterThan(engine.remainingCooldown, 29)
        engine.tick(at: now.addingTimeInterval(61)); engine.calculateManually(); await settle()
        XCTAssertEqual(provider.calls.count, 2); provider.complete(1); await settle(); engine.pause()
    }
    func testRoutingDoesNotChangeAttendanceOrStartLocationSharing() async throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.loadDemo(.reviewed)
        let before = app.store.state.sessions.last!.counts
        let provider = RoutingDirectionsStub(), session = GroupRouteSession(engine: RouteLab(provider: provider))
        session.start(app.routingInput(for: .leader, destination: .person("P01"))); await settle()
        provider.complete(0); await settle(); session.stop()
        XCTAssertEqual(app.store.state.sessions.last!.counts, before)
        XCTAssertFalse(app.sensor.running); XCTAssertFalse(app.leaderSharing.sensor.running)
        XCTAssertTrue(app.store.state.cloudBindings.isEmpty)
    }
    func testConstructingLiveLabStateDoesNotResetSharedEngine() async {
        let provider = RoutingDirectionsStub()
        let owned = RouteLab(provider: provider)
        owned.select(stage: .movingTarget); owned.start(); await settle()
        let live = LiveExperiment(stage: .realGPS, routing: owned)
        XCTAssertEqual(owned.stage, .movingTarget); XCTAssertTrue(owned.isCalculating)
        live.stop()
        XCTAssertTrue(owned.isCalculating)
        provider.complete(0); await settle(); owned.pause()
        XCTAssertEqual(owned.successes, 1)
    }
    func testLeavingOldLabStageCannotCancelNewStagesRouting() async {
        let provider = RoutingDirectionsStub()
        let owned = RouteLab(provider: provider)
        let oldStage = LiveExperiment(stage: .realGPS, routing: owned)
        owned.select(stage: .backgroundTracking)
        owned.updateLive(origin: .init(latitude: 0, longitude: 0), target: .init(latitude: 0, longitude: 0.002))
        owned.start(); await settle()
        oldStage.stop()
        XCTAssertTrue(owned.isCalculating); XCTAssertTrue(owned.liveInputsReady)
        provider.complete(0); await settle(); owned.pause()
        XCTAssertEqual(owned.successes, 1)
    }

}
