import XCTest
import CryptoKit
import CoreImage.CIFilterBuiltins
import CoreImage
@testable import poc_c67

@MainActor final class QRPairingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func invitation(key: Curve25519.Signing.PrivateKey = .init()) -> JourneyInvite {
        JourneyInvite(runID: UUID(), journey: "Keliling Jakarta", leader: "Budi", leaderRecord: "_leaderAccount", token: String(repeating: "a", count: 64), publicKey: key.publicKey.rawRepresentation, expiresAt: now.addingTimeInterval(300))
    }
    func member(run: RunState, account: String = "_member", id: String = UUID().uuidString) -> PairedMember {
        let ref = CloudReference(runID: run.runID, participantID: id, zoneName: "C67-zone-" + id, ownerName: account, rootName: "LocationShare", shareName: UUID().uuidString, latestName: "LatestLocation")
        return PairedMember(id: id, name: "Ayu", accountRecord: account, reference: ref)
    }
    func qrRun() -> RunState {
        var run = RunState(); run.qrMembers = []; run.qrJourneyName = "Tur"; run.qrLeaderName = "TL"; run.sessions[0].participants = []; return run
    }
    func testInviteRoundTripAndExpiry() throws {
        let invite = invitation()
        let encoded = invite.encoded
        for _ in 0 ..< 20 { XCTAssertEqual(invite.encoded, encoded) }
        XCTAssertEqual(try JourneyInvite.decode(encoded, now: now), invite)
        XCTAssertThrowsError(try JourneyInvite.decode(invite.encoded, now: invite.expiresAt))
        XCTAssertThrowsError(try JourneyInvite.decode("https://example.com/share", now: now))
        XCTAssertThrowsError(try JourneyInvite.decode(JourneyInvite.prefix + String(repeating: "a", count: 5000), now: now))
    }
    func testUnsupportedOrMalformedInviteCannotBeUsed() throws {
        var invite = invitation(); invite.version = 99
        XCTAssertThrowsError(try JourneyInvite.decode(invite.encoded, now: now))
        invite.version = 3; invite.publicKey = Data([1])
        XCTAssertThrowsError(try invite.validate(now: now))
        invite = invitation(); invite.expiresAt = now.addingTimeInterval(3600)
        XCTAssertThrowsError(try invite.validate(now: now))
    }
    func testActualQRCodeImageCanBeDecoded() throws {
        let invite = invitation()
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(invite.encoded.utf8); filter.correctionLevel = "M"
        let output = try XCTUnwrap(filter.outputImage).transformed(by: .init(scaleX: 5, y: 5))
        let image = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let result = detector.features(in: CIImage(cgImage: image)).first as? CIQRCodeFeature
        XCTAssertEqual(result?.messageString, invite.encoded)
    }
    func testWelcomeMustMatchQRKeyAccountRunAndChallenge() throws {
        let key = Curve25519.Signing.PrivateKey(), invite = invitation(key: key)
        let hello = PairingHello(challenge: UUID(), accountRecord: "_participant", name: "Ayu")
        var welcome = PairingWelcome(inviteID: invite.id, runID: invite.runID, challenge: hello.challenge, participantID: UUID().uuidString, accountRecord: hello.accountRecord, signature: Data())
        welcome.signature = try key.signature(for: welcome.signedData())
        XCTAssertNoThrow(try welcome.validate(invite: invite, hello: hello, now: now))
        var other = welcome; other.participantID = UUID().uuidString
        XCTAssertThrowsError(try other.validate(invite: invite, hello: hello, now: now))
        other = welcome; other.challenge = UUID(); other.signature = try key.signature(for: other.signedData())
        XCTAssertThrowsError(try other.validate(invite: invite, hello: hello, now: now))
        var wrongQR = invite; wrongQR.publicKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        XCTAssertThrowsError(try welcome.validate(invite: wrongQR, hello: hello, now: now))
        var wrongAccount = hello; wrongAccount.accountRecord = "_someoneElse"
        XCTAssertThrowsError(try welcome.validate(invite: invite, hello: wrongAccount, now: now))
    }
    func testReceiptCannotStartDifferentParticipantOrChallenge() throws {
        let key = Curve25519.Signing.PrivateKey(), invite = invitation(key: key)
        let welcome = PairingWelcome(inviteID: invite.id, runID: invite.runID, challenge: UUID(), participantID: UUID().uuidString, accountRecord: "_participant", signature: Data())
        var receipt = PairingReceipt(challenge: welcome.challenge, participantID: welcome.participantID, signature: Data())
        receipt.signature = try key.signature(for: receipt.signedData())
        XCTAssertNoThrow(try receipt.validate(invite: invite, welcome: welcome))
        receipt.participantID = UUID().uuidString
        XCTAssertThrowsError(try receipt.validate(invite: invite, welcome: welcome))
    }
    func testTwoPeopleWithSameNameHaveSeparateBindingsAndNoAttendance() throws {
        var run = qrRun(); let a = member(run: run), b = member(run: run, account: "_second")
        try run.register(a); try run.register(b)
        XCTAssertEqual(run.cloudBindings.count, 2)
        XCTAssertEqual(run.sessions[0].counts.unresolved, 2)
        XCTAssertEqual(run.sessions[0].counts.verified, 0)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(run.sessions[0].participants.map(\.name), ["Ayu", "Ayu"])
    }
    func testRejoiningSameAccountKeepsIDAndDoesNotDuplicateOrResetCheck() throws {
        var run = qrRun(); var a = member(run: run)
        try run.register(a); try run.sessions[0].apply(.verify, participantID: a.id)
        a.reference.zoneName = "C67-replacement"
        try run.register(a)
        XCTAssertEqual(run.qrMembers?.count, 1); XCTAssertEqual(run.cloudBindings.count, 1)
        XCTAssertEqual(run.sessions[0].counts.verified, 1)
        XCTAssertEqual(run.binding, a.reference)
        let bad = member(run: run, account: a.accountRecord)
        XCTAssertThrowsError(try run.register(bad))
    }
    func testWrongRunClosedSessionOrIDCollisionCannotRegister() throws {
        var run = qrRun(); let a = member(run: run)
        try run.register(a)
        var bad = member(run: run, account: "_other", id: a.id)
        XCTAssertThrowsError(try run.register(bad))
        bad = member(run: run); bad.reference.runID = UUID()
        XCTAssertThrowsError(try run.register(bad))
        try run.sessions[0].apply(.closeWithNote, reason: "test")
        XCTAssertThrowsError(try run.register(member(run: run, account: "_third")))
    }
    func testRosterCapAndNextSessionCarryNamesWithoutVerification() throws {
        var run = qrRun()
        for i in 0 ..< 20 { try run.register(member(run: run, account: "_\(i)")) }
        XCTAssertThrowsError(try run.register(member(run: run, account: "_overflow")))
        try run.sessions[0].apply(.verify, participantID: run.qrMembers!.first!.id)
        try run.sessions[0].apply(.closeWithNote, reason: "test")
        try run.nextSession()
        XCTAssertEqual(run.sessions[1].counts.unresolved, 20)
        XCTAssertEqual(run.sessions[1].counts.verified, 0)
        XCTAssertEqual(run.sessions[0].counts.verified, 1)
    }
    func testLegacySnapshotStillLoadsAndPreservesManualBinding() throws {
        var old = RunState(); old.binding = member(run: old).reference
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["qrMembers", "qrJourneyName", "qrLeaderName", "joinedQR"] { json.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(RunState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.binding, old.binding); XCTAssertNil(restored.qrMembers)
        XCTAssertEqual(restored.sessions[0].counts.total, 4)
        XCTAssertEqual(restored.cloudBindings, [old.binding!])
    }
    func testRegistrationSaveFailureCannotExposePartialRoster() throws {
        let store = try SessionStore(container: SessionStore.container(inMemory: true), initial: qrRun())
        let a = member(run: store.state)
        store.failNextSave = true
        XCTAssertThrowsError(try store.commit { try $0.register(a) })
        XCTAssertTrue(store.state.cloudBindings.isEmpty)
        XCTAssertEqual(store.state.sessions[0].participants.count, 0)
        XCTAssertTrue(store.state.sessions[0].events.isEmpty)
        try store.commit { try $0.register(a) }
        XCTAssertEqual(store.state.cloudBindings.count, 1)
    }
    func testCreateQRJourneyRejectsLiveShareAndJoinDoesNotStartGPS() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.createQRJourney(journey: "Tur", leader: "TL")
        XCTAssertEqual(app.store.state.sessions[0].counts.total, 0)
        XCTAssertEqual(app.store.state.mode, .real)
        try app.joinQR(invitation(), name: "Ayu")
        XCTAssertEqual(app.store.state.joinedQR?.participantName, "Ayu")
        XCTAssertFalse(app.sensor.running); XCTAssertNil(app.store.state.owner)
        try app.store.commit { $0.owner = self.member(run: $0).reference }
        XCTAssertThrowsError(try app.createQRJourney(journey: "Ganti", leader: "TL"))
    }
    func testPairedRosterReferencesReloadWithSeparateAccounts() throws {
        let container = try SessionStore.container(inMemory: true)
        let store = try SessionStore(container: container, initial: qrRun())
        let first = member(run: store.state), second = member(run: store.state, account: "_second")
        try store.commit { try $0.register(first); try $0.register(second) }
        let restored = try SessionStore(container: container)
        XCTAssertEqual(restored.state.cloudBindings, [first.reference, second.reference])
        XCTAssertEqual(restored.state.qrMembers?.map(\.accountRecord), ["_member", "_second"])
        XCTAssertEqual(restored.state.sessions[0].counts.unresolved, 2)
        XCTAssertEqual(restored.state.qrJourneyName, "Tur")
    }
}
