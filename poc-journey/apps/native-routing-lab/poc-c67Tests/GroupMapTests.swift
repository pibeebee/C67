import XCTest
import CryptoKit
@testable import poc_c67

@MainActor final class GroupMapTests: XCTestCase {
    func sample(runID: UUID = UUID(), epoch: UUID = UUID(), at: Date = .now, sequence: Int = 1) -> LocationSample {
        LocationSample(runID: runID, epoch: epoch, sequence: sequence, latitude: -6.1754, longitude: 106.8272, measuredAt: at, accuracy: 10, reduced: false, simulated: false)
    }
    func testDemoShowsAllParticipantsAtOnceAndLeaderWithoutChangingAttendance() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.loadDemo(.regroup)
        let counts = app.store.state.sessions.last!.counts
        let points = app.mapPoints(for: .leader)
        XCTAssertEqual(points.filter { $0.kind == .participant }.count, 4)
        XCTAssertEqual(points.filter { $0.kind == .leader }.count, 1)
        XCTAssertEqual(Set(points.map(\.id)).count, 5)
        XCTAssertEqual(points.filter { $0.kind == .participant }.map(\.id), ["P01", "P02", "P03", "P04"])
        XCTAssertTrue(points.first { $0.id == "P03" }!.stale)
        XCTAssertEqual(app.store.state.sessions.last!.counts, counts)
    }
    func testParticipantMapDoesNotExposeOtherParticipants() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.loadDemo(.reviewed)
        XCTAssertEqual(Set(app.mapPoints(for: .participant).map(\.id)), ["TL", "YOU"])
        XCTAssertFalse(app.mapPoints(for: .participant).contains { $0.kind == .participant })
    }
    func testMissingRealLocationsAreNotPlacedAtMeetingPoint() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.store.commit { $0.mode = .real }
        XCTAssertEqual(app.store.state.sessions[0].participants.count, 4)
        XCTAssertTrue(app.mapPoints(for: .leader).isEmpty)
        XCTAssertTrue(app.mapPoints(for: .participant).isEmpty)
    }
    func testLocalMapLocationWorksWithoutStartingEitherSharingSession() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.store.commit { $0.mode = .real }
        let own = sample(runID: app.store.state.runID)
        let leader = app.mapPoints(for: .leader, localSample: own)
        XCTAssertEqual(leader.map(\.id), ["TL"])
        XCTAssertEqual(leader.first?.kind, .you)
        let participant = app.mapPoints(for: .participant, localSample: own)
        XCTAssertEqual(participant.map(\.id), ["YOU"])
        XCTAssertFalse(app.sensor.running); XCTAssertFalse(app.leaderSharing.sensor.running)
        XCTAssertNil(app.store.state.owner); XCTAssertNil(app.store.state.leaderBinding)
        XCTAssertFalse(app.leaderSharing.hasConnections)
    }
    func testLocalMapRejectsWrongRunInvalidAndFutureSamples() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.store.commit { $0.mode = .real }
        let now = Date.now
        XCTAssertTrue(app.mapPoints(for: .leader, localSample: sample(), now: now).isEmpty)
        var own = sample(runID: app.store.state.runID, at: now)
        own.latitude = 91
        XCTAssertTrue(app.mapPoints(for: .participant, localSample: own, now: now).isEmpty)
        own.latitude = -6; own.measuredAt = now.addingTimeInterval(30)
        XCTAssertTrue(app.mapPoints(for: .leader, localSample: own, now: now).isEmpty)
    }
    func testRealLocalSampleDoesNotLeakIntoDemo() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        XCTAssertTrue(app.mapPoints(for: .leader, localSample: sample(runID: app.store.state.runID)).isEmpty)
    }
    func testWelcomeAllowsSignedAbsentMeetingPointAndRejectsTampering() throws {
        let key = Curve25519.Signing.PrivateKey()
        let invite = JourneyInvite(runID: UUID(), journey: "Tur", leader: "TL", leaderRecord: "_TL", token: String(repeating: "a", count: 64), publicKey: key.publicKey.rawRepresentation, expiresAt: .now.addingTimeInterval(300))
        let hello = PairingHello(challenge: UUID(), accountRecord: "_P", name: "Ayu")
        var welcome = PairingWelcome(inviteID: invite.id, runID: invite.runID, challenge: hello.challenge, participantID: UUID().uuidString, accountRecord: hello.accountRecord, signature: Data(), leaderURL: "https://www.icloud.com/share/example", meetingPoint: nil)
        welcome.signature = try key.signature(for: welcome.signedData())
        let decoded = try JSONDecoder().decode(PairingWelcome.self, from: JSONEncoder().encode(welcome))
        XCTAssertNil(decoded.meetingPoint)
        XCTAssertNoThrow(try decoded.validate(invite: invite, hello: hello))
        welcome.meetingPoint = MeetingPointSnapshot(latitude: -6, longitude: 106, radius: 100)
        XCTAssertThrowsError(try welcome.validate(invite: invite, hello: hello))
        welcome.meetingPoint?.latitude = 99
        welcome.signature = try key.signature(for: welcome.signedData())
        XCTAssertThrowsError(try welcome.validate(invite: invite, hello: hello))
        var old = invite; old.version = 2
        XCTAssertThrowsError(try JourneyInvite.decode(old.encoded))
    }
    func testMapKeepsStaleMeasurementButRejectsExpiredLeaseWrongRunAndInvalidCoordinates() {
        let now = Date.now, run = UUID()
        let old = sample(runID: run, at: now.addingTimeInterval(-180))
        var location = ParticipantLocation(sample: old, receivedAt: now, expiresAt: now.addingTimeInterval(300), epoch: old.epoch)
        XCTAssertNotNil(location.displayable(runID: run, now: now))
        XCTAssertTrue(LocationRules.freshness(location.sample, now: now).contains("Kedaluwarsa"))
        XCTAssertNil(location.displayable(runID: UUID(), now: now))
        location.expiresAt = now; XCTAssertNil(location.displayable(runID: run, now: now))
        location.expiresAt = now.addingTimeInterval(300); location.sample?.latitude = 100
        XCTAssertNil(location.displayable(runID: run, now: now))
        location.sample = sample(runID: run, at: now.addingTimeInterval(30))
        XCTAssertNil(location.displayable(runID: run, now: now))
    }
    func testPausedLeaderClearsCoordinatesAndNewEpochDoesNotReuseOldSample() {
        let now = Date.now, run = UUID(), epoch = UUID()
        let s = sample(runID: run, epoch: epoch, at: now)
        var cache = ParticipantLocation().applying(RemoteLocation(sample: s, epoch: epoch, expiresAt: now.addingTimeInterval(300), state: "active"), runID: run, now: now)
        XCTAssertEqual(cache.sample, s)
        cache = cache.applying(RemoteLocation(sample: nil, epoch: epoch, expiresAt: .distantPast, state: "paused"), runID: run, now: now)
        XCTAssertNil(cache.sample); XCTAssertNil(cache.receivedAt)
        cache = cache.applying(RemoteLocation(sample: s, epoch: UUID(), expiresAt: now.addingTimeInterval(300), state: "active"), runID: run, now: now)
        XCTAssertNil(cache.sample)
    }
    func testRepeatedLeaderFetchDoesNotRefreshMeasurementAgeOrAcceptOldSequence() {
        let now = Date.now, run = UUID(), epoch = UUID()
        let s = sample(runID: run, epoch: epoch, at: now.addingTimeInterval(-10), sequence: 2)
        let remote = RemoteLocation(sample: s, epoch: epoch, expiresAt: now.addingTimeInterval(300), state: "active")
        let first = ParticipantLocation().applying(remote, runID: run, now: now)
        let repeated = first.applying(remote, runID: run, now: now.addingTimeInterval(30))
        XCTAssertEqual(repeated.receivedAt, first.receivedAt)
        XCTAssertEqual(repeated.sample?.measuredAt, s.measuredAt)
        let older = sample(runID: run, epoch: epoch, at: now, sequence: 1)
        XCTAssertEqual(first.applying(RemoteLocation(sample: older, epoch: epoch, expiresAt: now.addingTimeInterval(300), state: "active"), runID: run, now: now).sample, s)
    }
    func testLeaderCannotStartWithoutConsentAndNoSensorStartsOnInit() async throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.createQRJourney(journey: "Tur", leader: "TL")
        do { try await app.leaderSharing.start(consent: false); XCTFail("Start without consent") } catch {}
        XCTAssertFalse(app.leaderSharing.sensor.running)
        XCTAssertFalse(app.leaderSharing.hasConnections)
        XCTAssertNil(app.leaderSharing.expiresAt)
    }
    func testLeaderReferencesPersistSeparatelyAndBlockRunReplacement() throws {
        let container = try SessionStore.container(inMemory: true)
        let app = try POCController(container: container, testing: true)
        try app.createQRJourney(journey: "Tur", leader: "TL")
        let ref = app.cloud.makeReference(runID: app.store.state.runID, participantID: "TL")
        try app.store.commit { $0.leaderShares = [LeaderShare(accountRecord: "_participant", reference: ref)] }
        XCTAssertFalse(app.canReplaceRun)
        XCTAssertThrowsError(try app.resetRun(mode: .simulation))
        XCTAssertThrowsError(try app.joinRun(UUID().uuidString))
        let loaded = try SessionStore(container: container)
        XCTAssertEqual(loaded.state.leaderShares?.first?.reference, ref)
        XCTAssertTrue(loaded.state.cloudBindings.isEmpty)
    }
    func testLeaderBindingBlocksResetAndOldSnapshotStillDecodes() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        let ref = app.cloud.makeReference(runID: app.store.state.runID, participantID: "TL")
        try app.store.commit { $0.leaderBinding = ref }
        XCTAssertFalse(app.canReplaceRun)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(app.store.state)) as? [String: Any])
        json.removeValue(forKey: "leaderBinding"); json.removeValue(forKey: "leaderShares")
        let restored = try JSONDecoder().decode(RunState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.leaderBinding); XCTAssertNil(restored.leaderShares)
        XCTAssertEqual(restored.sessions[0].participants.count, 4)
    }
    func testLeaderURLIsCoveredByWelcomeSignatureAndOldQRVersionRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let invite = JourneyInvite(runID: UUID(), journey: "Tur", leader: "TL", leaderRecord: "_TL", token: String(repeating: "a", count: 64), publicKey: key.publicKey.rawRepresentation, expiresAt: .now.addingTimeInterval(300))
        let hello = PairingHello(challenge: UUID(), accountRecord: "_P", name: "Ayu")
        var welcome = PairingWelcome(inviteID: invite.id, runID: invite.runID, challenge: hello.challenge, participantID: UUID().uuidString, accountRecord: hello.accountRecord, signature: Data(), leaderURL: "https://www.icloud.com/share/example")
        welcome.signature = try key.signature(for: welcome.signedData())
        XCTAssertNoThrow(try welcome.validate(invite: invite, hello: hello))
        welcome.leaderURL = "https://www.icloud.com/share/other"
        XCTAssertThrowsError(try welcome.validate(invite: invite, hello: hello))
        var old = invite; old.version = 1
        XCTAssertThrowsError(try JourneyInvite.decode(old.encoded))
    }
    func testMeetingPointSnapshotValidatesBoundsAndIsSigned() throws {
        XCTAssertTrue(MeetingPointSnapshot(latitude: -6.2, longitude: 106.8, radius: 100).valid)
        XCTAssertFalse(MeetingPointSnapshot(latitude: 95, longitude: 106.8, radius: 100).valid)
        XCTAssertFalse(MeetingPointSnapshot(latitude: -6.2, longitude: 106.8, radius: -1).valid)
        let key = Curve25519.Signing.PrivateKey()
        let invite = JourneyInvite(runID: UUID(), journey: "Tur", leader: "TL", leaderRecord: "_TL", token: String(repeating: "a", count: 64), publicKey: key.publicKey.rawRepresentation, expiresAt: .now.addingTimeInterval(300))
        let hello = PairingHello(challenge: UUID(), accountRecord: "_P", name: "Ayu")
        var welcome = PairingWelcome(inviteID: invite.id, runID: invite.runID, challenge: hello.challenge, participantID: UUID().uuidString, accountRecord: hello.accountRecord, signature: Data(), meetingPoint: MeetingPointSnapshot(latitude: -6.2, longitude: 106.8, radius: 100))
        welcome.signature = try key.signature(for: welcome.signedData())
        XCTAssertNoThrow(try welcome.validate(invite: invite, hello: hello))
        welcome.meetingPoint?.radius = 1000
        XCTAssertThrowsError(try welcome.validate(invite: invite, hello: hello))
    }
}
