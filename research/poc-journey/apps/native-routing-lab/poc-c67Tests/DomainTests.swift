import XCTest
import SwiftData
@testable import poc_c67

@MainActor final class DomainTests: XCTestCase {
    func testMeetingPointDefaultsToNilAndSurvivesReloadAfterSaveAndClear() throws {
        let container = try SessionStore.container(inMemory: true)
        let store = try SessionStore(container: container)
        XCTAssertNil(store.state.meetingPoint)
        XCTAssertNil(store.state.meetingLatitude); XCTAssertNil(store.state.meetingLongitude)
        let point = MeetingPointSnapshot(latitude: -6.2, longitude: 106.8, radius: 150)
        try store.commit { $0.meetingPoint = point }
        XCTAssertEqual(try SessionStore(container: container).state.meetingPoint, point)
        try store.commit { $0.meetingPoint = nil }
        XCTAssertNil(try SessionStore(container: container).state.meetingPoint)
    }
    func testOldMeetingPointJSONLoadsAndMissingOrPartialCoordinatesStayNil() throws {
        var state = RunState()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["meetingLatitude"] = -6.1754; json["meetingLongitude"] = 106.8272; json["meetingRadius"] = 100
        state = try JSONDecoder().decode(RunState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(state.meetingPoint, MeetingPointSnapshot(latitude: -6.1754, longitude: 106.8272, radius: 100))
        json.removeValue(forKey: "meetingLongitude")
        XCTAssertNil(try JSONDecoder().decode(RunState.self, from: JSONSerialization.data(withJSONObject: json)).meetingPoint)
        json["meetingLatitude"] = NSNull()
        XCTAssertNil(try JSONDecoder().decode(RunState.self, from: JSONSerialization.data(withJSONObject: json)).meetingPoint)
    }
    func testNewQRJourneyAndJoinDoNotInventAMeetingPoint() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.createQRJourney(journey: "Tur", leader: "Budi")
        XCTAssertNil(app.store.state.meetingPoint)
        let invite = JourneyInvite(runID: UUID(), journey: "Tur lain", leader: "TL", leaderRecord: "_TL", token: String(repeating: "a", count: 64), publicKey: Data(repeating: 1, count: 32), expiresAt: .now.addingTimeInterval(300))
        try app.joinQR(invite, name: "Ayu")
        XCTAssertNil(app.store.state.meetingPoint)
    }
    func testNamedParticipantsRemainDistinct() async throws {
        let s = AttendanceSession(name: "Test")
        XCTAssertEqual(s.participants.filter { $0.name == "Ayu" }.count, 2)
        XCTAssertEqual(Set(s.participants.map(\.id)).count, 4)
    }
    func testVerificationIsIdempotentAndRecordedOnce() async throws {
        var s = AttendanceSession(name: "Test")
        let id = UUID()
        try s.apply(.verify, participantID: "P01", actionID: id)
        try s.apply(.verify, participantID: "P01", actionID: id)
        try s.apply(.verify, participantID: "P01")
        XCTAssertEqual(s.counts.verified, 1); XCTAssertEqual(s.events.count, 1)
    }
    func testUndoRequiresReasonAndDoesNotTouchOtherAyu() async throws {
        var s = AttendanceSession(name: "Test")
        try s.apply(.verify, participantID: "P01")
        XCTAssertThrowsError(try s.apply(.undoVerification, participantID: "P01"))
        try s.apply(.undoVerification, participantID: "P01", reason: "Salah nama")
        XCTAssertEqual(s.counts.verified, 0); XCTAssertFalse(s.participants[2].verified)
    }
    func testExclusionAndRejoinNeedNewVerification() async throws {
        var s = AttendanceSession(name: "Test")
        try s.apply(.verify, participantID: "P01")
        XCTAssertThrowsError(try s.apply(.exclude, participantID: "P01", reason: "Belanja"))
        try s.apply(.exclude, participantID: "P01", reason: "Tidak ikut", arrangement: "Bertemu sesi berikutnya")
        XCTAssertEqual(s.counts.expected, 3); XCTAssertEqual(s.counts.verified, 0); XCTAssertEqual(s.counts.excluded, 1)
        XCTAssertThrowsError(try s.apply(.verify, participantID: "P01"))
        try s.apply(.include, participantID: "P01")
        XCTAssertEqual(s.counts.unresolved, 4)
        XCTAssertEqual(s.counts.total, s.counts.expected + s.counts.excluded)
        XCTAssertEqual(s.counts.expected, s.counts.verified + s.counts.unresolved)
    }
    func testFollowUpIsIndependentAndNotDuplicated() async throws {
        var s = AttendanceSession(name: "Test")
        try s.apply(.openFollowUp, participantID: "P01", reason: "Belum kembali")
        try s.apply(.openFollowUp, participantID: "P01", reason: "Telepon")
        XCTAssertEqual(s.events.count, 1)
        try s.apply(.verify, participantID: "P01")
        XCTAssertEqual(s.counts.openCases, 1)
        XCTAssertThrowsError(try s.apply(.resolveFollowUp, participantID: "P01"))
        try s.apply(.resolveFollowUp, participantID: "P01", reason: "Sudah ditemui")
        XCTAssertEqual(s.counts.verified, 1); XCTAssertEqual(s.counts.openCases, 0)
    }
    func testExcludedParticipantCaseStillCounts() async throws {
        var s = AttendanceSession(name: "Test")
        try s.apply(.openFollowUp, participantID: "P01", reason: "Koordinasi")
        try s.apply(.exclude, participantID: "P01", reason: "Skip", arrangement: "Sesi selanjutnya")
        XCTAssertEqual(s.counts.openCases, 1)
        try s.apply(.resolveFollowUp, participantID: "P01", reason: "Disepakati")
        XCTAssertEqual(s.counts.verified, 0)
    }
    func testClosingWithUnresolvedNeedsNoteAndPreservesThem() async throws {
        var s = AttendanceSession(name: "Test")
        XCTAssertThrowsError(try s.apply(.close))
        XCTAssertThrowsError(try s.apply(.closeWithNote, reason: "   "))
        try s.apply(.closeWithNote, reason: "Simulasi prosedur")
        XCTAssertEqual(s.counts.unresolved, 4)
        XCTAssertNotNil(s.closedAt)
        XCTAssertThrowsError(try s.apply(.verify, participantID: "P01"))
    }
    func testNormalCloseRequiresCasesResolvedEvenIfVerified() async throws {
        var s = AttendanceSession(name: "Test")
        for p in s.participants { try s.apply(.verify, participantID: p.id) }
        try s.apply(.openFollowUp, participantID: "P01", reason: "Butuh bantuan")
        XCTAssertThrowsError(try s.apply(.close))
        try s.apply(.resolveFollowUp, participantID: "P01", reason: "Selesai")
        try s.apply(.close)
        XCTAssertNil(s.closureNote); XCTAssertNotNil(s.closedSummary)
    }
    func testAllExcludedRequiresNotedClosure() async throws {
        var s = AttendanceSession(name: "Test")
        for p in s.participants { try s.apply(.exclude, participantID: p.id, reason: "Skip", arrangement: "Sesi besok") }
        XCTAssertThrowsError(try s.apply(.close))
        try s.apply(.closeWithNote, reason: "Tidak ada peserta diharapkan")
        XCTAssertEqual(s.counts.expected, 0)
    }
    func testNextSessionCannotOverlapAndResetsState() async throws {
        var run = RunState()
        XCTAssertThrowsError(try run.nextSession())
        try run.sessions[0].apply(.verify, participantID: "P01")
        try run.sessions[0].apply(.openFollowUp, participantID: "P01", reason: "Uji")
        try run.sessions[0].apply(.exclude, participantID: "P04", reason: "Skip", arrangement: "Besok")
        try run.sessions[0].apply(.closeWithNote, reason: "Uji")
        try run.nextSession()
        XCTAssertEqual(run.sessions[1].counts.verified, 0)
        XCTAssertEqual(run.sessions[1].counts.excluded, 0)
        XCTAssertEqual(run.sessions[1].counts.openCases, 0)
        XCTAssertEqual(run.sessions[0].counts.verified, 1)
    }
    func sample(at date: Date = .now) -> LocationSample {
        LocationSample(runID: UUID(), epoch: UUID(), sequence: 1, latitude: -6, longitude: 106,
                       measuredAt: date, accuracy: 10, reduced: false, simulated: false)
    }
    func testFreshnessNeverChangesByRepeatedReads() async {
        let date = Date(); let s = sample(at: date)
        XCTAssertTrue(LocationRules.freshness(s, now: date).contains("0 dtk"))
        XCTAssertTrue(LocationRules.freshness(s, now: date.addingTimeInterval(61)).contains("Kedaluwarsa"))
        XCTAssertEqual(s.measuredAt, date)
    }
    func testClockSkewAndInvalidSamplesDoNotBecomeFresh() async {
        var s = sample(at: .now.addingTimeInterval(120))
        XCTAssertTrue(LocationRules.freshness(s).contains("Waktu tidak"))
        s.accuracy = -1
        XCTAssertFalse(s.valid)
        XCTAssertTrue(LocationRules.freshness(s).contains("tidak valid"))
        s.accuracy = 10; s.latitude = .infinity; XCTAssertFalse(s.valid)
    }
    func testSequenceEpochAndRunGuards() async {
        let old = sample(); var new = old
        XCTAssertFalse(LocationRules.canReplace(new, old: old, runID: old.runID, epoch: old.epoch))
        new.sequence = 2
        XCTAssertFalse(LocationRules.canReplace(new, old: old, runID: old.runID, epoch: old.epoch))
        new.measuredAt = old.measuredAt.addingTimeInterval(0.01)
        XCTAssertTrue(LocationRules.canReplace(new, old: old, runID: old.runID, epoch: old.epoch))
        XCTAssertFalse(LocationRules.canReplace(new, old: old, runID: UUID(), epoch: old.epoch))
        XCTAssertFalse(LocationRules.canReplace(new, old: old, runID: old.runID, epoch: UUID()))
        new.simulated = true
        XCTAssertFalse(LocationRules.canReplace(new, old: old, runID: old.runID, epoch: old.epoch))
    }
    func testUploadRejectsExpiredStoppedOldAndSimulatedData() async {
        let now = Date(); var s = sample(at: now); let expiry = now.addingTimeInterval(60)
        XCTAssertTrue(LocationRules.mayUpload(s, activeEpoch: s.epoch, runID: s.runID, expiresAt: expiry, now: now))
        XCTAssertFalse(LocationRules.mayUpload(s, activeEpoch: nil, runID: s.runID, expiresAt: expiry, now: now))
        XCTAssertFalse(LocationRules.mayUpload(s, activeEpoch: s.epoch, runID: s.runID, expiresAt: now, now: now))
        s.measuredAt = now.addingTimeInterval(-61)
        XCTAssertFalse(LocationRules.mayUpload(s, activeEpoch: s.epoch, runID: s.runID, expiresAt: expiry, now: now))
        s.measuredAt = now; s.simulated = true
        XCTAssertFalse(LocationRules.mayUpload(s, activeEpoch: s.epoch, runID: s.runID, expiresAt: expiry, now: now))
    }
    func testProximityExpressesUncertaintyAndNeverVerifies() async {
        let now = Date(); var s = sample(at: now)
        XCTAssertTrue(LocationRules.proximity(distance: 10, radius: 100, sample: s, now: now).contains("dekat"))
        XCTAssertTrue(LocationRules.proximity(distance: 300, radius: 100, sample: s, now: now).contains("jauh"))
        XCTAssertTrue(LocationRules.proximity(distance: 100, radius: 100, sample: s, now: now).contains("tidak pasti"))
        s.reduced = true
        XCTAssertTrue(LocationRules.proximity(distance: 10, radius: 100, sample: s, now: now).contains("tidak dapat"))
    }
    func testFailedSaveRollsBackEventAndStateAndRetryCommitsOnce() async throws {
        let container = try SessionStore.container(inMemory: true)
        let store = try SessionStore(container: container)
        let id = UUID(); store.failNextSave = true
        XCTAssertThrowsError(try store.apply(.verify, participantID: "P01", actionID: id))
        XCTAssertEqual(store.state.sessions[0].counts.verified, 0)
        XCTAssertEqual(store.state.sessions[0].events.count, 0)
        let reopened = try SessionStore(container: container)
        XCTAssertEqual(reopened.state.sessions[0].counts.verified, 0)
        try store.apply(.verify, participantID: "P01", actionID: id)
        try store.apply(.verify, participantID: "P01", actionID: id)
        XCTAssertEqual(store.state.sessions[0].counts.verified, 1)
        XCTAssertEqual(store.state.sessions[0].events.count, 1)
    }
    func testCommittedStateReloadsIncludingClosureAndHistory() async throws {
        let container = try SessionStore.container(inMemory: true)
        let store = try SessionStore(container: container)
        try store.apply(.verify, participantID: "P01")
        try store.apply(.closeWithNote, reason: "Uji")
        try store.commit { try $0.nextSession() }
        let reopened = try SessionStore(container: container)
        XCTAssertEqual(reopened.state.sessions.count, 2)
        XCTAssertEqual(reopened.state.sessions[0].counts.verified, 1)
        XCTAssertEqual(reopened.state.sessions[1].counts.verified, 0)
        XCTAssertNotNil(reopened.state.sessions[0].closedAt)
    }
    func testSimulationIsExplicitAndCannotChangeAttendance() async throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        app.simulate("dekat")
        XCTAssertEqual(app.received?.simulated, true)
        XCTAssertEqual(app.store.state.sessions[0].counts.verified, 0)
        try app.store.commit { $0.mode = .real }
        app.clearReceived(); app.simulate("dekat")
        XCTAssertNil(app.received)
        XCTAssertNotNil(app.error)
    }
    func testStartWithoutConsentDoesNotStartSensorOrCreateCloudOwner() async throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.store.commit { $0.mode = .real }
        await app.startSharing(consent: false)
        XCTAssertFalse(app.sensor.running)
        XCTAssertNil(app.store.state.owner)
        XCTAssertNotNil(app.error)
    }
    func testLocalSensorRejectedInSimulationAndResetProtectsOwnedShare() async throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        XCTAssertThrowsError(try app.startLocalSensor())
        let ref = app.cloud.makeReference(runID: app.store.state.runID, participantID: "P01")
        try app.store.commit { $0.owner = ref }
        XCTAssertThrowsError(try app.resetRun(mode: .real))
        XCTAssertEqual(app.store.state.owner, ref)
    }
}
